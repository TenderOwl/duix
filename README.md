# duix

A retained-mode UI toolkit for Dart: a declarative tree of controls, retained
objects, real-time rendering through SDL3 and Skia, keyboard and mouse input,
IME, clipboard access and system dialogs.

The package consists of the Dart part (`package:duix`) and the native library
`dui_native`, which draws the windows through Skia. The native library is
already built for the supported platforms and ships inside the package, so
users never have to build Skia themselves.

## Quick start

```bash
dart create myapp && cd myapp
dart pub add duix
```

`bin/main.dart`:

```dart
import 'package:duix/dui.dart';
import 'package:duix/native.dart';

Future<void> main() async {
  final counter = ObservableValue<int>(0);
  final label = Label(fontSize: 24)
    ..bind(
      Label.textProperty,
      counter.map((value) => 'Clicks: $value').asBinding(),
    );

  final window = Window(
    title: 'Hello',
    width: 480,
    height: 320,
    content: StackPanel(
      spacing: 12,
      padding: const EdgeInsets.all(20),
      children: [
        label,
        Button(
          content: Label(text: 'Increment', fontSize: 16),
          onClick: () => counter.value++,
        ),
      ],
    ),
  );

  await runApp(window);
}
```

`runApp` shows the window, runs its event loop until the user closes the
window and releases the native host afterwards. An application that needs the
host itself — for the diagnostics or for a second window — creates it and
calls `runWindow` on it:

```dart
final host = await SdlSkiaHost.initialize(diagnosticsEnabled: true);
try {
  await host.runWindow(window);
} finally {
  host.dispose();
}
```

Run it:

```bash
dart run bin/main.dart
```

The `example/` folder holds more examples: a counter, a text gallery, a
TextBox, a list of 100 000 items, a ScrollViewer, dialogs and file panels.

## Where the native library comes from

The lookup order for `dui_native`:

1. An explicit path — the `libraryPath` argument or the `DUI_NATIVE_LIBRARY`
   environment variable.
2. Inside the installed package: `native/bin/<platform>-<architecture>/`,
   where the platform is `windows`, `macos` or `linux` and the architecture is
   `x64` or `arm64`. This is the path that works for an application started
   from source.
3. Next to the executable of the application.

`NativeBindings.libraryPath` reports the path the library was actually loaded
from, which is the first thing to look at when the loading fails.

### Compiled applications

A compiled executable keeps no package configuration, so it cannot find the
package on its own. Copy the library next to it:

```bash
dart compile exe bin/main.dart -o myapp.exe
dart run duix:setup_native .
./myapp.exe
```

`setup_native` takes the library and the ICU data file from the installed
package and puts them into the given directory (the current one by default).

## Supported platforms

| Platform | Architecture | State |
|---|---|---|
| Windows | x64 | built and verified |
| Windows | arm64 | not built |
| macOS | arm64 | built and verified |
| macOS | x64 | not built |
| Linux | x64 | built and verified |
| Linux | arm64 | not built |

The built library depends on system libraries only, so there are no extra
dependencies to install. The import table is checked by the packaging script.
`icudtl.dat` (the ICU data behind shaping and line breaking) ships next to the
library on Windows; on Linux and macOS Skia links the ICU data into the library
itself.

## Building the native library from source

This is only needed for development of the package itself: Skia and SDL3 are
built from source, which takes about half an hour and a lot of disk space.

```bash
python tools/bootstrap_native.py
```

It needs Visual Studio with the C++ workload (Windows), clang and GTK 4.10+
(Linux), or Xcode (macOS). The built library lands in `native/build/bin`.

## Packaging and publishing

```bash
python tools/package.py --dist
```

The script checks the runtime dependencies, builds the release bundle, places
the built library in `build/dist/<platform>-<architecture>/` and assembles
the package folder in `../duix-publish` with the sources, `bin/setup_native.dart`
and the native libraries of every platform that is present in the staging
folder. Builds of other platforms go into the same staging folder, so they can
be brought in from another machine.

The publishing folder lives outside the repository on purpose: pub hides
everything that the ignore rules of the repository exclude, and `build/` is
excluded.

```bash
dart pub publish --directory ../duix-publish
```

## Limitations

- A process holds one native host: SDL has a single global event queue, and
  the host owns every window of the application.
- Windows, macOS and Linux are supported, but the library is built for
  Windows x64, macOS arm64 and Linux x64 only — the other combinations have to
  be built.
- There is no GPU backend yet: rendering goes through CPU Skia.

## License

MIT — see [LICENSE](LICENSE).
