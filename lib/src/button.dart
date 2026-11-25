import 'content_control.dart';
import 'drawing.dart';
import 'events.dart';
import 'geometry.dart';
import 'ui_element.dart';

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
