import 'colors.dart';
import 'content_control.dart';
import 'drawing.dart';
import 'geometry.dart';
import 'properties.dart';

final class Border extends ContentControl {
  Border({
    super.content,
    Color color = Colors.black,
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    setValue(colorProperty, color);
    setValue(paddingProperty, padding);
  }

  static const colorProperty = DuiProperty<Border, Color>(
    name: 'color',
    defaultValue: Colors.black,
    affectsPaint: true,
  );
  static const paddingProperty = DuiProperty<Border, EdgeInsets>(
    name: 'padding',
    defaultValue: EdgeInsets.zero,
    affectsMeasure: true,
  );

  Color get color => getValue(colorProperty);
  set color(Color value) => setValue(colorProperty, value);

  EdgeInsets get padding => getValue(paddingProperty);
  set padding(EdgeInsets value) => setValue(paddingProperty, value);

  @override
  bool get isFocusable => false;

  @override
  Size measureContentCore(Size availableSize) {
    final inner = Size(
      (availableSize.width - padding.horizontal).clamp(0, double.infinity),
      (availableSize.height - padding.vertical).clamp(0, double.infinity),
    );
    return padding.inflateSize(super.measureContentCore(inner));
  }

  @override
  void arrangeContentCore(Rect finalRect) {
    content?.arrange(finalRect.deflate(padding));
  }

  @override
  void renderContentCore(DrawingContext context) {
    context.drawRect(bounds, Paint(color));
    super.renderContentCore(context);
  }
}
