import 'dart:math' as math;

import 'colors.dart';
import 'drawing.dart';
import 'events.dart';
import 'geometry.dart';
import 'headless_text_layout.dart';
import 'observable.dart';
import 'properties.dart';
import 'semantics.dart';
import 'templated_control.dart';
import 'text_layout.dart';
import 'ui_element.dart';

/// The core of the controls that can be checked.
///
/// A check box and a radio button share the state, the label of the control
/// and the way the user changes the state. They differ in the mark they draw
/// and in the group they belong to, so those parts stay in the subclasses.
abstract class CheckableControl extends TemplatedControl {
  CheckableControl({
    super.templateProperty,
    required DuiProperty<dynamic, bool> isCheckedProperty,
    required DuiProperty<dynamic, String> textProperty,
    required DuiProperty<dynamic, double> fontSizeProperty,
    required DuiProperty<dynamic, Color> colorProperty,
    bool isChecked = false,
    String text = '',
    double fontSize = 14,
    Color color = Colors.black,
    void Function(bool value)? onChanged,
  })  : _isCheckedProperty = isCheckedProperty,
        _textProperty = textProperty,
        _fontSizeProperty = fontSizeProperty,
        _colorProperty = colorProperty {
    setValue(_isCheckedProperty, isChecked);
    setValue(_textProperty, text);
    setValue(_fontSizeProperty, fontSize);
    setValue(_colorProperty, color);
    if (onChanged != null) addChangedHandler(onChanged);
    addPropertyListener(_propertyChanged);
    addHandler(UIElement.pointerDown, _pointerDown);
    addHandler(UIElement.keyDown, _keyDown);
  }

  /// The size of the mark that shows the state of the control.
  static const double markSize = 18;

  /// The width of the mark that shows the state of the control.
  ///
  /// The mark of a check box and of a radio button is a square. A control with
  /// a mark of another shape, a switch with its track, answers with its own
  /// width and height.
  double get markWidth => markSize;

  /// The height of the mark that shows the state of the control.
  double get markHeight => markSize;

  /// The distance between the mark and the text of the label.
  static const double gapSize = 8;

  /// The room the focus ring takes around the mark.
  ///
  /// The ring stands around the mark of the control and not around the whole
  /// control, so the control keeps room for the ring and the ring never
  /// covers the mark itself.
  static const double focusRingPadding = 3;

  /// The color of a control that cannot be used.
  static const Color disabledColor = Color(0xFF9A9A9A);

  static const _headlessFactory = HeadlessTextLayoutFactory();

  final DuiProperty<dynamic, bool> _isCheckedProperty;
  final DuiProperty<dynamic, String> _textProperty;
  final DuiProperty<dynamic, double> _fontSizeProperty;
  final DuiProperty<dynamic, Color> _colorProperty;
  final _changedHandlers = <void Function(bool value)>[];
  final CachedTextLayout _layout = CachedTextLayout();

  /// Whether the control is checked.
  bool get isChecked => getValue<bool>(_isCheckedProperty);
  set isChecked(bool value) => setValue<bool>(_isCheckedProperty, value);

  /// The text of the label next to the mark.
  String get text => getValue<String>(_textProperty);
  set text(String value) => setValue<String>(_textProperty, value);

  /// The size of the font of the label.
  double get fontSize => getValue<double>(_fontSizeProperty);
  set fontSize(double value) => setValue<double>(_fontSizeProperty, value);

  /// The color of the text of the label.
  Color get color => getValue<Color>(_colorProperty);
  set color(Color value) => setValue<Color>(_colorProperty, value);

  /// Adds a handler that is called when the state of the control changes.
  void addChangedHandler(void Function(bool value) handler) =>
      _changedHandlers.add(handler);

  /// Removes a handler that is called when the state of the control changes.
  void removeChangedHandler(void Function(bool value) handler) =>
      _changedHandlers.remove(handler);

  /// Changes the state of the control.
  void toggle() => isChecked = !isChecked;

  /// Changes the state of the control after a click or the space bar.
  ///
  /// A radio button stays checked when it is clicked again, so it overrides
  /// this method.
  void activate() => toggle();

  /// Called when the state of the control changes.
  ///
  /// The control that belongs to a group tells the group about the change.
  void onCheckedChanged(bool isChecked) {}

  /// The rectangle of the mark that shows the state of the control.
  ///
  /// The mark stands at the start of the control: at the left edge from left
  /// to right and at the right edge from right to left. The room of the focus
  /// ring keeps it away from the edge of the control.
  Rect get markRect {
    final width = math.min(
      markWidth,
      math.max(0.0, bounds.width - 2 * focusRingPadding),
    );
    final height = math.min(
      markHeight,
      math.max(0.0, bounds.height - 2 * focusRingPadding),
    );
    final top = bounds.top + (bounds.height - height) / 2;
    if (isRightToLeft) {
      return Rect.fromLTWH(
        bounds.right - focusRingPadding - width,
        top,
        width,
        height,
      );
    }
    return Rect.fromLTWH(bounds.left + focusRingPadding, top, width, height);
  }

  /// The rectangle of the text of the label.
  ///
  /// The text stands next to the mark, on the side of the mark that is not
  /// the start of the control.
  Rect get labelRect {
    final width = math.max(
      0.0,
      bounds.width - focusRingPadding - markWidth - gapSize,
    );
    final left = isRightToLeft
        ? bounds.left
        : bounds.left + focusRingPadding + markWidth + gapSize;
    return Rect.fromLTWH(left, bounds.top, width, bounds.height);
  }

  /// The ring of the focus stands around the mark of the control.
  ///
  /// The ring leaves a gap between itself and the mark, so the mark stays
  /// readable under the ring.
  @override
  Rect get focusRingBounds {
    final mark = markRect;
    return Rect.fromLTWH(
      mark.left - focusRingPadding,
      mark.top - focusRingPadding,
      mark.width + 2 * focusRingPadding,
      mark.height + 2 * focusRingPadding,
    );
  }

  /// Draws the mark that shows the state of the control.
  void renderMark(DrawingContext context, Rect rect);

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
    activate();
    args.handled = true;
  }

  void _keyDown(Object sender, KeyEventArgs args) {
    if (!isEnabled) return;
    if (handleKey(args)) args.handled = true;
  }

  /// Handles the keys that change the state of the control.
  ///
  /// The control that handles a key returns true.
  bool handleKey(KeyEventArgs args) {
    if (args.primaryShortcutPressed) return false;
    if (args.key != 'space') return false;
    activate();
    return true;
  }

  void _propertyChanged(PropertyChangedEvent event) {
    if (!identical(event.property, _isCheckedProperty)) return;
    final value = event.newValue as bool;
    for (final handler in List<void Function(bool)>.of(_changedHandlers)) {
      handler(value);
    }
    onCheckedChanged(value);
  }

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
    final layout = _layoutFor(_labelWidthFor(availableSize));
    return Size(
      focusRingPadding + markWidth + gapSize + layout.width,
      math.max(markHeight + 2 * focusRingPadding, layout.height),
    );
  }

  @override
  void renderContentCore(DrawingContext context) {
    renderMark(context, markRect);

    final layout = _layoutFor(_labelWidthFor(bounds.size));
    final rect = labelRect;
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
  /// The text stands next to the mark, so the mark, the room of the focus
  /// ring and the gap take their part of the width of the control.
  double _labelWidthFor(Size availableSize) {
    final available =
        availableSize.width - focusRingPadding - markWidth - gapSize;
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
}
