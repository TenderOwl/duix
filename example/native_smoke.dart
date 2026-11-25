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
    var activations = 0;
    final button = Button(
      content: TextBlock(text: 'Space / Enter', fontSize: 16),
      onClick: () => activations++,
    );
    window = Window(
      title: 'DUI — native smoke',
      width: 320,
      height: 200,
      content: StackPanel(
        spacing: 12,
        padding: const EdgeInsets.all(20),
        children: [
          TextBlock(text: 'Native smoke test', fontSize: 20),
          button,
        ],
      ),
    );

    button.focus();
    await application.run(window);
    window.dispatchKeyDown('enter');
    window.dispatchKeyDown('space');
    if (activations != 2) {
      throw StateError('Native Button keyboard activation failed.');
    }
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
    final renderedFrames = diagnostics?.renderFrameCount;
    print(
      'Native smoke passed: 3 event iterations'
      '${renderedFrames == null ? '' : ', $renderedFrames frames rendered'}.',
    );
  } finally {
    final activeWindow = window;
    if (application != null && activeWindow != null) {
      await application.shutdown(activeWindow);
    }
    host?.dispose();
  }
}
