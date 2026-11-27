import 'drawing.dart';
import 'geometry.dart';
import 'image.dart';

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
    this.paint,
  );

  final Rect rect;
  final double radiusX;
  final double radiusY;
  final Paint paint;

  /// The width of the stroke, zero when the shape is filled.
  double get strokeWidth => paint.strokeWidth;
}

final class DrawLineCommand extends DrawCommand {
  const DrawLineCommand(this.from, this.to, this.paint);

  final Point from;
  final Point to;
  final Paint paint;

  /// The width of the stroke, zero when the line is a hairline.
  double get strokeWidth => paint.strokeWidth;
}

final class DrawImageCommand extends DrawCommand {
  const DrawImageCommand(this.image, this.rect, this.paint);

  final DrawableImage image;
  final Rect rect;
  final Paint paint;
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
    Paint paint,
  ) {
    commands.add(DrawRoundedRectCommand(
      rect,
      radiusX,
      radiusY,
      paint,
    ));
  }

  @override
  void drawLine(Point from, Point to, Paint paint) {
    commands.add(DrawLineCommand(from, to, paint));
  }

  @override
  void drawImage(DrawableImage image, Rect rect, Paint paint) {
    commands.add(DrawImageCommand(image, rect, paint));
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
