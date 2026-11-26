import 'drawing.dart';
import 'geometry.dart';

const _focusRingColor = Color(0xFF356AC3);

enum FocusRingShape { rectangle, capsule }

/// Draws a two-pixel focus indicator inside the supplied control bounds.
void drawFocusRing(
  DrawingContext context,
  Rect bounds, {
  FocusRingShape shape = FocusRingShape.rectangle,
}) {
  if (bounds.width <= 0 || bounds.height <= 0) return;
  var thickness = 2.0;
  if (bounds.width / 2 < thickness) thickness = bounds.width / 2;
  if (bounds.height / 2 < thickness) thickness = bounds.height / 2;
  const paint = Paint(_focusRingColor);
  if (shape == FocusRingShape.capsule) {
    final inset = thickness / 2;
    final ring = Rect.fromLTWH(
      bounds.left + inset,
      bounds.top + inset,
      bounds.width - thickness,
      bounds.height - thickness,
    );
    final radiusX = ring.width / 2;
    final radiusY = ring.height / 2;
    context.drawRoundedRect(
      ring,
      radiusX,
      radiusY,
      paint,
      strokeWidth: thickness,
    );
    return;
  }

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
