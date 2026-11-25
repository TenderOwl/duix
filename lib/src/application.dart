import 'dart:async';

import 'window.dart';

final class Application {
  Application({required this.host});

  final NativeHost host;
  bool _running = false;

  Future<void> run(Window mainWindow) async {
    if (_running) throw StateError('The application is already running.');
    _running = true;
    await host.showWindow(mainWindow);
  }

  Future<void> shutdown(Window window) async {
    await host.closeWindow(window);
    _running = false;
  }
}
