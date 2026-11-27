import 'content_control.dart';
import 'control_template.dart';
import 'drawing.dart';
import 'events.dart';
import 'geometry.dart';
import 'properties.dart';
import 'semantics.dart';
import 'ui_element.dart';

final class Button extends ContentControl {
  Button({super.content, void Function()? onClick})
      : super(templateProperty: templateProperty) {
    if (onClick != null) addClickHandler(onClick);
    addHandler(UIElement.pointerDown, _pointerDown);
    addHandler(UIElement.keyDown, _keyDown);
  }

  static const templateProperty = DuiProperty<Button, ControlTemplate<Button>?>(
    name: 'template',
    defaultValue: null,
    affectsMeasure: true,
    affectsPaint: true,
  );

  final _clickHandlers = <void Function()>[];

  /// The template of the button.
  ///
  /// The template owns the look of the button: it presents the content of
  /// the button and reacts to the state of the control.
  @override
  ControlTemplate<Button>? get template =>
      super.template as ControlTemplate<Button>?;

  @override
  bool get handlesPointerPress => true;

  void addClickHandler(void Function() handler) => _clickHandlers.add(handler);
  void removeClickHandler(void Function() handler) =>
      _clickHandlers.remove(handler);

  void _pointerDown(Object sender, PointerEventArgs args) {
    if (!isEnabled) return;
    focus();
  }

  @override
  void onReleased(PointerEventArgs args) {
    _activate();
    args.handled = true;
  }

  void _keyDown(Object sender, KeyEventArgs args) {
    if (!isEnabled ||
        args.primaryShortcutPressed ||
        (args.key != 'space' && args.key != 'enter')) {
      return;
    }
    _activate();
    args.handled = true;
  }

  void _activate() {
    for (final handler in List<void Function()>.of(_clickHandlers)) {
      handler();
    }
  }

  @override
  SemanticsRole get semanticsRole => SemanticsRole.button;

  @override
  SemanticsState get semanticsState => SemanticsState(
        focused: state.focused,
        disabled: !state.enabled,
        pressed: state.pressed,
      );

  @override
  Size measureContentCore(Size availableSize) {
    final childSize = super.measureContentCore(availableSize);
    return Size(childSize.width + 24, childSize.height + 12);
  }

  @override
  void arrangeContentCore(Rect finalRect) {
    content?.arrange(Rect.fromLTWH(
      finalRect.left + 12,
      finalRect.top + 6,
      (finalRect.width - 24).clamp(0, double.infinity),
      (finalRect.height - 12).clamp(0, double.infinity),
    ));
  }

  @override
  void renderContentCore(DrawingContext context) {
    context.drawRect(
      bounds,
      Paint(isPressed ? const Color(0xFFB0B0B0) : const Color(0xFFE0E0E0)),
    );
    super.renderContentCore(context);
  }
}
