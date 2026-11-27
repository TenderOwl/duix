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
- `runApp(window)` shows the window, runs its event loop until the window is
  closed and releases the native host, so an application no longer needs the
  event loop and the cleanup in its own code.
- `WidgetState` gathers the state of a control into one value: enabled,
  hovered, pressed and focused. The base class keeps the pressed state up to
  date, so a control no longer has to maintain it on its own.
