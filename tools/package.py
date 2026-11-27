#!/usr/bin/env python3
"""Assemble a release bundle of the native library and check its dependencies.

On Windows the bundle keeps the native library and the ICU data file together,
because the ICU loader looks for `icudtl.dat` next to the executable or next to
the library. On Linux and macOS Skia links the ICU data into the library, so
the file is not part of the bundle there. The script also reports the runtime
dependencies of the library so a missing private dependency is caught before a
release, not on a user machine.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
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


def requires_icu(system: str) -> bool:
    """Tells whether the platform loads the ICU data from the disk.

    Windows reads `icudtl.dat` next to the executable or next to the library,
    on Linux and macOS Skia links the ICU data into the library itself.
    """
    return system == "Windows"


def strip_library(library: Path, system: str) -> None:
    """Removes the symbol table from a built library.

    Skia is linked statically, so the library keeps the symbol table of every
    static library it pulls in. On Linux that makes the file more than two
    hundred megabytes, which is too much for a published package, and the
    symbols are not needed to run it.
    """
    if system == "Windows":
        # The MSVC linker already writes a library without a symbol table.
        return

    tool = shutil.which("strip")
    if not tool:
        print(
            "WARNING: strip was not found, the library keeps its symbol table."
        )
        return

    # The GNU strip and the one of macOS know different options.
    arguments = ["-x"] if system == "Darwin" else ["--strip-unneeded"]
    result = subprocess.run(
        [tool, *arguments, str(library)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        print(
            f"WARNING: the library {library} was not stripped: "
            f"{(result.stderr or result.stdout).strip()}",
            file=sys.stderr,
        )


def install_native(prefix: Path, system: str) -> tuple[Path, Path | None]:
    """Installs the native library with the CMake install rules.

    The install rules decide where the library and the ICU data file go, so
    the release bundle is built from the install tree. That keeps the shipped
    layout and the documented install layout in sync. The ICU data file is
    only installed on Windows, so it is only expected there.
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
    if not library.exists():
        raise RuntimeError(f"the install tree {prefix} is incomplete.")

    icu = directory / "icudtl.dat"
    if requires_icu(system):
        if not icu.exists():
            raise RuntimeError(
                f"the install tree {prefix} has no ICU data file, but Windows "
                "loads it from the disk."
            )
        return library, icu
    strip_library(library, system)
    return library, None


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


def platform_key(system: str, machine: str) -> str:
    """The folder name of a platform, the same one the Dart loader looks for."""
    platform_name = {
        "Windows": "windows",
        "Darwin": "macos",
        "Linux": "linux",
    }[system]
    return f"{platform_name}-{machine}"


def collect_platform_artifacts(
    staging: Path,
    key: str,
    library: Path,
    icu: Path | None,
) -> Path:
    """Copies the built artifacts of one platform into the staging area.

    Every platform build drops its library and the ICU data file into
    `staging/<platform>/`, and the distribution takes them from there. That
    way a release can be assembled from builds of different machines. Only
    Windows needs the ICU data file, on the other systems Skia links the ICU
    data into the library.
    """
    directory = staging / key
    if directory.exists():
        shutil.rmtree(directory)
    directory.mkdir(parents=True)
    shutil.copy2(library, directory / library.name)
    if icu is not None:
        if not icu.exists():
            raise RuntimeError(f"the ICU data file {icu} is missing.")
        shutil.copy2(icu, directory / icu.name)
    return directory


def build_distribution(staging: Path, output: Path, version: str) -> dict:
    """Assembles the package folder that is published or handed to a user.

    The folder holds the Dart sources, the executable that copies the native
    library, and the prebuilt library of every platform in the staging area.
    """
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)

    shutil.copytree(ROOT / "lib", output / "lib")
    if (ROOT / "bin").exists():
        shutil.copytree(ROOT / "bin", output / "bin")
    if (ROOT / "example").exists():
        shutil.copytree(ROOT / "example", output / "example")
    for name in ("README.md", "CHANGELOG.md", "LICENSE"):
        source = ROOT / name
        if source.exists():
            shutil.copy2(source, output / name)

    # The published package must not keep the "do not publish" marker.
    pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    pubspec = re.sub(r"^publish_to:.*\n", "", pubspec, flags=re.MULTILINE)
    (output / "pubspec.yaml").write_text(pubspec, encoding="utf-8")

    # The distribution lives inside the ignored build folder, and pub reads the
    # ignore rules of the package root. Without this file the whole package
    # would be hidden and the upload would be empty.
    (output / ".pubignore").write_text(
        "# The distribution folder holds everything that gets published.\n",
        encoding="utf-8",
    )

    platforms = {}
    native_root = output / "native" / "bin"
    for directory in sorted(staging.iterdir()) if staging.exists() else []:
        if not directory.is_dir():
            continue
        files = sorted(file for file in directory.iterdir() if file.is_file())
        if not files:
            continue
        target = native_root / directory.name
        target.mkdir(parents=True, exist_ok=True)
        hashes = {}
        for file in files:
            shutil.copy2(file, target / file.name)
            hashes[file.name] = sha256(target / file.name)
        platforms[directory.name] = {
            "files": [file.name for file in files],
            "sha256": hashes,
        }

    manifest = {
        "name": "duix",
        "version": version,
        "platforms": platforms,
        "size": sum(
            file.stat().st_size for file in output.rglob("*") if file.is_file()
        ),
    }
    (output / "dist-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest


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
            source = directory / name
            if source.exists():
                shutil.copy2(source, workspace / name)

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
    parser.add_argument(
        "--dist",
        action="store_true",
        help="assemble the distribution folder of the package",
    )
    parser.add_argument(
        "--staging",
        default=str(ROOT / "build" / "dist"),
        help="folder that holds the built library of every platform",
    )
    parser.add_argument(
        "--dist-output",
        default=str(ROOT.parent / "duix-publish"),
        help="folder of the assembled distribution; it has to sit outside the "
        "repository, because pub hides every folder that the ignore rules "
        "of the repository exclude",
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
        icu = library.parent / "icudtl.dat" if requires_icu(system) else None
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

    if icu is not None and not icu.exists():
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
    if icu is not None:
        print(f"ICU data: {icu} ({icu.stat().st_size} bytes)")
    else:
        print("ICU data: linked into the library")
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
    strip_library(directory / library.name, system)
    if icu is not None:
        shutil.copy2(icu, directory / icu.name)

    manifest = {
        "name": "dui_native",
        "version": args.version,
        "platform": system,
        "architecture": machine,
        "library": library.name,
        "icuData": icu.name if icu is not None else None,
        "dependencies": [name for name, _ in dependencies],
        "sha256": {
            library.name: sha256(directory / library.name),
            **({icu.name: sha256(directory / icu.name)} if icu is not None else {}),
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

    if args.dist:
        staging = Path(args.staging)
        key = platform_key(system, machine)
        collect_platform_artifacts(staging, key, library, icu)
        output = Path(args.dist_output)
        manifest = build_distribution(staging, output, args.version)
        print(f"Distribution: {output}")
        for platform_name, files in manifest["platforms"].items():
            print(f"  - {platform_name}: {', '.join(files['files'])}")
        missing = [
            expected
            for expected in (
                "windows-x64",
                "windows-arm64",
                "macos-x64",
                "macos-arm64",
                "linux-x64",
                "linux-arm64",
            )
            if expected not in manifest["platforms"]
        ]
        if missing:
            print(
                "WARNING: the distribution has no library for: "
                f"{', '.join(missing)}",
                file=sys.stderr,
            )
        print(
            "Publish it with: dart pub publish --directory "
            f"{output}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
