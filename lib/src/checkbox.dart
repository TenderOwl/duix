import 'dart:math' as math;

import 'colors.dart';
import 'control_template.dart';
import 'drawing.dart';
import 'events.dart';
import 'geometry.dart';
import 'headless_text_layout.dart';
import 'observable.dart';
import 'path.dart';
import 'properties.dart';
import 'semantics.dart';
import 'templated_control.dart';
import 'text_layout.dart';
import 'ui_element.dart';

/// A control with two states: checked and unchecked.
///
/// The control draws a box with a check mark and the text of the label next
/// to it. The state is a property, so it can be bound: a two-way binding
/// keeps the value of the control and the value of the model equal.
///
/// The template owns the look of the control: it draws the box and the check
/// mark in its own way and reacts to the state of the control.
final class CheckBox extends TemplatedControl {
  CheckBox({
    bool isChecked = false,
    String text = '',
    double fontSize = 14,
    Color color = Colors.black,
    void Function(bool value)? onChanged,
  }) : super(templateProperty: templateProperty) {
    setValue(isCheckedProperty, isChecked);
    setValue(textProperty, text);
    setValue(fontSizeProperty, fontSize);
    setValue(colorProperty, color);
    if (onChanged != null) addChangedHandler(onChanged);
    addPropertyListener(_propertyChanged);
    addHandler(UIElement.pointerDown, _pointerDown);
    addHandler(UIElement.keyDown, _keyDown);
  }

  static const templateProperty =
      DuiProperty<CheckBox, ControlTemplate<CheckBox>?>(
    name: 'template',
    defaultValue: null,
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The state of the box.
  static const isCheckedProperty = DuiProperty<CheckBox, bool>(
    name: 'isChecked',
    defaultValue: false,
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The text of the label next to the box.
  static const textProperty = DuiProperty<CheckBox, String>(
    name: 'text',
    defaultValue: '',
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The size of the font of the label.
  static const fontSizeProperty = DuiProperty<CheckBox, double>(
    name: 'fontSize',
    defaultValue: 14,
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The color of the text of the label.
  static const colorProperty = DuiProperty<CheckBox, Color>(
    name: 'color',
    defaultValue: Colors.black,
    affectsPaint: true,
  );

  /// The size of the box with the check mark.
  static const double boxSize = 18;

  /// The distance between the box and the text of the label.
  static const double gapSize = 8;

  /// The radius of the corners of the box.
  static const double boxRadius = 3;

  /// The color of the border of the box.
  static const Color boxBorderColor = Color(0xFF8A8A8A);

  /// The color of the fill of the box.
  static const Color boxFillColor = Color(0xFFFFFFFF);

  /// The color of the check mark.
  static const Color checkMarkColor = Color(0xFF3584E4);

  /// The color of the box and of the text of a disabled control.
  static const Color disabledColor = Color(0xFF9A9A9A);

  static const _headlessFactory = HeadlessTextLayoutFactory();

  final _changedHandlers = <void Function(bool value)>[];
  final CachedTextLayout _layout = CachedTextLayout();

  /// The template of the check box.
  ///
  /// The template owns the look of the control: it draws the box and the
  /// check mark and reacts to the state of the control.
  @override
  ControlTemplate<CheckBox>? get template =>
      super.template as ControlTemplate<CheckBox>?;

  /// Whether the box is checked.
  bool get isChecked => getValue(isCheckedProperty);
  set isChecked(bool value) => setValue(isCheckedProperty, value);

  /// The text of the label next to the box.
  String get text => getValue(textProperty);
  set text(String value) => setValue(textProperty, value);

  /// The size of the font of the label.
  double get fontSize => getValue(fontSizeProperty);
  set fontSize(double value) => setValue(fontSizeProperty, value);

  /// The color of the text of the label.
  Color get color => getValue(colorProperty);
  set color(Color value) => setValue(colorProperty, value);

  /// Adds a handler that is called when the state of the box changes.
  void addChangedHandler(void Function(bool value) handler) =>
      _changedHandlers.add(handler);

  /// Removes a handler that is called when the state of the box changes.
  void removeChangedHandler(void Function(bool value) handler) =>
      _changedHandlers.remove(handler);

  /// Changes the state of the box.
  void toggle() => isChecked = !isChecked;

  /// The rectangle of the box with the check mark.
  ///
  /// The box stands at the start of the control: at the left edge from left to
  /// right and at the right edge from right to left.
  Rect get boxRect {
    final size = math.min(boxSize, math.min(bounds.width, bounds.height));
    final top = bounds.top + (bounds.height - size) / 2;
    if (isRightToLeft) {
      return Rect.fromLTWH(bounds.right - size, top, size, size);
    }
    return Rect.fromLTWH(bounds.left, top, size, size);
  }

  /// The rectangle of the text of the label.
  ///
  /// The text stands next to the box, on the side of the box that is not the
  /// start of the control.
  Rect get textRect {
    final width = math.max(0.0, bounds.width - boxSize - gapSize);
    final left = isRightToLeft ? bounds.left : bounds.left + boxSize + gapSize;
    return Rect.fromLTWH(left, bounds.top, width, bounds.height);
  }

  @override
  bool get handlesPointerPress => true;

  void _pointerDown(Object sender, PointerEventArgs args) {
    if (!isEnabled) return;
    if (args.button != PointerButton.primary) return;
    focus();
  }

  @override
  void onReleased(PointerEventArgs args) {
    if (!isEnabled) return;
    toggle();
    args.handled = true;
  }

  void _keyDown(Object sender, KeyEventArgs args) {
    if (!isEnabled || args.primaryShortcutPressed) return;
    if (args.key != 'space') return;
    toggle();
    args.handled = true;
  }

  void _propertyChanged(PropertyChangedEvent event) {
    if (!identical(event.property, isCheckedProperty)) return;
    final value = event.newValue as bool;
    for (final handler in List<void Function(bool)>.of(_changedHandlers)) {
      handler(value);
    }
  }

  @override
  SemanticsRole get semanticsRole => SemanticsRole.checkBox;

  @override
  String get semanticsName => text;

  @override
  SemanticsState get semanticsState => SemanticsState(
        focused: isFocused,
        disabled: !isEnabled,
        checked: isChecked,
      );

  @override
  Size measureContentCore(Size availableSize) {
    final layout = _layoutFor(_textWidthFor(availableSize));
    return Size(
      boxSize + gapSize + layout.width,
      math.max(boxSize, layout.height),
    );
  }

  @override
  void renderContentCore(DrawingContext context) {
    final box = boxRect;
    context.drawRoundedRect(
        box, boxRadius, boxRadius, const Paint(boxFillColor));
    context.drawRoundedRect(
      box,
      boxRadius,
      boxRadius,
      Paint(
        isEnabled ? boxBorderColor : disabledColor,
        strokeWidth: 1,
      ),
    );
    if (isChecked) {
      context.drawPath(
        _checkMark(box),
        Paint(isEnabled ? checkMarkColor : disabledColor, strokeWidth: 2),
      );
    }

    final layout = _layoutFor(_textWidthFor(bounds.size));
    final rect = textRect;
    final top = rect.top + (rect.height - layout.height) / 2;
    layout.draw(
      context,
      Point(rect.left, top),
      paint: Paint(isEnabled ? color : disabledColor),
    );
  }

  @override
  void onMounted() {
    invalidateMeasure();
  }

  @override
  void onUnmounted() {
    _layout.dispose();
    invalidateMeasure();
  }

  @override
  void onDisposed() => _layout.dispose();

  /// The width the text of the label is laid out in.
  ///
  /// The text stands next to the box, so the box and the gap take their part
  /// of the width of the control.
  double _textWidthFor(Size availableSize) {
    final available = availableSize.width - boxSize - gapSize;
    if (!available.isFinite) return double.infinity;
    return math.max(0.0, available);
  }

  TextLayout _layoutFor(double maxWidth) {
    final host = window;
    final factory = host?.textLayoutFactory ?? _headlessFactory;
    final options = TextLayoutOptions(
      text: text,
      fontSize: fontSize,
      maxWidth: maxWidth,
      scale: host?.displayScale ?? 1,
      direction: flowDirection,
    );
    return _layout.resolve(options, factory);
  }

  /// The path of the check mark inside the box.
  Path _checkMark(Rect box) {
    return Path()
      ..moveTo(
        Point(box.left + box.width * 0.24, box.top + box.height * 0.52),
      )
      ..lineTo(
        Point(box.left + box.width * 0.44, box.top + box.height * 0.72),
      )
      ..lineTo(
        Point(box.left + box.width * 0.78, box.top + box.height * 0.28),
      );
  }
}
