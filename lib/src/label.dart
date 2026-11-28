import 'colors.dart';
import 'control_template.dart';
import 'drawing.dart';
import 'geometry.dart';
import 'headless_text_layout.dart';
import 'properties.dart';
import 'semantics.dart';
import 'templated_control.dart';
import 'text_layout.dart';

final class Label extends TemplatedControl {
  Label({
    String text = '',
    double fontSize = 14,
    Color color = Colors.black,
    TextAlignment alignment = TextAlignment.start,
  })  : _alignment = alignment,
        super(templateProperty: templateProperty) {
    setValue(textProperty, text);
    setValue(fontSizeProperty, fontSize);
    setValue(colorProperty, color);
  }

  static const templateProperty = DuiProperty<Label, ControlTemplate<Label>?>(
    name: 'template',
    defaultValue: null,
    affectsMeasure: true,
    affectsPaint: true,
  );

  static const textProperty = DuiProperty<Label, String>(
    name: 'text',
    defaultValue: '',
    affectsMeasure: true,
    affectsPaint: true,
  );
  static const fontSizeProperty = DuiProperty<Label, double>(
    name: 'fontSize',
    defaultValue: 14,
    affectsMeasure: true,
    affectsPaint: true,
  );
  static const colorProperty = DuiProperty<Label, Color>(
    name: 'color',
    defaultValue: Colors.black,
    affectsPaint: true,
  );

  static const _headlessFactory = HeadlessTextLayoutFactory();

  TextAlignment _alignment;
  final CachedTextLayout _layout = CachedTextLayout();

  String get text => getValue(textProperty);
  set text(String value) => setValue(textProperty, value);

  double get fontSize => getValue(fontSizeProperty);
  set fontSize(double value) => setValue(fontSizeProperty, value);

  Color get color => getValue(colorProperty);
  set color(Color value) => setValue(colorProperty, value);

  TextAlignment get alignment => _alignment;
  set alignment(TextAlignment value) {
    if (_alignment == value) return;
    _alignment = value;
    invalidateMeasure();
  }

  @override
  bool get isFocusable => false;

  /// The template of the label.
  ///
  /// The template owns the look of the label: it draws the text in its own
  /// way and reacts to the text, the size and the color of the label.
  @override
  ControlTemplate<Label>? get template =>
      super.template as ControlTemplate<Label>?;

  @override
  SemanticsRole get semanticsRole => SemanticsRole.label;

  @override
  String get semanticsName => text;

  @override
  Size measureContentCore(Size availableSize) {
    final layout = _layoutFor(availableSize.width);
    return Size(layout.width, layout.height);
  }

  @override
  void renderContentCore(DrawingContext context) {
    final layout = _layoutFor(bounds.width);
    layout.draw(
      context,
      Point(bounds.left, bounds.top),
      paint: Paint(color),
    );
  }

  @override
  void onMounted() {
    invalidateMeasure();
  }

  @override
  void onUnmounted() {
    _clearTextLayout();
    invalidateMeasure();
  }

  @override
  void onDisposed() => _clearTextLayout();

  TextLayout _layoutFor(double maxWidth) {
    final host = window;
    final factory = host?.textLayoutFactory ?? _headlessFactory;
    final options = TextLayoutOptions(
      text: text,
      fontSize: fontSize,
      maxWidth: maxWidth,
      scale: host?.displayScale ?? 1,
      alignment: alignment,
      direction: flowDirection,
    );
    return _layout.resolve(options, factory);
  }

  void _clearTextLayout() => _layout.dispose();
}
