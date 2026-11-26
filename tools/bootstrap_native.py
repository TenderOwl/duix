#!/usr/bin/env python3
"""Build pinned SDL3/Skia dependencies and the dui_native library."""

from __future__ import annotations

import argparse
import os
import platform
import re
import shutil
import stat
import subprocess
import sys
from pathlib import Path

SDL_VERSION = "release-3.4.20"
SKIA_BRANCH = "chrome/m148"

ROOT = Path(__file__).resolve().parents[1]
DEPS = ROOT / ".native-deps"
SOURCES = DEPS / "src"
PREFIX = DEPS / "prefix"
SDL_SOURCE = SOURCES / "SDL"
SKIA_SOURCE = SOURCES / "skia"
NATIVE_BUILD = ROOT / "native" / "build"


def run(command: list[str], cwd: Path | None = None) -> None:
    print("\n+", " ".join(command), flush=True)
    subprocess.run(command, cwd=cwd or ROOT, check=True)


def require_tools() -> None:
    missing = [name for name in ("cmake", "ninja", "git") if not shutil.which(name)]
    if missing:
        raise RuntimeError(
            "Missing tools: "
            + ", ".join(missing)
            + ". Add them to PATH and restart the terminal."
        )

    if platform.system() == "Windows":
        if not shutil.which("clang-cl"):
            raise RuntimeError(
                "clang-cl was not found. Install LLVM/Clang and run from a Visual "
                "Studio x64 Native Tools environment so the Windows SDK is visible."
            )
    elif not shutil.which("c++"):
        raise RuntimeError("A C++ compiler was not found (c++).")


def clone_pinned(repository: str, branch: str, destination: Path) -> None:
    if destination.exists():
        print(f"Using existing source: {destination}")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    run([
        "git",
        "clone",
        "--depth",
        "1",
        "--branch",
        branch,
        repository,
        str(destination),
    ])


def target_cpu() -> str:
    machine = platform.machine().lower()
    if machine in ("arm64", "aarch64"):
        return "arm64"
    if machine in ("amd64", "x86_64"):
        return "x64"
    raise RuntimeError(f"Unsupported CPU architecture: {platform.machine()}")


def build_sdl() -> Path:
    clone_pinned("https://github.com/libsdl-org/SDL.git", SDL_VERSION, SDL_SOURCE)
    build = DEPS / "build" / "SDL"
    prepare_cmake_build(build, SDL_SOURCE)
    command = [
        "cmake",
        "-S",
        str(SDL_SOURCE),
        "-B",
        str(build),
        "-G",
        "Ninja",
        "-DCMAKE_BUILD_TYPE=Release",
        f"-DCMAKE_INSTALL_PREFIX={PREFIX}",
        "-DSDL_SHARED=OFF",
        "-DSDL_STATIC=ON",
        "-DSDL_TEST_LIBRARY=OFF",
    ]
    if platform.system() == "Windows":
        command += [
            "-DCMAKE_C_COMPILER=clang-cl",
            "-DCMAKE_CXX_COMPILER=clang-cl",
            "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded",
        ]
    run(command)
    run(["cmake", "--build", str(build), "--parallel"])
    run(["cmake", "--install", str(build)])
    for directory in (PREFIX / "lib" / "cmake" / "SDL3", PREFIX / "cmake"):
        if (directory / "SDL3Config.cmake").exists():
            return directory
    raise RuntimeError("SDL3Config.cmake was not found after installation.")


def remove_generated_tree(directory: Path) -> None:
    def make_writable(function, path, _exception) -> None:
        os.chmod(path, stat.S_IWRITE)
        function(path)

    shutil.rmtree(directory, onexc=make_writable)


def prepare_cmake_build(build: Path, source: Path) -> None:
    """Discard a CMake build tree generated at a different location."""
    cache = build / "CMakeCache.txt"
    if not cache.exists():
        return

    cached_paths: dict[str, str] = {}
    for line in cache.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.match(r"^(CMAKE_CACHEFILE_DIR|CMAKE_HOME_DIRECTORY):[^=]+=(.*)$", line)
        if match:
            cached_paths[match.group(1)] = match.group(2)

    expected = {
        "CMAKE_CACHEFILE_DIR": build,
        "CMAKE_HOME_DIRECTORY": source,
    }
    relocated = any(
        key in cached_paths
        and os.path.normcase(os.path.normpath(cached_paths[key]))
        != os.path.normcase(os.path.normpath(os.fspath(path)))
        for key, path in expected.items()
    )
    if relocated:
        print(f"Removing CMake cache from the previous project location: {build}")
        remove_generated_tree(build)


def repair_skia_dependencies() -> None:
    """Remove only dirty or non-Git dependency checkouts owned by this script."""
    deps_file = SKIA_SOURCE / "DEPS"
    if not deps_file.exists():
        return
    pattern = re.compile(
        r'"(third_party/externals/[^"]+)"\s*:\s*"[^"]+@([0-9a-f]{40})"'
    )
    for match in pattern.finditer(deps_file.read_text(encoding="utf-8")):
        relative, _ = match.groups()
        directory = SKIA_SOURCE / Path(relative)
        if not directory.exists():
            continue
        dirty = not (directory / ".git").exists()
        if not dirty:
            result = subprocess.run(
                ["git", "status", "--porcelain"],
                cwd=directory,
                capture_output=True,
                text=True,
                check=False,
            )
            dirty = result.returncode != 0 or bool(result.stdout.strip())
        if dirty:
            print(f"Removing damaged generated dependency: {directory}")
            remove_generated_tree(directory)


def build_skia(repair: bool = False) -> list[Path]:
    clone_pinned("https://skia.googlesource.com/skia.git", SKIA_BRANCH, SKIA_SOURCE)
    output = SKIA_SOURCE / "out" / "Release"
    if repair:
        repair_skia_dependencies()

    environment = os.environ.copy()
    environment["GIT_SYNC_DEPS_SKIP_EMSDK"] = "1"
    if platform.system() == "Windows":
        environment.update({
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "core.longpaths",
            "GIT_CONFIG_VALUE_0": "true",
        })
    print("\n+", sys.executable, "tools/git-sync-deps", flush=True)
    subprocess.run(
        [sys.executable, "tools/git-sync-deps"],
        cwd=SKIA_SOURCE,
        env=environment,
        check=True,
    )
    gn = SKIA_SOURCE / "bin" / ("gn.exe" if platform.system() == "Windows" else "gn")

    arguments = [
        "is_official_build=false",
        "is_debug=false",
        "skia_enable_ganesh=false",
        "skia_enable_graphite=false",
        "skia_enable_tools=false",
        "skia_enable_skparagraph=true",
        "skia_enable_skshaper=true",
        "skia_enable_skunicode=true",
        "skia_use_harfbuzz=true",
        "skia_use_icu=true",
        f'target_cpu="{target_cpu()}"',
    ]
    if platform.system() == "Windows":
        arguments += ['cc="clang-cl"', 'cxx="clang-cl"']
    elif platform.system() == "Linux":
        arguments += ['extra_cflags=["-fPIC"]', 'extra_cflags_cc=["-fPIC"]']

    run([str(gn), "gen", str(output), "--args=" + " ".join(arguments)], cwd=SKIA_SOURCE)
    run(["ninja", "-C", str(output), "skia", "skparagraph"])
    names = [
        "skia",
        "skparagraph",
        "skshaper",
        "skunicode_core",
        "skunicode_icu",
        "harfbuzz",
        "icu",
    ]
    libraries = [
        output / (f"{name}.lib" if platform.system() == "Windows" else f"lib{name}.a")
        for name in names
    ]
    missing = [library for library in libraries if not library.exists()]
    if missing:
        raise RuntimeError(f"Skia build completed without producing: {missing}")
    return libraries


def skia_extra_libraries() -> str:
    system = platform.system()
    if system == "Windows":
        return ";".join(["dwrite", "windowscodecs", "ole32", "uuid", "usp10"])
    if system == "Darwin":
        # The frameworks of macOS are added by the CMake project: CMake keeps
        # the link flags and the libraries apart, so a framework cannot be
        # passed through a variable.
        return ""
    return ";".join(["fontconfig", "freetype", "pthread", "dl", "m"])


def build_native(sdl_dir: Path, skia_libraries: list[Path]) -> Path:
    prepare_cmake_build(NATIVE_BUILD, ROOT / "native")
    command = [
        "cmake",
        "-S",
        str(ROOT / "native"),
        "-B",
        str(NATIVE_BUILD),
        "-G",
        "Ninja",
        "-DCMAKE_BUILD_TYPE=Release",
        f"-DSDL3_DIR={sdl_dir}",
        f"-DSKIA_ROOT={SKIA_SOURCE}",
        f"-DSKIA_LIBRARY={';'.join(str(library) for library in skia_libraries)}",
        f"-DSKIA_EXTRA_LIBRARIES={skia_extra_libraries()}",
        "-DDUI_SDL_STATIC=ON",
    ]
    if platform.system() == "Windows":
        command += ["-DCMAKE_C_COMPILER=clang-cl", "-DCMAKE_CXX_COMPILER=clang-cl"]
    run(command)
    run(["cmake", "--build", str(NATIVE_BUILD), "--parallel"])

    names = {
        "Windows": "dui_native.dll",
        "Darwin": "libdui_native.dylib",
        "Linux": "libdui_native.so",
    }
    library = NATIVE_BUILD / "bin" / names[platform.system()]
    if not library.exists():
        raise RuntimeError(f"Native build completed without producing {library}")
    smoke_name = "dui_paragraph_smoke.exe" if platform.system() == "Windows" else "dui_paragraph_smoke"
    icu_data = SKIA_SOURCE / "out" / "Release" / "icudtl.dat"
    if not icu_data.exists():
        raise RuntimeError(f"ICU data file was not produced: {icu_data}")
    shutil.copy2(icu_data, NATIVE_BUILD / "bin" / "icudtl.dat")
    run([str(NATIVE_BUILD / "bin" / smoke_name)])
    return library


def run_example(
    library: Path,
    dart: str | None,
    example: str = "native_counter.dart",
    smoke: bool = False,
    diagnostics: bool = False,
) -> None:
    executable = dart or shutil.which("dart")
    if not executable:
        raise RuntimeError("Dart SDK was not found. Pass --dart <path-to-dart>.")
    environment = os.environ.copy()
    environment["DUI_NATIVE_LIBRARY"] = str(library)
    command = [executable, "run", f"example/{example}"]
    if smoke and example in ("native_text_gallery.dart", "native_textbox.dart"):
        command.append("--smoke")
    if diagnostics:
        command.append("--diagnostics")
    print("\n+ " + " ".join(command[1:]), flush=True)
    subprocess.run(command, cwd=ROOT, env=environment, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check tools without building")
    parser.add_argument("--skip-native", action="store_true", help="build dependencies only")
    parser.add_argument("--run", action="store_true", help="run the native counter example")
    parser.add_argument(
        "--text-gallery",
        action="store_true",
        help="run the Unicode text gallery; combine with --smoke to close automatically",
    )
    parser.add_argument(
        "--textbox",
        action="store_true",
        help="run the TextBox example; combine with --smoke to close automatically",
    )
    parser.add_argument(
        "--smoke",
        action="store_true",
        help="run a native smoke example with automatic shutdown",
    )
    parser.add_argument(
        "--diagnostics",
        action="store_true",
        help="print one native metrics snapshot when running an example",
    )
    parser.add_argument(
        "--repair",
        action="store_true",
        help="remove dirty generated dependency checkouts before syncing",
    )
    parser.add_argument("--dart", help="path to the Dart executable")
    args = parser.parse_args()

    try:
        require_tools()
        print(f"SDL3: {SDL_VERSION}; Skia: {SKIA_BRANCH}; CPU: {target_cpu()}")
        if args.check:
            print("Tool check passed.")
            return 0
        sdl_dir = build_sdl()
        skia_library = build_skia(repair=args.repair)
        if args.skip_native:
            return 0
        library = build_native(sdl_dir, skia_library)
        print(f"\nNative library: {library}")
        if args.run or args.smoke or args.text_gallery or args.textbox:
            if args.text_gallery:
                example = "native_text_gallery.dart"
            elif args.textbox:
                example = "native_textbox.dart"
            elif args.smoke:
                example = "native_smoke.dart"
            else:
                example = "native_counter.dart"
            run_example(
                library,
                args.dart,
                example=example,
                smoke=args.smoke,
                diagnostics=args.diagnostics,
            )
        return 0
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(f"\nERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
