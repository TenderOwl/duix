cmake_minimum_required(VERSION 3.24)
project(dui_native VERSION 0.1.0 LANGUAGES CXX)

# Skia's default Windows GN build uses the static MSVC runtime.
if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)

find_package(SDL3 CONFIG REQUIRED)
set(SKIA_EXTRA_LIBRARIES "" CACHE STRING "Additional libraries required by static Skia")
option(DUI_SDL_STATIC "Link SDL3 statically" ON)

if(NOT SKIA_ROOT)
  message(FATAL_ERROR "Set SKIA_ROOT to a Skia source/build checkout.")
endif()
if(NOT SKIA_LIBRARY)
  message(FATAL_ERROR "Set SKIA_LIBRARY to the built Skia library path.")
endif()

add_library(dui_native SHARED
  src/dui_native.cpp
)

target_include_directories(dui_native
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE
    ${SKIA_ROOT}
    ${SKIA_ROOT}/include
)

if(DUI_SDL_STATIC AND TARGET SDL3::SDL3-static)
  set(DUI_SDL_TARGET SDL3::SDL3-static)
else()
  set(DUI_SDL_TARGET SDL3::SDL3)
endif()

target_link_libraries(dui_native
  PRIVATE
    ${DUI_SDL_TARGET}
    ${SKIA_LIBRARY}
    ${SKIA_EXTRA_LIBRARIES}
)

add_executable(dui_paragraph_smoke
  src/paragraph_smoke.cpp
)
target_include_directories(dui_paragraph_smoke
  PRIVATE
    ${SKIA_ROOT}
    ${SKIA_ROOT}/include
)
target_link_libraries(dui_paragraph_smoke
  PRIVATE
    ${SKIA_LIBRARY}
    ${SKIA_EXTRA_LIBRARIES}
)
if(MSVC)
  target_compile_options(
    dui_paragraph_smoke PRIVATE /D_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH
  )
endif()
set_target_properties(dui_paragraph_smoke PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)

if(WIN32)
  target_link_libraries(dui_native PRIVATE ole32)
elseif(APPLE)
  enable_language(OBJCXX)
  target_sources(dui_native PRIVATE src/file_dialog_macos.mm)
  set_source_files_properties(
    src/file_dialog_macos.mm PROPERTIES COMPILE_OPTIONS "-fobjc-arc"
  )
  # A plain name would be turned into "-lAppKit", which does not find a
  # framework. A framework has to be passed as a path, and CMake then links it
  # with "-framework". The same frameworks are needed by the Skia libraries of
  # the paragraph smoke.
  foreach(framework
      AppKit
      ApplicationServices
      CoreText
      CoreGraphics
      Foundation
      UniformTypeIdentifiers)
    find_library(DUI_FRAMEWORK_${framework} ${framework})
    if(NOT DUI_FRAMEWORK_${framework})
      message(FATAL_ERROR "The ${framework} framework was not found.")
    endif()
    target_link_libraries(dui_native PRIVATE ${DUI_FRAMEWORK_${framework}})
    target_link_libraries(
      dui_paragraph_smoke PRIVATE ${DUI_FRAMEWORK_${framework}}
    )
  endforeach()
elseif(UNIX)
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(GTK4 REQUIRED IMPORTED_TARGET gtk4>=4.10)
  target_link_libraries(dui_native PRIVATE PkgConfig::GTK4)
endif()

if(MSVC)
  target_compile_options(dui_native PRIVATE /W4 /EHsc)
  # Newer Visual Studio versions ship an STL that refuses older clang
  # versions, and Skia silences the same check for its own build. The native
  # library uses the same compiler, so the check has to be silenced here too.
  target_compile_options(
    dui_native PRIVATE /D_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH
  )
else()
  target_compile_options(dui_native PRIVATE -Wall -Wextra -Wpedantic)
endif()

set_target_properties(dui_native PROPERTIES
  OUTPUT_NAME dui_native
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
  LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)

# The ICU data file is loaded from the directory of the executable or of the
# native library, so it has to be installed next to the library. Only Windows
# loads it from the disk, on the other systems Skia links it into the library.
set(SKIA_ICU_DATA "${SKIA_ROOT}/out/Release/icudtl.dat" CACHE FILEPATH
    "Path to the Skia ICU data file (icudtl.dat)")

# CMake re-parses install() arguments at install time, and a Windows path with
# backslashes would be read as an escape sequence ("\U" is invalid). Normalize
# the path to forward slashes once, at configure time.
if(SKIA_ICU_DATA)
  file(TO_CMAKE_PATH "${SKIA_ICU_DATA}" DUI_ICU_DATA)
endif()

if(WIN32)
  install(TARGETS dui_native RUNTIME DESTINATION bin)
  if(DUI_ICU_DATA AND EXISTS "${DUI_ICU_DATA}")
    install(FILES "${DUI_ICU_DATA}" DESTINATION bin)
  else()
    message(WARNING "Skia ICU data file not found (${SKIA_ICU_DATA}); "
                    "Unicode shaping will be limited.")
  endif()
else()
  install(TARGETS dui_native LIBRARY DESTINATION lib)
endif()

if(APPLE)
  # A packaged application loads the library from its own bundle, so the
  # install name and the runtime search path stay relative to the executable.
  set_target_properties(dui_native PROPERTIES
    BUILD_WITH_INSTALL_NAME_DIR TRUE
    INSTALL_NAME_DIR "@rpath"
    INSTALL_RPATH "@executable_path;@loader_path;@executable_path/../Frameworks"
  )
elseif(UNIX)
  # Private dependencies are shipped next to the library.
  set_target_properties(dui_native PROPERTIES
    BUILD_RPATH "$ORIGIN"
    INSTALL_RPATH "$ORIGIN"
  )
endif()
