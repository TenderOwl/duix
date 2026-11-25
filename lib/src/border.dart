import 'colors.dart';
import 'content_control.dart';
import 'drawing.dart';
import 'geometry.dart';

final class Border extends ContentControl {
  Border({
    super.content,
    Color color = Colors.black,
    EdgeInsets padding = EdgeInsets.zero,
  })  : _color = color,
        _padding = padding;

  Color _color;
  EdgeInsets _padding;

  Color get color => _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    invalidatePaint();
  }

  EdgeInsets get padding => _padding;
  set padding(EdgeInsets value) {
    if (_padding == value) return;
    _padding = value;
    invalidateMeasure();
  }

  @override
  bool get isFocusable => false;

  @override
  Size measureCore(Size availableSize) {
    final inner = Size(
      (availableSize.width - padding.horizontal).clamp(0, double.infinity),
      (availableSize.height - padding.vertical).clamp(0, double.infinity),
    );
    return padding.inflateSize(super.measureCore(inner));
  }

  @override
  void arrangeCore(Rect finalRect) {
    content?.arrange(finalRect.deflate(padding));
  }

  @override
  void renderCore(DrawingContext context) {
    context.drawRect(bounds, Paint(color));
    super.renderCore(context);
  }
}
