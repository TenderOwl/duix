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
set_target_properties(dui_paragraph_smoke PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)

if(MSVC)
  target_compile_options(dui_native PRIVATE /W4 /EHsc)
else()
  target_compile_options(dui_native PRIVATE -Wall -Wextra -Wpedantic)
endif()

set_target_properties(dui_native PROPERTIES
  OUTPUT_NAME dui_native
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
  LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)
