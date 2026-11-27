# Changelog

## Unreleased

- Templates work for any control, not only for a button. `TemplatedControl` holds
  the template mechanics: it creates, replaces and releases the persistent
  subtree of the control, exposes `templateRoot` and `hasTemplate` and draws the
  focus ring itself. `ContentControl` inherits it, so a control declares its own
  template property and gets the same behaviour.
- A widget implements its own content through `measureContentCore`,
  `arrangeContentCore`, `renderContentCore` and `hitTestContentCore`. When the
  control has a template, the template owns the layout, the rendering and the
  hit testing, so a subclass cannot accidentally override the template.
- A control without a template property does not support templates: its template
  is always null and setting it throws a `StateError`.
- **Breaking:** the focus ring of a templated control is drawn on top of the
  content instead of under it.

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
- The layout knows the three sizes of a widget: the minimum size it cannot
  work without, the natural size it would like to have and the size it was
  allocated. An element reports them through `SizeRequest`, and a widget that
  cannot work below a certain size keeps that space.
