import 'geometry.dart';

abstract interface class DrawingContext {
  void pushClipRect(Rect rect);
  void popClip();
  void drawRect(Rect rect, Paint paint);
  void drawRoundedRect(
    Rect rect,
    double radiusX,
    double radiusY,
    Paint paint, {
    double strokeWidth = 0,
  });

  void drawText(
    String text,
    Point position, {
    required double fontSize,
    required Color color,
    TextAlignment alignment,
  });
}
