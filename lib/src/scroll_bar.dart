import 'dart:math' as math;

import 'control_template.dart';
import 'drawing.dart';
import 'events.dart';
import 'geometry.dart';
import 'properties.dart';
import 'templated_control.dart';
import 'ui_element.dart';

/// When a scroll bar of a scrollable area is shown.
enum ScrollBarVisibility { disabled, hidden, auto, visible }

/// A scroll bar that shows a part of a scrollable range.
///
/// The bar owns the track and the thumb and reacts to the pointer: the thumb
/// can be dragged, and a click on the track scrolls by one page. The value of
/// the bar is a property, so a scrollable area binds it to its own offset.
///
/// The bar is not focusable: the keyboard belongs to the area that scrolls.
final class ScrollBar extends TemplatedControl {
  ScrollBar({
    Orientation orientation = Orientation.vertical,
    double minimum = 0,
    double maximum = 0,
    double value = 0,
    double viewportSize = 0,
    double thickness = defaultThickness,
  })  : _orientation = orientation,
        super(templateProperty: templateProperty) {
    setValue(minimumProperty, minimum);
    setValue(maximumProperty, maximum);
    setValue(valueProperty, value);
    setValue(viewportSizeProperty, viewportSize);
    setValue(thicknessProperty, thickness);
    addHandler(UIElement.pointerDown, _pointerDown);
    addHandler(UIElement.pointerMove, _pointerMove);
    addHandler(UIElement.pointerUp, _pointerUp);
  }

  static const templateProperty =
      DuiProperty<ScrollBar, ControlTemplate<ScrollBar>?>(
    name: 'template',
    defaultValue: null,
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The template of the scroll bar.
  ///
  /// The template owns the look of the bar: it draws the track and the thumb
  /// and reacts to the value and the orientation of the bar.
  @override
  ControlTemplate<ScrollBar>? get template =>
      super.template as ControlTemplate<ScrollBar>?;

  /// The thickness of a scroll bar.
  static const defaultThickness = 12.0;

  /// The smallest length of the thumb.
  static const minimumThumbSize = 20.0;

  static const orientationProperty = DuiProperty<ScrollBar, Orientation>(
    name: 'orientation',
    defaultValue: Orientation.vertical,
    affectsMeasure: true,
  );
  static const minimumProperty = DuiProperty<ScrollBar, double>(
    name: 'minimum',
    defaultValue: 0,
    affectsPaint: true,
  );
  static const maximumProperty = DuiProperty<ScrollBar, double>(
    name: 'maximum',
    defaultValue: 0,
    affectsPaint: true,
  );
  static const valueProperty = DuiProperty<ScrollBar, double>(
    name: 'value',
    defaultValue: 0,
    affectsPaint: true,
  );
  static const viewportSizeProperty = DuiProperty<ScrollBar, double>(
    name: 'viewportSize',
    defaultValue: 0,
    affectsPaint: true,
  );
  static const thicknessProperty = DuiProperty<ScrollBar, double>(
    name: 'thickness',
    defaultValue: defaultThickness,
    affectsMeasure: true,
  );

  Orientation _orientation;
  bool _isDragging = false;
  Point _dragStartPosition = const Point(0, 0);
  double _dragStartValue = 0;

  /// The direction the bar scrolls in.
  Orientation get orientation => _orientation;
  set orientation(Orientation value) {
    if (_orientation == value) return;
    final oldValue = _orientation;
    _orientation = value;
    invalidateMeasure();
    notifyPropertyChanged(orientationProperty, oldValue, value);
  }

  /// The smallest value of the bar.
  double get minimum => getValue(minimumProperty);
  set minimum(double value) => setValue(minimumProperty, value);

  /// The largest value of the bar.
  double get maximum => getValue(maximumProperty);
  set maximum(double value) => setValue(maximumProperty, value);

  /// The current value of the bar.
  double get value => getValue(valueProperty);
  set value(double value) => setValue(valueProperty, _clamp(value));

  /// The size of the visible part of the scrollable range.
  double get viewportSize => getValue(viewportSizeProperty);
  set viewportSize(double value) => setValue(viewportSizeProperty, value);

  /// The thickness of the bar across the scrolling direction.
  double get thickness => getValue(thicknessProperty);
  set thickness(double value) => setValue(thicknessProperty, value);

  /// Whether the bar has a range to scroll through.
  bool get isScrollable => maximum > minimum;

  /// The length of the track along the scrolling direction.
  double get trackLength =>
      orientation == Orientation.vertical ? bounds.height : bounds.width;

  /// The full length of the scrollable range, the visible part included.
  double get extent => (maximum - minimum) + viewportSize;

  /// The rectangle of the thumb inside the track.
  Rect get thumbRect {
    if (!isScrollable) return Rect.zero;
    final length = trackLength;
    if (length <= 0) return Rect.zero;
    final thumbLength = _thumbLength(length);
    final range = maximum - minimum;
    final scrollable = length - thumbLength;
    final offset = range <= 0 || scrollable <= 0
        ? 0.0
        : scrollable * (value - minimum).clamp(0.0, range) / range;
    return orientation == Orientation.vertical
        ? Rect.fromLTWH(
            bounds.left + 2,
            bounds.top + offset,
            math.max(0, bounds.width - 4),
            thumbLength,
          )
        : Rect.fromLTWH(
            // A horizontal bar of a right to left tree starts at its right
            // edge, so the thumb moves to the left with the growing value.
            isRightToLeft
                ? bounds.right - thumbLength - offset
                : bounds.left + offset,
            bounds.top + 2,
            thumbLength,
            math.max(0, bounds.height - 4),
          );
  }

  double _thumbLength(double length) {
    if (extent <= 0 || viewportSize <= 0) return length;
    final raw = length * viewportSize / extent;
    return raw.clamp(math.min(minimumThumbSize, length), length).toDouble();
  }

  double _clamp(double next) {
    final low = minimum;
    final high = maximum;
    if (high < low) return low;
    return next.clamp(low, high).toDouble();
  }

  @override
  bool get isFocusable => false;

  @override
  Size measureContentCore(Size availableSize) {
    final thickness = this.thickness;
    if (orientation == Orientation.vertical) {
      final length = availableSize.height.isFinite ? availableSize.height : 0.0;
      return Size(thickness, length);
    }
    final length = availableSize.width.isFinite ? availableSize.width : 0.0;
    return Size(length, thickness);
  }

  @override
  void renderContentCore(DrawingContext context) {
    context.drawRect(bounds, const Paint(Color(0xFFF0F0F0)));
    final thumb = thumbRect;
    if (thumb.width > 0 && thumb.height > 0) {
      context.drawRect(thumb, const Paint(Color(0xFFA0A0A0)));
    }
  }

  @override
  UIElement? hitTestContentCore(Point position) => null;

  void _pointerDown(Object sender, PointerEventArgs args) {
    if (!isEnabled || !isScrollable) return;
    if (args.button != PointerButton.primary) return;
    final thumb = thumbRect;
    if (thumb.contains(args.position)) {
      _isDragging = true;
      _dragStartPosition = args.position;
      _dragStartValue = value;
      capturePointer();
      args.handled = true;
      return;
    }
    final page = viewportSize > 0 ? viewportSize : 1;
    final isBefore = orientation == Orientation.vertical
        ? args.position.y < thumb.top
        : isRightToLeft
            ? args.position.x > thumb.right
            : args.position.x < thumb.left;
    _setValue(isBefore ? value - page : value + page);
    args.handled = true;
  }

  void _pointerMove(Object sender, PointerEventArgs args) {
    if (!_isDragging) return;
    final length = trackLength;
    final scrollable = length - _thumbLength(length);
    final range = maximum - minimum;
    if (scrollable > 0 && range > 0) {
      final delta = orientation == Orientation.vertical
          ? args.position.y - _dragStartPosition.y
          : args.position.x - _dragStartPosition.x;
      // The thumb of a horizontal bar of a right to left tree starts at the
      // right edge, so a drag to the right lowers the value.
      final signed = orientation == Orientation.horizontal && isRightToLeft
          ? -delta
          : delta;
      _setValue(_dragStartValue + signed * range / scrollable);
    }
    args.handled = true;
  }

  void _pointerUp(Object sender, PointerEventArgs args) {
    if (!_isDragging) return;
    _isDragging = false;
    releasePointer();
    args.handled = true;
  }

  void _setValue(double next) {
    final clamped = next.clamp(minimum, maximum).toDouble();
    if (clamped == value) return;
    value = clamped;
  }

  @override
  void onUnmounted() {
    _isDragging = false;
  }
}
