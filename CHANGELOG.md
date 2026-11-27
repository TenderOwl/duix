# Changelog

## 0.1.0

- First public prototype: a retained-mode tree of controls, layout, real-time
  rendering through SDL3 and Skia, keyboard and mouse input, IME, clipboard
  access, system dialogs and semantics.
- The native library `dui_native` ships inside the package for the supported
  platforms (Windows x64, macOS arm64, Linux x64); users never have to build it
  themselves.
- `dart run duix:setup_native <dir>` copies the library next to the executable
  of a compiled application.
