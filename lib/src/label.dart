import 'colors.dart';
import 'drawing.dart';
import 'geometry.dart';
import 'headless_text_layout.dart';
import 'properties.dart';
import 'text_layout.dart';
import 'ui_element.dart';

final class Label extends Control {
  Label({
    String text = '',
    double fontSize = 14,
    Color color = Colors.black,
    TextAlignment alignment = TextAlignment.start,
  }) : _alignment = alignment {
    setValue(textProperty, text);
    setValue(fontSizeProperty, fontSize);
    setValue(colorProperty, color);
  }

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
  TextLayout? _textLayout;
  TextLayoutOptions? _textLayoutOptions;
  TextLayoutFactory? _textLayoutFactory;

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

  @override
  Size measureCore(Size availableSize) {
    final layout = _layoutFor(availableSize.width);
    return Size(layout.width, layout.height);
  }

  @override
  void renderCore(DrawingContext context) {
    final layout = _textLayout ?? _layoutFor(bounds.width);
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

  TextLayout _layoutFor(double maxWidth) {
    final host = window;
    final factory = host?.textLayoutFactory ?? _headlessFactory;
    final options = TextLayoutOptions(
      text: text,
      fontSize: fontSize,
      maxWidth: maxWidth,
      scale: host?.displayScale ?? 1,
      alignment: alignment,
    );
    final current = _textLayout;
    if (current != null &&
        !current.isDisposed &&
        identical(_textLayoutFactory, factory) &&
        _textLayoutOptions == options) {
      return current;
    }

    _clearTextLayout();
    final created = factory.create(options);
    _textLayout = created;
    _textLayoutOptions = options;
    _textLayoutFactory = factory;
    return created;
  }

  void _clearTextLayout() {
    _textLayout?.dispose();
    _textLayout = null;
    _textLayoutOptions = null;
    _textLayoutFactory = null;
  }
}
