import 'dart:async';

import 'window.dart';

/// The application that owns the windows of a process.
///
/// The application shows a window and runs its event loop until the window is
/// closed. The native host stays alive, so a second window can be opened
/// while the first one is running.
final class Application {
  Application({required this.host});

  final NativeHost host;
  bool _running = false;

  /// Shows the window and runs its event loop until the window is closed.
  ///
  /// The call returns when the user closes the window, so it blocks the
  /// application until then.
  Future<void> run(Window mainWindow) async {
    if (_running) throw StateError('The application is already running.');
    _running = true;
    try {
      await host.runWindow(mainWindow);
    } finally {
      _running = false;
    }
  }

  /// Closes the window and stops the application.
  Future<void> shutdown(Window window) async {
    await host.closeWindow(window);
    _running = false;
  }
}
