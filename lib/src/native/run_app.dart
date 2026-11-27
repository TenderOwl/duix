import 'dart:async';

import '../window.dart';
import 'sdl_skia_host.dart';

/// Shows the window, runs its event loop and releases the native host.
///
/// This is the shortest way to write an application: the loop runs until the
/// user closes the window, and the native host is released afterwards. An
/// application that needs the host itself — for the diagnostics or for a
/// second window — creates a [SdlSkiaHost] and calls
/// [SdlSkiaHost.runWindow] instead.
Future<void> runApp(
  Window window, {
  String? libraryPath,
  bool diagnosticsEnabled = false,
}) async {
  final host = await SdlSkiaHost.initialize(
    libraryPath: libraryPath,
    diagnosticsEnabled: diagnosticsEnabled,
  );
  try {
    await host.runWindow(window);
  } finally {
    host.dispose();
  }
}
