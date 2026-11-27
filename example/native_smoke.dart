import 'dart:async';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';

Future<void> main(List<String> args) async {
  SdlSkiaHost? host;
  Window? window;

  try {
    host = await SdlSkiaHost.initialize(
      diagnosticsEnabled: args.contains('--diagnostics'),
    );
    var activations = 0;
    final button = Button(
      content: Label(text: 'Space / Enter', fontSize: 16),
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
          Label(text: 'Native smoke test', fontSize: 20),
          button,
          _Rule(),
          _Outline(),
        ],
      ),
    );

    button.focus();
    await host.showWindow(window);
    window.dispatchKeyDown('enter');
    window.dispatchKeyDown('space');
    if (activations != 2) {
      throw StateError('Native Button keyboard activation failed.');
    }

    // The popup layer is drawn above the content of the window.
    window.overlay.open(
      Border(
        color: const Color(0xFF202020),
        padding: const EdgeInsets.all(8),
        content: Label(text: 'Popup', color: const Color(0xFFFFFFFF)),
      ),
      ownerArea: button.bounds,
    );
    if (!window.overlay.isOpen) {
      throw StateError('The popup layer did not open.');
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
    host?.dispose();
  }
}

/// A thin line that proves the line primitive of the backend.
final class _Rule extends Control {
  _Rule();

  @override
  bool get isFocusable => false;

  @override
  Size measureCore(Size availableSize) =>
      Size(availableSize.width.isFinite ? availableSize.width : 0, 12);

  @override
  void renderCore(DrawingContext context) {
    context.drawLine(
      const Point(0, 6),
      Point(bounds.width, 6),
      const Paint(Color(0xFF9E9E9E), strokeWidth: 2),
    );
  }
}

/// A rounded rectangle that proves the stroke of the backend.
final class _Outline extends Control {
  _Outline();

  @override
  bool get isFocusable => false;

  @override
  Size measureCore(Size availableSize) =>
      Size(availableSize.width.isFinite ? availableSize.width : 0, 24);

  @override
  void renderCore(DrawingContext context) {
    context.drawRoundedRect(
      bounds.deflate(const EdgeInsets.symmetric(vertical: 2)),
      6,
      6,
      const Paint(Color(0xFF3A7BD5), strokeWidth: 1),
    );
  }
}
