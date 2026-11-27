import 'drawing.dart';
import 'events.dart';
import 'geometry.dart';
import 'ui_element.dart';

/// Where a popup is placed relative to the area that opened it.
enum PopupPlacement {
  /// Below the owner area.
  below,

  /// Above the owner area.
  above,

  /// To the right of the owner area.
  right,

  /// To the left of the owner area.
  left,

  /// At the pointer.
  atPointer,

  /// At the top left corner of the owner area.
  atOwner,
}

/// The layer of a window that holds the open popup.
///
/// The layer sits above the content of the window: it has its own layout, it
/// clips the popup to the window and it takes the clicks that fall outside of
/// the popup, so the content under the popup does not react to them.
///
/// The layer belongs to the window: [Window.overlay] is the layer of a window.
final class PopupLayer extends Control {
  PopupLayer() {
    // The layer only takes part in the layout and in the hit test while a
    // popup is open.
    isVisible = false;
    addHandler(UIElement.keyDown, _keyDown);
    addHandler(UIElement.pointerDown, _pointerDown);
  }

  UIElement? _content;
  Rect _ownerArea = Rect.zero;
  Point _pointerPosition = const Point(0, 0);
  PopupPlacement _placement = PopupPlacement.below;
  bool _isOpen = false;
  Control? _focusBeforeOpen;

  /// The content of the popup, if a popup is open.
  UIElement? get content => _content;

  /// Whether a popup is open.
  bool get isOpen => _isOpen;

  /// The area the popup was opened for, in the coordinates of the window.
  Rect get ownerArea => _ownerArea;

  /// The placement of the popup.
  PopupPlacement get placement => _placement;

  /// The rectangle the popup occupies.
  Rect get popupRect => _content?.bounds ?? Rect.zero;

  /// Opens the popup with [content].
  ///
  /// The [ownerArea] is the area of the window the popup belongs to, in the
  /// coordinates of the window. The [pointerPosition] is used by the
  /// [PopupPlacement.atPointer] placement. The content is not disposed when
  /// the popup closes, so it can be opened again.
  void open(
    UIElement content, {
    Rect ownerArea = Rect.zero,
    Point? pointerPosition,
    PopupPlacement placement = PopupPlacement.below,
  }) {
    if (content.logicalParent != null) {
      throw StateError('The popup content already belongs to another parent.');
    }
    _content?.attachToParent(null);
    _content?.mountTo(null);
    _ownerArea = ownerArea;
    _pointerPosition = pointerPosition ?? const Point(0, 0);
    _placement = placement;
    _isOpen = true;
    _content = content;
    content
      ..attachToParent(this)
      ..mountTo(window);
    isVisible = true;
    invalidateMeasure();
    _focusBeforeOpen = window?.focusedElement;
    focus();
  }

  /// Closes the popup and detaches its content.
  void close() {
    if (!_isOpen) return;
    _isOpen = false;
    final content = _content;
    _content = null;
    content
      ?..attachToParent(null)
      ..mountTo(null);
    isVisible = false;
    invalidateMeasure();
    final previous = _focusBeforeOpen;
    _focusBeforeOpen = null;
    if (previous != null && previous.isMounted) previous.focus();
  }

  @override
  bool get isFocusable => true;

  @override
  Iterable<UIElement> get logicalChildren =>
      _content == null ? const [] : [_content!];

  @override
  Size measureCore(Size availableSize) {
    final content = _content;
    if (content == null) return Size.zero;
    return content.measure(availableSize);
  }

  @override
  void arrangeCore(Rect finalRect) {
    final content = _content;
    if (content == null) return;
    content.arrange(_popupArea(content.desiredSize));
  }

  Rect _popupArea(Size size) {
    final width = size.width;
    final height = size.height;
    switch (_placement) {
      case PopupPlacement.below:
        final below = _ownerArea.bottom;
        final fitsBelow = below + height <= bounds.bottom;
        return Rect.fromLTWH(
          _ownerArea.left,
          fitsBelow ? below : _ownerArea.top - height,
          width,
          height,
        );
      case PopupPlacement.above:
        return Rect.fromLTWH(
          _ownerArea.left,
          _ownerArea.top - height,
          width,
          height,
        );
      case PopupPlacement.right:
        return Rect.fromLTWH(
          _ownerArea.right,
          _ownerArea.top,
          width,
          height,
        );
      case PopupPlacement.left:
        return Rect.fromLTWH(
          _ownerArea.left - width,
          _ownerArea.top,
          width,
          height,
        );
      case PopupPlacement.atPointer:
        return Rect.fromLTWH(
          _pointerPosition.x,
          _pointerPosition.y,
          width,
          height,
        );
      case PopupPlacement.atOwner:
        return Rect.fromLTWH(
          _ownerArea.left,
          _ownerArea.top,
          width,
          height,
        );
    }
  }

  @override
  void renderCore(DrawingContext context) {
    final content = _content;
    if (content == null) return;
    context.pushClipRect(bounds);
    try {
      content.render(context);
    } finally {
      context.popClip();
    }
  }

  @override
  UIElement? hitTestCore(Point position) {
    final content = _content;
    if (content == null) return null;
    if (!content.bounds.contains(position)) return null;
    return content.hitTest(position);
  }

  void _keyDown(Object sender, KeyEventArgs args) {
    if (!_isOpen) return;
    if (args.key == 'escape') {
      close();
      args.handled = true;
    }
  }

  void _pointerDown(Object sender, PointerEventArgs args) {
    if (!_isOpen) return;
    // A click outside of the popup closes it, and the click does not reach
    // the content under the popup.
    final content = _content;
    if (content != null && content.bounds.contains(args.position)) return;
    close();
    args.handled = true;
  }
}
