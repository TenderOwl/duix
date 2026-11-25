import 'dart:async';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';

Future<void> main(List<String> args) async {
  SdlSkiaHost? host;
  Application? application;
  Window? window;

  try {
    host = await SdlSkiaHost.initialize(
      diagnosticsEnabled: args.contains('--diagnostics'),
    );
    application = Application(host: host);
    window = Window(
      title: 'DUI — native smoke',
      width: 320,
      height: 200,
      content: TextBlock(
        text: 'Native smoke test',
        fontSize: 20,
      ),
    );

    await application.run(window);
    for (var frame = 0; frame < 3 && host.isOpen(window); frame++) {
      host.pumpEvents();
      host.presentWindow(window);
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }

    if (!host.isOpen(window)) {
      throw StateError('The native window closed before the smoke test ended.');
    }
    final diagnostics = host.diagnosticsFor(window);
    if (diagnostics != null) print(diagnostics);
    print('Native smoke passed: 3 frames rendered.');
  } finally {
    final activeWindow = window;
    if (application != null && activeWindow != null) {
      await application.shutdown(activeWindow);
    }
    host?.dispose();
  }
}
