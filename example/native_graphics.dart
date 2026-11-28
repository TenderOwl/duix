import 'dart:async';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';

/// Shows the paths, the shadows and the blend modes of the backend.
///
/// The example draws a curve, a card with a shadow and two shapes that are
/// mixed with each other, so every new primitive of the graphics layer is
/// visible at once.
Future<void> main(List<String> args) async {
  SdlSkiaHost? host;

  try {
    host = await SdlSkiaHost.initialize(
      diagnosticsEnabled: args.contains('--diagnostics'),
    );
    final window = Window(
      title: 'DUI - native graphics',
      width: 420,
      height: 320,
      content: StackPanel(
        spacing: 16,
        padding: const EdgeInsets.all(20),
        children: [
          Label(text: 'Paths, shadows and blending', fontSize: 18),
          _Curve(),
          _ShadowCard(),
          _Blend(),
        ],
      ),
    );

    await host.showWindow(window);

    if (args.contains('--smoke')) {
      for (var frame = 0; frame < 3 && host.isOpen(window); frame++) {
        host.pumpEvents();
        host.presentWindow(window);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }

      if (!host.isOpen(window)) {
        throw StateError(
            'The native window closed before the smoke test ended.');
      }
      final diagnostics = host.diagnosticsFor(window);
      if (diagnostics != null) print(diagnostics);
      print('Native graphics smoke passed: 3 event iterations.');
      return;
    }

    await host.runWindow(window);
  } finally {
    host?.dispose();
  }
}

/// A curve that proves the path of the backend.
final class _Curve extends Control {
  _Curve();

  @override
  bool get isFocusable => false;

  @override
  Size measureCore(Size availableSize) =>
      Size(availableSize.width.isFinite ? availableSize.width : 0, 72);

  @override
  void renderCore(DrawingContext context) {
    final left = bounds.left;
    final top = bounds.top;
    final width = bounds.width;
    final path = Path()
      ..moveTo(Point(left, top + 60))
      ..cubicTo(
        Point(left + width / 3, top),
        Point(left + width * 2 / 3, top + 72),
        Point(left + width, top + 12),
      );
    context.drawPath(
      path,
      const Paint(Color(0xFF3584E4), strokeWidth: 3),
    );
  }
}

/// A card that proves the shadow of the paint.
final class _ShadowCard extends Control {
  _ShadowCard();

  @override
  bool get isFocusable => false;

  @override
  Size measureCore(Size availableSize) =>
      Size(availableSize.width.isFinite ? availableSize.width : 0, 56);

  @override
  void renderCore(DrawingContext context) {
    final card = bounds.deflate(const EdgeInsets.symmetric(vertical: 4));
    context.drawRoundedRect(
      card,
      8,
      8,
      const Paint(
        Color(0xFFFFFFFF),
        shadow: Shadow(
          Color(0x60000000),
          blurRadius: 12,
          offsetX: 0,
          offsetY: 4,
        ),
      ),
    );
    context.drawText(
      'Shadow of the paint',
      Point(card.left + 12, card.top + 12),
      fontSize: 14,
      color: const Color(0xFF202020),
    );
  }
}

/// Two shapes that prove the blend mode and the transparency of the paint.
final class _Blend extends Control {
  _Blend();

  @override
  bool get isFocusable => false;

  @override
  Size measureCore(Size availableSize) =>
      Size(availableSize.width.isFinite ? availableSize.width : 0, 56);

  @override
  void renderCore(DrawingContext context) {
    final left = bounds.left;
    final top = bounds.top;
    final width = bounds.width;
    final first = Rect.fromLTWH(left, top + 8, width * 0.6, 40);
    final second = Rect.fromLTWH(left + width * 0.4, top + 8, width * 0.6, 40);
    context.drawRect(
      first,
      const Paint(Color(0xFFFFC107)),
    );
    context.drawRect(
      second,
      const Paint(
        Color(0x994FD1C5),
        opacity: 0.8,
        blendMode: BlendMode.multiply,
      ),
    );
  }
}
