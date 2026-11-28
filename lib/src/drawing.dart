import 'geometry.dart';
import 'image.dart';
import 'path.dart';

/// A surface that a widget draws on.
///
/// The paint decides how a shape is drawn: a paint without a stroke width
/// fills the shape, a paint with one strokes its outline.
abstract interface class DrawingContext {
  void pushClipRect(Rect rect);
  void popClip();
  void drawRect(Rect rect, Paint paint);
  void drawRoundedRect(
    Rect rect,
    double radiusX,
    double radiusY,
    Paint paint,
  );

  /// Draws a straight line from [from] to [to].
  void drawLine(Point from, Point to, Paint paint);

  /// Draws a path.
  ///
  /// The paint fills the path or strokes its outline, and it may carry a
  /// transparency, a blend mode and a shadow.
  void drawPath(Path path, Paint paint);

  /// Draws an image into [rect].
  void drawImage(DrawableImage image, Rect rect, Paint paint);

  void drawText(
    String text,
    Point position, {
    required double fontSize,
    required Color color,
    TextAlignment alignment,
  });
}
