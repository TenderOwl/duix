import 'drawing.dart';
import 'geometry.dart';

const _focusRingColor = Color(0xFF356AC3);

/// Draws a two-pixel focus indicator inside the supplied control bounds.
void drawFocusRing(DrawingContext context, Rect bounds) {
  if (bounds.width <= 0 || bounds.height <= 0) return;
  var thickness = 2.0;
  if (bounds.width / 2 < thickness) thickness = bounds.width / 2;
  if (bounds.height / 2 < thickness) thickness = bounds.height / 2;
  const paint = Paint(_focusRingColor);

  context.drawRect(
    Rect.fromLTWH(bounds.left, bounds.top, bounds.width, thickness),
    paint,
  );
  context.drawRect(
    Rect.fromLTWH(
      bounds.left,
      bounds.bottom - thickness,
      bounds.width,
      thickness,
    ),
    paint,
  );
  final sideHeight = bounds.height - thickness * 2;
  if (sideHeight <= 0) return;
  context.drawRect(
    Rect.fromLTWH(
      bounds.left,
      bounds.top + thickness,
      thickness,
      sideHeight,
    ),
    paint,
  );
  context.drawRect(
    Rect.fromLTWH(
      bounds.right - thickness,
      bounds.top + thickness,
      thickness,
      sideHeight,
    ),
    paint,
  );
}
