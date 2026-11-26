import 'drawing.dart';
import 'geometry.dart';

sealed class DrawCommand {
  const DrawCommand();
}

final class DrawRectCommand extends DrawCommand {
  const DrawRectCommand(this.rect, this.paint);

  final Rect rect;
  final Paint paint;
}

final class DrawRoundedRectCommand extends DrawCommand {
  const DrawRoundedRectCommand(
    this.rect,
    this.radiusX,
    this.radiusY,
    this.paint, {
    this.strokeWidth = 0,
  });

  final Rect rect;
  final double radiusX;
  final double radiusY;
  final Paint paint;
  final double strokeWidth;
}

final class DrawTextCommand extends DrawCommand {
  const DrawTextCommand(
    this.text,
    this.position, {
    required this.fontSize,
    required this.color,
    required this.alignment,
  });

  final String text;
  final Point position;
  final double fontSize;
  final Color color;
  final TextAlignment alignment;
}

final class PushClipRectCommand extends DrawCommand {
  const PushClipRectCommand(this.rect);

  final Rect rect;
}

final class PopClipCommand extends DrawCommand {
  const PopClipCommand();
}

final class RecordingDrawingContext implements DrawingContext {
  final commands = <DrawCommand>[];

  @override
  void pushClipRect(Rect rect) {
    commands.add(PushClipRectCommand(rect));
  }

  @override
  void popClip() {
    commands.add(const PopClipCommand());
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    commands.add(DrawRectCommand(rect, paint));
  }

  @override
  void drawRoundedRect(
    Rect rect,
    double radiusX,
    double radiusY,
    Paint paint, {
    double strokeWidth = 0,
  }) {
    commands.add(DrawRoundedRectCommand(
      rect,
      radiusX,
      radiusY,
      paint,
      strokeWidth: strokeWidth,
    ));
  }

  @override
  void drawText(
    String text,
    Point position, {
    required double fontSize,
    required Color color,
    TextAlignment alignment = TextAlignment.start,
  }) {
    commands.add(DrawTextCommand(
      text,
      position,
      fontSize: fontSize,
      color: color,
      alignment: alignment,
    ));
  }
}
