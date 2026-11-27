import 'content_control.dart';
import 'control_template.dart';
import 'drawing.dart';
import 'events.dart';
import 'focus_decoration.dart';
import 'geometry.dart';
import 'properties.dart';
import 'semantics.dart';
import 'ui_element.dart';

final class Button extends ContentControl {
  Button({super.content, void Function()? onClick}) {
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
  UIElement? _templateRoot;

  ControlTemplate<Button>? get template => getValue(templateProperty);
  set template(ControlTemplate<Button>? value) =>
      setValue(templateProperty, value);

  /// The persistent root created by the current template, if any.
  UIElement? get templateRoot => _templateRoot;

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
  Iterable<UIElement> get logicalChildren =>
      _templateRoot == null ? super.logicalChildren : [_templateRoot!];

  @override
  SemanticsRole get semanticsRole => SemanticsRole.button;

  @override
  SemanticsState get semanticsState => SemanticsState(
        focused: state.focused,
        disabled: !state.enabled,
        pressed: state.pressed,
      );

  @override
  void onDuiPropertyChanged<T>(
    DuiProperty<dynamic, T> property,
    T oldValue,
    T newValue,
  ) {
    super.onDuiPropertyChanged(property, oldValue, newValue);
    if (identical(property, templateProperty)) {
      _replaceTemplate(newValue as ControlTemplate<Button>?);
    }
  }

  void _replaceTemplate(ControlTemplate<Button>? template) {
    final previous = _templateRoot;
    if (previous != null) {
      _detachPresenters(previous);
      previous
        ..attachToParent(null)
        ..mountTo(null);
      _disposeTemplate(previous);
    }
    _templateRoot = null;
    content
      ?..attachToParent(this)
      ..mountTo(window);

    if (template != null) {
      final created = template.create(this);
      if (created.logicalParent != null) {
        throw StateError('A control template must return an unparented root.');
      }
      _templateRoot = created;
      created
        ..attachToParent(this)
        ..mountTo(window);
    }
    invalidateMeasure();
  }

  void _detachPresenters(UIElement root) {
    if (root is ContentPresenter && identical(root.host, this)) {
      root.detachFromHost();
    }
    for (final child in root.logicalChildren) {
      _detachPresenters(child);
    }
  }

  void _disposeTemplate(UIElement root) {
    for (final child in root.logicalChildren) {
      _disposeTemplate(child);
    }
    root.dispose();
  }

  @override
  Size measureCore(Size availableSize) {
    final root = _templateRoot;
    if (root != null) return root.measure(availableSize);
    final childSize = super.measureCore(availableSize);
    return Size(childSize.width + 24, childSize.height + 12);
  }

  @override
  void arrangeCore(Rect finalRect) {
    final root = _templateRoot;
    if (root != null) {
      root.arrange(finalRect);
      return;
    }
    content?.arrange(Rect.fromLTWH(
      finalRect.left + 12,
      finalRect.top + 6,
      (finalRect.width - 24).clamp(0, double.infinity),
      (finalRect.height - 12).clamp(0, double.infinity),
    ));
  }

  @override
  void renderCore(DrawingContext context) {
    final root = _templateRoot;
    if (root != null) {
      root.render(context);
      if (isFocused) {
        drawFocusRing(
          context,
          bounds,
          shape: template?.focusRingShape ?? FocusRingShape.rectangle,
        );
      }
      return;
    }
    context.drawRect(
      bounds,
      Paint(isPressed ? const Color(0xFFB0B0B0) : const Color(0xFFE0E0E0)),
    );
    if (isFocused) drawFocusRing(context, bounds);
    super.renderCore(context);
  }

  @override
  UIElement? hitTestCore(Point position) {
    final root = _templateRoot;
    return root == null ? super.hitTestCore(position) : root.hitTest(position);
  }
}
