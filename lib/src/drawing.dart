import 'geometry.dart';

abstract interface class DrawingContext {
  void pushClipRect(Rect rect);
  void popClip();
  void drawRect(Rect rect, Paint paint);

  void drawText(
    String text,
    Point position, {
    required double fontSize,
    required Color color,
    TextAlignment alignment,
  });
}
