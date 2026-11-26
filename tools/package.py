#!/usr/bin/env python3
"""Assemble a release bundle of the native library and check its dependencies.

The bundle keeps the native library and the ICU data file together, because
the ICU loader looks for `icudtl.dat` next to the executable or next to the
library. The script also reports the runtime dependencies of the library so a
missing private dependency is caught before a release, not on a user machine.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NATIVE_BUILD = ROOT / "native" / "build"
RELEASE = ROOT / "build" / "release"
INSTALL_PREFIX = ROOT / "build" / "release" / "install-tree"

LIBRARY_NAMES = {
    "Windows": "dui_native.dll",
    "Darwin": "libdui_native.dylib",
    "Linux": "libdui_native.so",
}

# A dependency is private when it is not part of the operating system and has
# to be shipped next to the library.
WINDOWS_SYSTEM_PREFIXES = ("api-ms-", "ext-ms-")


def run(command: list[str]) -> str:
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout


def pe_imports(path: Path) -> list[str]:
    """Reads the imported DLL names from a PE image."""
    data = path.read_bytes()
    if data[:2] != b"MZ":
        raise ValueError(f"{path.name} is not a PE image.")
    pe_offset = int.from_bytes(data[0x3C:0x40], "little")
    if data[pe_offset:pe_offset + 4] != b"PE\0\0":
        raise ValueError(f"{path.name} has no PE signature.")
    coff = pe_offset + 4
    section_count = int.from_bytes(data[coff + 2:coff + 4], "little")
    optional_size = int.from_bytes(data[coff + 16:coff + 18], "little")
    optional = coff + 20
    magic = int.from_bytes(data[optional:optional + 2], "little")
    directories = optional + (112 if magic == 0x20B else 96)
    import_rva = int.from_bytes(data[directories + 8:directories + 12], "little")
    if not import_rva:
        return []

    sections = []
    section_base = optional + optional_size
    for index in range(section_count):
        base = section_base + index * 40
        virtual_size = int.from_bytes(data[base + 8:base + 12], "little")
        virtual_address = int.from_bytes(data[base + 12:base + 16], "little")
        raw_size = int.from_bytes(data[base + 16:base + 20], "little")
        raw_pointer = int.from_bytes(data[base + 20:base + 24], "little")
        sections.append((virtual_address, max(virtual_size, raw_size), raw_pointer, raw_size))

    def to_offset(rva: int) -> int:
        for virtual_address, span, raw_pointer, raw_size in sections:
            if virtual_address <= rva < virtual_address + span:
                return raw_pointer + (rva - virtual_address)
        raise ValueError(f"Cannot map the RVA {rva} of {path.name}.")

    names = []
    descriptor = to_offset(import_rva)
    while True:
        entry = data[descriptor:descriptor + 20]
        if len(entry) < 20 or entry == b"\0" * 20:
            break
        name_rva = int.from_bytes(entry[12:16], "little")
        if not name_rva:
            break
        offset = to_offset(name_rva)
        end = data.index(b"\0", offset)
        names.append(data[offset:end].decode("ascii"))
        descriptor += 20
    return names


def elf_dependencies(path: Path) -> list[tuple[str, str]]:
    """Reads the shared library dependencies of an ELF image.

    Every entry keeps the resolved path, because it tells whether a dependency
    comes from the system or from the build tree of this project.
    """
    output = run(["ldd", str(path)])
    dependencies = []
    for line in output.splitlines():
        line = line.strip()
        if not line or "=>" not in line:
            continue
        name, _, rest = line.partition("=>")
        location = rest.strip().split(" (")[0].strip()
        dependencies.append((name.strip(), location))
    return dependencies


def macho_dependencies(path: Path) -> list[tuple[str, str]]:
    """Reads the linked libraries of a Mach-O image."""
    output = run(["otool", "-L", str(path)])
    dependencies = []
    for line in output.splitlines()[1:]:
        line = line.strip()
        if not line:
            continue
        name, _, location = line.partition(" ")
        dependencies.append((name, location.strip()))
    return dependencies


def runtime_dependencies(system: str, library: Path) -> list[tuple[str, str]]:
    """Returns the runtime dependencies with the place they are resolved from."""
    if system == "Windows":
        return [(name, "") for name in pe_imports(library)]
    if system == "Linux":
        return elf_dependencies(library)
    return macho_dependencies(library)


def _is_inside_project(location: str) -> bool:
    """Reports whether a resolved path belongs to this project."""
    if not location:
        return False
    try:
        resolved = Path(location).resolve()
        resolved.relative_to(ROOT.resolve())
        return True
    except (ValueError, OSError):
        return False


def is_system_dependency(system: str, name: str, location: str) -> bool:
    """Reports whether a dependency is provided by the operating system.

    A dependency is private when it has to be shipped next to the library: a
    library of the build tree of this project, or a library that is looked up
    through an rpath on macOS.
    """
    if system == "Windows":
        if name.lower().startswith(WINDOWS_SYSTEM_PREFIXES):
            return True
        system32 = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32"
        return (system32 / name).exists()
    if system == "Darwin":
        # A library of the system or of the frameworks is always available.
        if location.startswith(("@rpath/", "/usr/lib/", "/System/")):
            return not location.startswith("@rpath/")
        return True
    # Linux: everything outside of the build tree of this project is provided
    # by the system, even a library of a distribution package.
    return not _is_inside_project(location)


def install_native(prefix: Path, system: str) -> tuple[Path, Path]:
    """Installs the native library with the CMake install rules.

    The install rules decide where the library and the ICU data file go, so
    the release bundle is built from the install tree. That keeps the shipped
    layout and the documented install layout in sync.
    """
    cmake = shutil.which("cmake")
    if not cmake:
        raise RuntimeError("cmake was not found, the native library cannot be installed.")

    # A relative prefix keeps backslashes out of the generated install script.
    prefix_argument = Path(os.path.relpath(prefix, ROOT)).as_posix()
    result = subprocess.run(
        [cmake, "--install", str(NATIVE_BUILD.relative_to(ROOT)), "--prefix", prefix_argument],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "cmake --install failed:\n" + (result.stderr or result.stdout).strip()
        )

    directory = prefix / ("bin" if system == "Windows" else "lib")
    library = directory / LIBRARY_NAMES[system]
    icu = directory / "icudtl.dat"
    if not library.exists() or not icu.exists():
        raise RuntimeError(f"the install tree {prefix} is incomplete.")
    return library, icu


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def archive_name(system: str, version: str, machine: str) -> str:
    platform_name = {
        "Windows": "windows",
        "Darwin": "macos",
        "Linux": "linux",
    }[system]
    return f"dui_native-{version}-{platform_name}-{machine}"


def write_archive(directory: Path, system: str) -> Path:
    """Writes a reproducible archive of the bundle directory."""
    if system == "Windows":
        archive = directory.parent / f"{directory.name}.zip"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zip_file:
            for path in sorted(directory.rglob("*")):
                if not path.is_file():
                    continue
                info = zipfile.ZipInfo(
                    f"{directory.name}/{path.relative_to(directory).as_posix()}",
                    date_time=(1980, 1, 1, 0, 0, 0),
                )
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o644 << 16
                zip_file.writestr(info, path.read_bytes())
        return archive
    import tarfile

    archive = directory.parent / f"{directory.name}.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        for path in sorted(directory.rglob("*")):
            if not path.is_file():
                continue
            info = tar.gettarinfo(str(path), f"{directory.name}/{path.relative_to(directory).as_posix()}")
            info.mtime = 0
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            info.mode = 0o644
            with path.open("rb") as stream:
                tar.addfile(info, stream)
    return archive


def verify_bundle(directory: Path) -> bool:
    """Runs a compiled program that loads the library next to the executable.

    The program is started from another working directory, so the library is
    only found through the executable directory candidate.
    """
    dart = shutil.which("dart")
    if not dart:
        print("WARNING: the Dart SDK was not found, skipping the bundle check.")
        return True
    source = ROOT / "tool" / "verify_native.dart"
    if not source.exists():
        print(f"WARNING: {source} is missing, skipping the bundle check.")
        return True

    with tempfile.TemporaryDirectory() as temporary:
        workspace = Path(temporary)
        executable = workspace / ("verify_native.exe" if platform.system() == "Windows" else "verify_native")
        result = subprocess.run(
            [dart, "compile", "exe", str(source), "-o", str(executable)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            print("ERROR: the verification program did not compile.")
            print(result.stdout)
            print(result.stderr)
            return False
        for name in (LIBRARY_NAMES[platform.system()], "icudtl.dat"):
            shutil.copy2(directory / name, workspace / name)

        working_directory = workspace / "run"
        working_directory.mkdir()
        result = subprocess.run(
            [str(executable)],
            cwd=working_directory,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            print("ERROR: the packaged program did not load the native library.")
            print(result.stdout)
            print(result.stderr)
            return False
        print(f"Bundle check: {result.stdout.strip()}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--version",
        default="0.1.0",
        help="version of the bundle",
    )
    parser.add_argument(
        "--check-only",
        action="store_true",
        help="only report the runtime dependencies and the ICU data file",
    )
    parser.add_argument(
        "--no-verify",
        action="store_true",
        help="skip the check that compiles a program against the bundle",
    )
    parser.add_argument(
        "--skip-install",
        action="store_true",
        help="package from the build directory instead of the CMake install tree",
    )
    args = parser.parse_args()

    system = platform.system()
    machine = platform.machine().lower()
    if machine in ("amd64", "x86_64"):
        machine = "x64"
    elif machine in ("arm64", "aarch64"):
        machine = "arm64"

    if args.skip_install:
        library = NATIVE_BUILD / "bin" / LIBRARY_NAMES[system]
        icu = library.parent / "icudtl.dat"
    else:
        try:
            library, icu = install_native(INSTALL_PREFIX, system)
            print(f"Install tree: {INSTALL_PREFIX}")
        except RuntimeError as error:
            print(f"ERROR: {error}", file=sys.stderr)
            return 1

    if not library.exists():
        print(
            f"ERROR: {library} is missing. Run tools/bootstrap_native.py first.",
            file=sys.stderr,
        )
        return 1

    if not icu.exists():
        print(
            f"ERROR: {icu} is missing. The ICU loader needs it next to the "
            "library or next to the executable.",
            file=sys.stderr,
        )
        return 1

    dependencies = runtime_dependencies(system, library)
    private = [
        name
        for name, location in dependencies
        if not is_system_dependency(system, name, location)
    ]
    print(f"Library: {library} ({library.stat().st_size} bytes)")
    print(f"ICU data: {icu} ({icu.stat().st_size} bytes)")
    print(f"Runtime dependencies: {len(dependencies)}")
    for name, location in dependencies:
        marker = "private" if name in private else "system"
        suffix = f" -> {location}" if location else ""
        print(f"  - {name} ({marker}){suffix}")
    if private:
        print(
            "ERROR: private dependencies have to be shipped next to the "
            f"library: {', '.join(private)}",
            file=sys.stderr,
        )
        return 1

    if args.check_only:
        print("Runtime dependency check passed.")
        return 0

    name = archive_name(system, args.version, machine)
    directory = RELEASE / name
    if directory.exists():
        shutil.rmtree(directory)
    directory.mkdir(parents=True)
    shutil.copy2(library, directory / library.name)
    shutil.copy2(icu, directory / icu.name)

    manifest = {
        "name": "dui_native",
        "version": args.version,
        "platform": system,
        "architecture": machine,
        "library": library.name,
        "icuData": icu.name,
        "dependencies": [name for name, _ in dependencies],
        "sha256": {
            library.name: sha256(directory / library.name),
            icu.name: sha256(directory / icu.name),
        },
    }
    (directory / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    archive = write_archive(directory, system)
    print(f"Bundle: {directory}")
    print(f"Archive: {archive} (sha256 {sha256(archive)})")

    if not args.no_verify and not verify_bundle(directory):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
