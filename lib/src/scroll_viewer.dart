import 'dart:math' as math;

import 'content_control.dart';
import 'drawing.dart';
import 'events.dart';
import 'geometry.dart';
import 'ui_element.dart';

enum ScrollBarVisibility { disabled, hidden, auto, visible }

final class ScrollViewer extends ContentControl {
  ScrollViewer({
    super.content,
    ScrollBarVisibility horizontalScrollBarVisibility =
        ScrollBarVisibility.auto,
    ScrollBarVisibility verticalScrollBarVisibility = ScrollBarVisibility.auto,
  })  : _horizontalScrollBarVisibility = horizontalScrollBarVisibility,
        _verticalScrollBarVisibility = verticalScrollBarVisibility {
    addHandler(UIElement.pointerDown, _pointerDown);
    addHandler(UIElement.pointerMove, _pointerMove);
    addHandler(UIElement.pointerUp, _pointerUp);
    addHandler(UIElement.mouseWheel, _mouseWheel);
    addHandler(UIElement.keyDown, _keyDown);
  }

  static const scrollBarThickness = 12.0;
  static const wheelScrollDistance = 48.0;
  static const lineScrollDistance = 40.0;
  static const _minimumThumbSize = 20.0;

  ScrollBarVisibility _horizontalScrollBarVisibility;
  ScrollBarVisibility _verticalScrollBarVisibility;
  double _horizontalOffset = 0;
  double _verticalOffset = 0;
  double _viewportWidth = 0;
  double _viewportHeight = 0;
  double _extentWidth = 0;
  double _extentHeight = 0;
  bool _isHorizontalScrollBarVisible = false;
  bool _isVerticalScrollBarVisible = false;
  Rect _viewportRect = Rect.zero;
  Rect _horizontalTrackRect = Rect.zero;
  Rect _verticalTrackRect = Rect.zero;
  Rect _horizontalThumbRect = Rect.zero;
  Rect _verticalThumbRect = Rect.zero;
  Orientation? _draggingScrollBar;
  Point _dragStartPosition = const Point(0, 0);
  double _dragStartOffset = 0;

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
  Rect get horizontalTrackRect => _horizontalTrackRect;
  Rect get verticalTrackRect => _verticalTrackRect;
  Rect get horizontalThumbRect => _horizontalThumbRect;
  Rect get verticalThumbRect => _verticalThumbRect;

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
  Size measureContentCore(Size availableSize) {
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
    final maximumViewport = Size(
      _subtractBar(availableSize.width, showVertical),
      _subtractBar(availableSize.height, showHorizontal),
    );
    _viewportWidth = math.min(contentSize.width, maximumViewport.width);
    _viewportHeight = math.min(contentSize.height, maximumViewport.height);
    _extentWidth = math.max(contentSize.width, _viewportWidth);
    _extentHeight = math.max(contentSize.height, _viewportHeight);
    _horizontalOffset =
        _horizontalScrollBarVisibility == ScrollBarVisibility.disabled
            ? 0
            : _horizontalOffset.clamp(0.0, _maxHorizontalOffset);
    _verticalOffset =
        _verticalScrollBarVisibility == ScrollBarVisibility.disabled
            ? 0
            : _verticalOffset.clamp(0.0, _maxVerticalOffset);

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

  @override
  void arrangeContentCore(Rect finalRect) {
    _viewportWidth = math.max(
      0,
      finalRect.width - (_isVerticalScrollBarVisible ? scrollBarThickness : 0),
    );
    _viewportHeight = math.max(
      0,
      finalRect.height -
          (_isHorizontalScrollBarVisible ? scrollBarThickness : 0),
    );
    final contentSize = content?.desiredSize ?? Size.zero;
    _extentWidth = math.max(contentSize.width, _viewportWidth);
    _extentHeight = math.max(contentSize.height, _viewportHeight);
    _horizontalOffset =
        _horizontalOffset.clamp(0.0, _maxHorizontalOffset).toDouble();
    _verticalOffset = _verticalOffset.clamp(0.0, _maxVerticalOffset).toDouble();
    _viewportRect = Rect.fromLTWH(
      finalRect.left,
      finalRect.top,
      _viewportWidth,
      _viewportHeight,
    );

    content?.arrange(Rect.fromLTWH(
      finalRect.left - _horizontalOffset,
      finalRect.top - _verticalOffset,
      math.max(contentSize.width, _viewportWidth),
      math.max(contentSize.height, _viewportHeight),
    ));

    _verticalTrackRect = _isVerticalScrollBarVisible
        ? Rect.fromLTWH(
            finalRect.right - scrollBarThickness,
            finalRect.top,
            scrollBarThickness,
            _viewportHeight,
          )
        : Rect.zero;
    _horizontalTrackRect = _isHorizontalScrollBarVisible
        ? Rect.fromLTWH(
            finalRect.left,
            finalRect.bottom - scrollBarThickness,
            _viewportWidth,
            scrollBarThickness,
          )
        : Rect.zero;
    _verticalThumbRect = _thumbRect(_verticalTrackRect, Orientation.vertical);
    _horizontalThumbRect =
        _thumbRect(_horizontalTrackRect, Orientation.horizontal);
  }

  Rect _thumbRect(Rect track, Orientation orientation) {
    final vertical = orientation == Orientation.vertical;
    final trackLength = vertical ? track.height : track.width;
    if (trackLength <= 0) return Rect.zero;
    final viewport = vertical ? _viewportHeight : _viewportWidth;
    final extent = vertical ? _extentHeight : _extentWidth;
    final offset = vertical ? _verticalOffset : _horizontalOffset;
    final maximum = math.max(0, extent - viewport);
    final thumbLength = extent <= 0
        ? trackLength
        : (trackLength * viewport / extent)
            .clamp(math.min(_minimumThumbSize, trackLength), trackLength)
            .toDouble();
    final thumbOffset =
        maximum <= 0 ? 0.0 : (trackLength - thumbLength) * offset / maximum;
    return vertical
        ? Rect.fromLTWH(
            track.left + 2,
            track.top + thumbOffset,
            math.max(0, track.width - 4),
            thumbLength,
          )
        : Rect.fromLTWH(
            track.left + thumbOffset,
            track.top + 2,
            thumbLength,
            math.max(0, track.height - 4),
          );
  }

  @override
  void renderContentCore(DrawingContext context) {
    context.pushClipRect(_viewportRect);
    try {
      content?.render(context);
    } finally {
      context.popClip();
    }

    _drawScrollBar(context, _verticalTrackRect, _verticalThumbRect);
    _drawScrollBar(context, _horizontalTrackRect, _horizontalThumbRect);
    if (_isHorizontalScrollBarVisible && _isVerticalScrollBarVisible) {
      context.drawRect(
        Rect.fromLTWH(
          bounds.right - scrollBarThickness,
          bounds.bottom - scrollBarThickness,
          scrollBarThickness,
          scrollBarThickness,
        ),
        const Paint(Color(0xFFF0F0F0)),
      );
    }
  }

  static void _drawScrollBar(
    DrawingContext context,
    Rect track,
    Rect thumb,
  ) {
    if (track.width <= 0 || track.height <= 0) return;
    context.drawRect(track, const Paint(Color(0xFFF0F0F0)));
    if (thumb.width > 0 && thumb.height > 0) {
      context.drawRect(thumb, const Paint(Color(0xFFA0A0A0)));
    }
  }

  @override
  UIElement? hitTestContentCore(Point position) {
    if (_verticalTrackRect.contains(position) ||
        _horizontalTrackRect.contains(position)) {
      return this;
    }
    if (!_viewportRect.contains(position)) return null;
    return content?.hitTest(position);
  }

  void _pointerDown(Object sender, PointerEventArgs args) {
    if (!isEnabled || args.button != PointerButton.primary) return;
    if (_verticalTrackRect.contains(args.position)) {
      focus();
      if (_verticalThumbRect.contains(args.position)) {
        _startThumbDrag(Orientation.vertical, args.position);
      } else {
        scrollBy(
          vertical: args.position.y < _verticalThumbRect.top
              ? -_viewportHeight
              : _viewportHeight,
        );
      }
      args.handled = true;
      return;
    }
    if (_horizontalTrackRect.contains(args.position)) {
      focus();
      if (_horizontalThumbRect.contains(args.position)) {
        _startThumbDrag(Orientation.horizontal, args.position);
      } else {
        scrollBy(
          horizontal: args.position.x < _horizontalThumbRect.left
              ? -_viewportWidth
              : _viewportWidth,
        );
      }
      args.handled = true;
      return;
    }
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

  void _startThumbDrag(Orientation orientation, Point position) {
    _draggingScrollBar = orientation;
    _dragStartPosition = position;
    _dragStartOffset = orientation == Orientation.vertical
        ? _verticalOffset
        : _horizontalOffset;
    capturePointer();
  }

  void _pointerMove(Object sender, PointerEventArgs args) {
    final orientation = _draggingScrollBar;
    if (orientation == null) return;
    final vertical = orientation == Orientation.vertical;
    final track = vertical ? _verticalTrackRect : _horizontalTrackRect;
    final thumb = vertical ? _verticalThumbRect : _horizontalThumbRect;
    final trackLength = vertical ? track.height : track.width;
    final thumbLength = vertical ? thumb.height : thumb.width;
    final scrollableTrack = math.max(0, trackLength - thumbLength);
    if (scrollableTrack > 0) {
      final pointerDelta = vertical
          ? args.position.y - _dragStartPosition.y
          : args.position.x - _dragStartPosition.x;
      final maximum = vertical ? _maxVerticalOffset : _maxHorizontalOffset;
      final next = math.max(
        0.0,
        _dragStartOffset + pointerDelta * maximum / scrollableTrack,
      );
      if (vertical) {
        scrollTo(vertical: next);
      } else {
        scrollTo(horizontal: next);
      }
    }
    args.handled = true;
  }

  void _pointerUp(Object sender, PointerEventArgs args) {
    if (_draggingScrollBar == null || args.button != PointerButton.primary) {
      return;
    }
    _draggingScrollBar = null;
    releasePointer();
    args.handled = true;
  }

  void _mouseWheel(Object sender, MouseWheelEventArgs args) {
    var handled = scrollBy(
      horizontal: args.deltaX * wheelScrollDistance,
      vertical: -args.deltaY * wheelScrollDistance,
    );
    if (!handled && args.deltaY != 0 && canScrollHorizontally) {
      handled = scrollBy(horizontal: -args.deltaY * wheelScrollDistance);
    }
    args.handled = handled;
  }

  void _keyDown(Object sender, KeyEventArgs args) {
    if (!isEnabled) return;
    final handled = switch (args.key) {
      'up' when !args.primaryShortcutPressed =>
        scrollBy(vertical: -lineScrollDistance),
      'down' when !args.primaryShortcutPressed =>
        scrollBy(vertical: lineScrollDistance),
      'left' when !args.primaryShortcutPressed =>
        scrollBy(horizontal: -lineScrollDistance),
      'right' when !args.primaryShortcutPressed =>
        scrollBy(horizontal: lineScrollDistance),
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

  @override
  void onUnmounted() {
    _draggingScrollBar = null;
  }
}
