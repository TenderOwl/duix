import 'dart:math' as math;

import 'content_control.dart';
import 'control_template.dart';
import 'drawing.dart';
import 'events.dart';
import 'geometry.dart';
import 'observable.dart';
import 'properties.dart';
import 'scroll_bar.dart';
import 'template_part.dart';
import 'ui_element.dart';

/// A scrollable area.
///
/// The viewer keeps the offset of the content and delegates the appearance
/// and the dragging of the scroll bars to two [ScrollBar] controls.
///
/// The content and the scroll bars are parts of the viewer: the viewer owns
/// them and draws them, a template only places them. The content of the
/// viewer therefore survives every template.
final class ScrollViewer extends ContentControl {
  // The content cannot be a super parameter: the viewer passes its own
  // template property to the content control.
  // ignore: use_super_parameters
  ScrollViewer({
    UIElement? content,
    ScrollBarVisibility horizontalScrollBarVisibility =
        ScrollBarVisibility.auto,
    ScrollBarVisibility verticalScrollBarVisibility = ScrollBarVisibility.auto,
  })  : _horizontalScrollBarVisibility = horizontalScrollBarVisibility,
        _verticalScrollBarVisibility = verticalScrollBarVisibility,
        super(content: content, templateProperty: templateProperty) {
    _horizontalBar = ScrollBar(orientation: Orientation.horizontal);
    _verticalBar = ScrollBar(orientation: Orientation.vertical);
    _contentPart = TemplatePart('content', this);
    registerPart('content', _contentPart);
    registerPart('horizontalScrollBar', _horizontalBar);
    registerPart('verticalScrollBar', _verticalBar);
    _horizontalBar.addPropertyListener(_barValueChanged);
    _verticalBar.addPropertyListener(_barValueChanged);
    addHandler(UIElement.pointerDown, _pointerDown);
    addHandler(UIElement.mouseWheel, _mouseWheel);
    addHandler(UIElement.keyDown, _keyDown);
  }

  static const templateProperty =
      DuiProperty<ScrollViewer, ControlTemplate<ScrollViewer>?>(
    name: 'template',
    defaultValue: null,
    affectsMeasure: true,
    affectsPaint: true,
  );

  static const scrollBarThickness = ScrollBar.defaultThickness;
  static const wheelScrollDistance = 48.0;
  static const lineScrollDistance = 40.0;

  ScrollBarVisibility _horizontalScrollBarVisibility;
  ScrollBarVisibility _verticalScrollBarVisibility;
  late final ScrollBar _horizontalBar;
  late final ScrollBar _verticalBar;
  late final TemplatePart _contentPart;
  double _horizontalOffset = 0;
  double _verticalOffset = 0;
  double _viewportWidth = 0;
  double _viewportHeight = 0;
  double _extentWidth = 0;
  double _extentHeight = 0;
  Size _contentSize = Size.zero;
  bool _isHorizontalScrollBarVisible = false;
  bool _isVerticalScrollBarVisible = false;
  bool _isSyncingBars = false;
  Rect _viewportRect = Rect.zero;

  /// The template of the scroll viewer.
  ///
  /// The template owns the look of the viewer: it places the part with the
  /// content and the two scroll bars. The content and the bars stay with the
  /// viewer.
  @override
  ControlTemplate<ScrollViewer>? get template =>
      super.template as ControlTemplate<ScrollViewer>?;

  ScrollBarVisibility get horizontalScrollBarVisibility =>
      _horizontalScrollBarVisibility;
  set horizontalScrollBarVisibility(ScrollBarVisibility value) {
    if (_horizontalScrollBarVisibility == value) return;
    _horizontalScrollBarVisibility = value;
    if (value == ScrollBarVisibility.disabled) _horizontalOffset = 0;
    invalidateMeasure();
  }

  ScrollBarVisibility get verticalScrollBarVisibility =>
      _verticalScrollBarVisibility;
  set verticalScrollBarVisibility(ScrollBarVisibility value) {
    if (_verticalScrollBarVisibility == value) return;
    _verticalScrollBarVisibility = value;
    if (value == ScrollBarVisibility.disabled) _verticalOffset = 0;
    invalidateMeasure();
  }

  /// The horizontal scroll bar of the viewer.
  ScrollBar get horizontalScrollBar => _horizontalBar;

  /// The vertical scroll bar of the viewer.
  ScrollBar get verticalScrollBar => _verticalBar;

  /// The part of the viewer that holds the scrolled content.
  UIElement get contentPart => _contentPart;

  double get horizontalOffset => _horizontalOffset;
  set horizontalOffset(double value) => scrollTo(horizontal: value);

  double get verticalOffset => _verticalOffset;
  set verticalOffset(double value) => scrollTo(vertical: value);

  double get viewportWidth => _viewportWidth;
  double get viewportHeight => _viewportHeight;
  double get extentWidth => _extentWidth;
  double get extentHeight => _extentHeight;
  Size get viewportSize => Size(_viewportWidth, _viewportHeight);
  Size get extentSize => Size(_extentWidth, _extentHeight);
  Rect get viewportRect => _viewportRect;
  Rect get horizontalTrackRect => _horizontalBar.bounds;
  Rect get verticalTrackRect => _verticalBar.bounds;
  Rect get horizontalThumbRect => _horizontalBar.thumbRect;
  Rect get verticalThumbRect => _verticalBar.thumbRect;

  bool get isHorizontalScrollBarVisible => _isHorizontalScrollBarVisible;
  bool get isVerticalScrollBarVisible => _isVerticalScrollBarVisible;
  bool get canScrollHorizontally =>
      _horizontalScrollBarVisibility != ScrollBarVisibility.disabled &&
      _extentWidth > _viewportWidth;
  bool get canScrollVertically =>
      _verticalScrollBarVisibility != ScrollBarVisibility.disabled &&
      _extentHeight > _viewportHeight;

  double get _maxHorizontalOffset => math.max(0, _extentWidth - _viewportWidth);
  double get _maxVerticalOffset => math.max(0, _extentHeight - _viewportHeight);

  bool scrollTo({double? horizontal, double? vertical}) {
    if (horizontal != null && (horizontal.isNaN || horizontal < 0)) {
      throw ArgumentError.value(
          horizontal, 'horizontal', 'Must be non-negative.');
    }
    if (vertical != null && (vertical.isNaN || vertical < 0)) {
      throw ArgumentError.value(vertical, 'vertical', 'Must be non-negative.');
    }
    final nextHorizontal = horizontal == null
        ? _horizontalOffset
        : horizontal.clamp(0.0, _maxHorizontalOffset);
    final nextVertical = vertical == null
        ? _verticalOffset
        : vertical.clamp(0.0, _maxVerticalOffset);
    if (nextHorizontal == _horizontalOffset &&
        nextVertical == _verticalOffset) {
      return false;
    }

    final oldHorizontal = _horizontalOffset;
    final oldVertical = _verticalOffset;
    _horizontalOffset = nextHorizontal;
    _verticalOffset = nextVertical;
    invalidateArrange();
    _syncScrollBars();
    if (oldHorizontal != nextHorizontal) {
      notifyPropertyChanged('horizontalOffset', oldHorizontal, nextHorizontal);
    }
    if (oldVertical != nextVertical) {
      notifyPropertyChanged('verticalOffset', oldVertical, nextVertical);
    }
    return true;
  }

  bool scrollBy({double horizontal = 0, double vertical = 0}) {
    if (!horizontal.isFinite || !vertical.isFinite) {
      throw ArgumentError('Scroll deltas must be finite.');
    }
    return scrollTo(
      horizontal: math.max(0, _horizontalOffset + horizontal),
      vertical: math.max(0, _verticalOffset + vertical),
    );
  }

  void scrollToStart() => scrollTo(horizontal: 0, vertical: 0);
  void scrollToEnd() => scrollTo(
        horizontal: _maxHorizontalOffset,
        vertical: _maxVerticalOffset,
      );

  @override
  Iterable<UIElement> get logicalChildren {
    final children = <UIElement>[...super.logicalChildren];
    final current = content;
    if (current != null &&
        !children.contains(current) &&
        identical(current.logicalParent, this)) {
      children.add(current);
    }
    return children;
  }

  @override
  Size measureContentCore(Size availableSize) =>
      _contentPart.measure(availableSize);

  @override
  Size measurePart(UIElement part, Size availableSize) {
    if (!identical(part, _contentPart)) {
      return super.measurePart(part, availableSize);
    }
    return _measureScrollable(availableSize);
  }

  /// Measures the content and settles which scroll bars are shown.
  Size _measureScrollable(Size availableSize) {
    var showHorizontal =
        _horizontalScrollBarVisibility == ScrollBarVisibility.visible;
    var showVertical =
        _verticalScrollBarVisibility == ScrollBarVisibility.visible;
    var contentSize = Size.zero;

    for (var pass = 0; pass < 4; pass++) {
      final viewportAvailable = Size(
        _subtractBar(availableSize.width, showVertical),
        _subtractBar(availableSize.height, showHorizontal),
      );
      contentSize = content?.measure(
            Size(
              _horizontalScrollBarVisibility == ScrollBarVisibility.disabled
                  ? viewportAvailable.width
                  : double.infinity,
              _verticalScrollBarVisibility == ScrollBarVisibility.disabled
                  ? viewportAvailable.height
                  : double.infinity,
            ),
          ) ??
          Size.zero;
      final nextShowHorizontal = _shouldShowScrollBar(
        _horizontalScrollBarVisibility,
        contentSize.width,
        viewportAvailable.width,
      );
      final nextShowVertical = _shouldShowScrollBar(
        _verticalScrollBarVisibility,
        contentSize.height,
        viewportAvailable.height,
      );
      if (nextShowHorizontal == showHorizontal &&
          nextShowVertical == showVertical) {
        break;
      }
      showHorizontal = nextShowHorizontal;
      showVertical = nextShowVertical;
    }

    _isHorizontalScrollBarVisible = showHorizontal;
    _isVerticalScrollBarVisible = showVertical;
    _contentSize = contentSize;
    final maximumViewport = Size(
      _subtractBar(availableSize.width, showVertical),
      _subtractBar(availableSize.height, showHorizontal),
    );
    _viewportWidth = math.min(contentSize.width, maximumViewport.width);
    _viewportHeight = math.min(contentSize.height, maximumViewport.height);
    _extentWidth = math.max(contentSize.width, _viewportWidth);
    _extentHeight = math.max(contentSize.height, _viewportHeight);
    // The viewport of the measure is only an estimate: a template may measure
    // the part with free space, so the offset is clamped when the part is
    // arranged and the real viewport is known.
    if (_horizontalScrollBarVisibility == ScrollBarVisibility.disabled) {
      _horizontalOffset = 0;
    }
    if (_verticalScrollBarVisibility == ScrollBarVisibility.disabled) {
      _verticalOffset = 0;
    }

    return Size(
      _viewportWidth + (showVertical ? scrollBarThickness : 0),
      _viewportHeight + (showHorizontal ? scrollBarThickness : 0),
    );
  }

  static double _subtractBar(double available, bool visible) {
    if (!visible) return available;
    return math.max(0, available - scrollBarThickness);
  }

  static bool _shouldShowScrollBar(
    ScrollBarVisibility visibility,
    double extent,
    double viewport,
  ) {
    return switch (visibility) {
      ScrollBarVisibility.visible => true,
      ScrollBarVisibility.auto => extent > viewport,
      ScrollBarVisibility.disabled || ScrollBarVisibility.hidden => false,
    };
  }

  void _clampOffsets() {
    _horizontalOffset =
        _horizontalScrollBarVisibility == ScrollBarVisibility.disabled
            ? 0
            : _horizontalOffset.clamp(0.0, _maxHorizontalOffset);
    _verticalOffset =
        _verticalScrollBarVisibility == ScrollBarVisibility.disabled
            ? 0
            : _verticalOffset.clamp(0.0, _maxVerticalOffset);
  }

  @override
  void arrangeCore(Rect finalRect) {
    // Without a template the viewport is the control minus the scroll bars.
    // With a template the part with the content decides the viewport.
    _viewportWidth = math.max(
      0,
      finalRect.width - (_isVerticalScrollBarVisible ? scrollBarThickness : 0),
    );
    _viewportHeight = math.max(
      0,
      finalRect.height -
          (_isHorizontalScrollBarVisible ? scrollBarThickness : 0),
    );
    _viewportRect = Rect.fromLTWH(
      finalRect.left,
      finalRect.top,
      _viewportWidth,
      _viewportHeight,
    );
    super.arrangeCore(finalRect);
    if (hasTemplate) _updateScrollBarVisibility();
    _syncScrollBars();
  }

  /// Settles which scroll bars are shown, now that the viewport is known.
  ///
  /// A template decides how large the viewport is, so the bars follow the
  /// area the template gave to the content.
  void _updateScrollBarVisibility() {
    _isHorizontalScrollBarVisible = _shouldShowScrollBar(
      _horizontalScrollBarVisibility,
      _contentSize.width,
      _viewportWidth,
    );
    _isVerticalScrollBarVisible = _shouldShowScrollBar(
      _verticalScrollBarVisibility,
      _contentSize.height,
      _viewportHeight,
    );
  }

  @override
  void arrangePart(UIElement part, Rect finalRect) {
    if (!identical(part, _contentPart)) {
      super.arrangePart(part, finalRect);
      return;
    }
    _viewportWidth = finalRect.width;
    _viewportHeight = finalRect.height;
    _viewportRect = finalRect;
    final contentSize = content?.desiredSize ?? Size.zero;
    _extentWidth = math.max(contentSize.width, _viewportWidth);
    _extentHeight = math.max(contentSize.height, _viewportHeight);
    _clampOffsets();

    final contentWidth = math.max(contentSize.width, _viewportWidth);
    final contentHeight = math.max(contentSize.height, _viewportHeight);
    // The content starts at the start of the direction: at the left edge of
    // the viewport from left to right and at its right edge from right to
    // left. The offset is counted from that start.
    final contentLeft = isRightToLeft
        ? finalRect.right - contentWidth + _horizontalOffset
        : finalRect.left - _horizontalOffset;
    content?.arrange(Rect.fromLTWH(
      contentLeft,
      finalRect.top - _verticalOffset,
      contentWidth,
      contentHeight,
    ));
  }

  @override
  Rect partRect(UIElement part, Rect contentRect) {
    if (identical(part, _contentPart)) return _viewportRect;
    if (identical(part, _horizontalBar)) {
      return _isHorizontalScrollBarVisible
          ? Rect.fromLTWH(
              contentRect.left,
              contentRect.bottom - scrollBarThickness,
              _viewportWidth,
              scrollBarThickness,
            )
          : Rect.zero;
    }
    if (identical(part, _verticalBar)) {
      return _isVerticalScrollBarVisible
          ? Rect.fromLTWH(
              isRightToLeft
                  ? contentRect.left
                  : contentRect.right - scrollBarThickness,
              contentRect.top,
              scrollBarThickness,
              _viewportHeight,
            )
          : Rect.zero;
    }
    return super.partRect(part, contentRect);
  }

  @override
  void renderContentCore(DrawingContext context) {
    if (_isHorizontalScrollBarVisible && _isVerticalScrollBarVisible) {
      context.drawRect(
        Rect.fromLTWH(
          isRightToLeft ? bounds.left : bounds.right - scrollBarThickness,
          bounds.bottom - scrollBarThickness,
          scrollBarThickness,
          scrollBarThickness,
        ),
        const Paint(Color(0xFFF0F0F0)),
      );
    }
  }

  @override
  void renderPart(UIElement part, DrawingContext context) {
    if (!identical(part, _contentPart)) return;
    context.pushClipRect(_contentPart.bounds);
    try {
      content?.render(context);
    } finally {
      context.popClip();
    }
  }

  @override
  UIElement? hitTestContentCore(Point position) {
    final bar =
        _verticalBar.hitTest(position) ?? _horizontalBar.hitTest(position);
    if (bar != null) return bar;
    if (!_viewportRect.contains(position)) return null;
    return content?.hitTest(position);
  }

  @override
  UIElement? hitTestPart(UIElement part, Point position) {
    if (!identical(part, _contentPart)) {
      return super.hitTestPart(part, position);
    }
    if (!_contentPart.bounds.contains(position)) return null;
    return content?.hitTest(position);
  }

  void _syncScrollBars() {
    _isSyncingBars = true;
    try {
      _horizontalBar
        ..minimum = 0
        ..maximum = _maxHorizontalOffset
        ..value = _horizontalOffset
        ..viewportSize = _viewportWidth
        ..thickness = scrollBarThickness
        ..isVisible = _isHorizontalScrollBarVisible;
      _verticalBar
        ..minimum = 0
        ..maximum = _maxVerticalOffset
        ..value = _verticalOffset
        ..viewportSize = _viewportHeight
        ..thickness = scrollBarThickness
        ..isVisible = _isVerticalScrollBarVisible;
    } finally {
      _isSyncingBars = false;
    }
  }

  void _barValueChanged(PropertyChangedEvent event) {
    if (!identical(event.property, ScrollBar.valueProperty)) return;
    if (_isSyncingBars) return;
    final value = event.newValue as double;
    final source = event.source;
    if (identical(source, _horizontalBar)) {
      scrollTo(horizontal: value);
    } else if (identical(source, _verticalBar)) {
      scrollTo(vertical: value);
    }
  }

  void _pointerDown(Object sender, PointerEventArgs args) {
    if (!isEnabled) return;
    if (!_hasFocusedDescendant()) focus();
  }

  bool _hasFocusedDescendant() {
    UIElement? focused = window?.focusedElement;
    while (focused != null) {
      if (identical(focused, this)) return true;
      focused = focused.logicalParent;
    }
    return false;
  }

  void _mouseWheel(Object sender, MouseWheelEventArgs args) {
    // The wheel is a physical device, so it moves the content the way it
    // moves in a tree from left to right.
    final horizontal = isRightToLeft ? -args.deltaX : args.deltaX;
    var handled = scrollBy(
      horizontal: horizontal * wheelScrollDistance,
      vertical: -args.deltaY * wheelScrollDistance,
    );
    if (!handled && args.deltaY != 0 && canScrollHorizontally) {
      handled = scrollBy(
        horizontal:
            (isRightToLeft ? args.deltaY : -args.deltaY) * wheelScrollDistance,
      );
    }
    args.handled = handled;
  }

  void _keyDown(Object sender, KeyEventArgs args) {
    if (!isEnabled) return;
    // The keys move the content the way they move it in a tree from left to
    // right.
    final horizontal = isRightToLeft ? -1.0 : 1.0;
    final handled = switch (args.key) {
      'up' when !args.primaryShortcutPressed =>
        scrollBy(vertical: -lineScrollDistance),
      'down' when !args.primaryShortcutPressed =>
        scrollBy(vertical: lineScrollDistance),
      'left' when !args.primaryShortcutPressed =>
        scrollBy(horizontal: -horizontal * lineScrollDistance),
      'right' when !args.primaryShortcutPressed =>
        scrollBy(horizontal: horizontal * lineScrollDistance),
      'pageup' when !args.primaryShortcutPressed =>
        scrollBy(vertical: -_viewportHeight),
      'pagedown' when !args.primaryShortcutPressed =>
        scrollBy(vertical: _viewportHeight),
      'home' => scrollTo(vertical: 0),
      'end' => scrollTo(vertical: _maxVerticalOffset),
      _ => false,
    };
    args.handled = handled;
  }
}
