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
