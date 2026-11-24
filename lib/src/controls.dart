import 'drawing.dart';
import 'events.dart';
import 'geometry.dart';
import 'properties.dart';
import 'ui_element.dart';

final class TextBlock extends Control {
  TextBlock({
    String text = '',
    double fontSize = 14,
    Color color = Colors.black,
    TextAlignment alignment = TextAlignment.start,
  }) : _alignment = alignment {
    setValue(textProperty, text);
    setValue(fontSizeProperty, fontSize);
    setValue(colorProperty, color);
  }

  static const textProperty = DuiProperty<TextBlock, String>(
    name: 'text',
    defaultValue: '',
    affectsMeasure: true,
    affectsPaint: true,
  );
  static const fontSizeProperty = DuiProperty<TextBlock, double>(
    name: 'fontSize',
    defaultValue: 14,
    affectsMeasure: true,
    affectsPaint: true,
  );
  static const colorProperty = DuiProperty<TextBlock, Color>(
    name: 'color',
    defaultValue: Colors.black,
    affectsPaint: true,
  );

  TextAlignment _alignment;

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
    invalidatePaint();
  }

  @override
  bool get isFocusable => false;

  @override
  Size measureCore(Size availableSize) {
    final lines = text.split('\n');
    final width = lines.fold<double>(
      0,
      (maximum, line) => line.length * fontSize * 0.6 > maximum
          ? line.length * fontSize * 0.6
          : maximum,
    );
    return Size(width, lines.length * fontSize * 1.3);
  }

  @override
  void renderCore(DrawingContext context) {
    context.drawText(
      text,
      Point(bounds.left, bounds.top),
      fontSize: fontSize,
      color: color,
      alignment: alignment,
    );
  }
}

abstract class ContentControl extends Control {
  ContentControl({UIElement? content}) : _content = content {
    _content?.attachToParent(this);
  }

  UIElement? _content;

  UIElement? get content => _content;
  set content(UIElement? value) {
    if (identical(_content, value)) return;
    if (value?.logicalParent != null) {
      throw StateError('The content already belongs to another parent.');
    }
    _content?.attachToParent(null);
    _content?.mountTo(null);
    _content = value;
    _content?.attachToParent(this);
    _content?.mountTo(window);
    invalidateMeasure();
  }

  @override
  Iterable<UIElement> get logicalChildren =>
      _content == null ? const [] : [_content!];

  @override
  void onMounted() {
    _content?.mountTo(window);
  }

  @override
  Size measureCore(Size availableSize) =>
      _content?.measure(availableSize) ?? Size.zero;

  @override
  void arrangeCore(Rect finalRect) {
    _content?.arrange(finalRect);
  }

  @override
  void renderCore(DrawingContext context) {
    _content?.render(context);
  }

  @override
  UIElement? hitTestCore(Point position) => _content?.hitTest(position);
}

final class Button extends ContentControl {
  Button({super.content, void Function()? onClick}) {
    if (onClick != null) addClickHandler(onClick);
    addHandler(UIElement.pointerDown, _pointerDown);
    addHandler(UIElement.pointerUp, _pointerUp);
  }

  final _clickHandlers = <void Function()>[];
  bool _isPressed = false;

  bool get isPressed => _isPressed;

  void addClickHandler(void Function() handler) => _clickHandlers.add(handler);
  void removeClickHandler(void Function() handler) =>
      _clickHandlers.remove(handler);

  void _pointerDown(Object sender, PointerEventArgs args) {
    if (!isEnabled) return;
    _isPressed = true;
    focus();
    invalidatePaint();
  }

  void _pointerUp(Object sender, PointerEventArgs args) {
    if (!_isPressed) return;
    _isPressed = false;
    invalidatePaint();
    for (final handler in List<void Function()>.of(_clickHandlers)) {
      handler();
    }
    args.handled = true;
  }

  @override
  Size measureCore(Size availableSize) {
    final childSize = super.measureCore(availableSize);
    return Size(childSize.width + 24, childSize.height + 12);
  }

  @override
  void arrangeCore(Rect finalRect) {
    content?.arrange(Rect.fromLTWH(
      finalRect.left + 12,
      finalRect.top + 6,
      (finalRect.width - 24).clamp(0, double.infinity),
      (finalRect.height - 12).clamp(0, double.infinity),
    ));
  }

  @override
  void renderCore(DrawingContext context) {
    context.drawRect(
      bounds,
      Paint(isPressed ? const Color(0xFFB0B0B0) : const Color(0xFFE0E0E0)),
    );
    super.renderCore(context);
  }
}

final class TextBox extends Control {
  TextBox({String text = ''}) {
    setValue(textProperty, text);
    addHandler(UIElement.textInput, _textInput);
  }

  static const textProperty = DuiProperty<TextBox, String>(
    name: 'text',
    defaultValue: '',
    affectsMeasure: true,
    affectsPaint: true,
  );

  String get text => getValue(textProperty);
  set text(String value) => setValue(textProperty, value);

  void _textInput(Object sender, TextInputEventArgs args) {
    text += args.text;
    args.handled = true;
  }

  @override
  Size measureCore(Size availableSize) => Size(
        (text.length * 8.4 + 16).clamp(80, availableSize.width),
        30,
      );

  @override
  void renderCore(DrawingContext context) {
    context.drawRect(bounds, const Paint(Colors.white));
    context.drawText(
      text,
      Point(bounds.left + 8, bounds.top + 7),
      fontSize: 14,
      color: Colors.black,
    );
  }
}

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

abstract final class Colors {
  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);
}
