import 'control_template.dart';
import 'drawing.dart';
import 'focus_decoration.dart';
import 'geometry.dart';
import 'properties.dart';
import 'ui_element.dart';

/// A control whose look is built by a template.
///
/// The template creates one persistent visual subtree for the control. The
/// control measures, arranges, renders and hit tests that subtree instead of
/// its own content, so the look of any control can be replaced without
/// touching the control itself.
abstract class TemplatedControl extends Control {
  TemplatedControl({
    DuiProperty<dynamic, ControlTemplate<dynamic>?>? templateProperty,
  }) : _templateProperty = templateProperty;

  final DuiProperty<dynamic, ControlTemplate<dynamic>?>? _templateProperty;

  /// The template of the control, if it has one.
  ///
  /// A control without a template property does not support templates: its
  /// template is always null and setting it throws.
  ControlTemplate<dynamic>? get template =>
      _templateProperty == null ? null : getValue(_templateProperty);

  set template(ControlTemplate<dynamic>? value) {
    final property = _templateProperty;
    if (property == null) {
      throw StateError('The control does not support a template.');
    }
    setValue(property, value);
  }

  /// The persistent root created by the current template, if any.
  UIElement? get templateRoot => _templateRoot;
  UIElement? _templateRoot;

  /// Whether the control draws a template instead of its own content.
  bool get hasTemplate => _templateRoot != null;

  @override
  void onDuiPropertyChanged<T>(
    DuiProperty<dynamic, T> property,
    T oldValue,
    T newValue,
  ) {
    super.onDuiPropertyChanged(property, oldValue, newValue);
    if (identical(property, _templateProperty)) {
      _replaceTemplate(newValue as ControlTemplate<dynamic>?);
    }
  }

  void _replaceTemplate(ControlTemplate<dynamic>? template) {
    final previous = _templateRoot;
    if (previous != null) {
      _detachPresenters(previous);
      previous
        ..attachToParent(null)
        ..mountTo(null);
      _disposeTemplate(previous);
    }
    _templateRoot = null;
    onTemplateReplacing();
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

  /// Called after the old template is gone and before the new one is built.
  ///
  /// A control with content takes its content back here, so the new template
  /// can present it again.
  void onTemplateReplacing() {}

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
  Iterable<UIElement> get logicalChildren =>
      _templateRoot == null ? super.logicalChildren : [_templateRoot!];

  @override
  Size measureCore(Size availableSize) {
    final root = _templateRoot;
    if (root != null) return root.measure(availableSize);
    return measureContentCore(availableSize);
  }

  /// Measures the own content of the control, when it has no template.
  Size measureContentCore(Size availableSize) => Size.zero;

  @override
  void arrangeCore(Rect finalRect) {
    final root = _templateRoot;
    if (root != null) {
      root.arrange(finalRect);
      return;
    }
    arrangeContentCore(finalRect);
  }

  /// Arranges the own content of the control, when it has no template.
  void arrangeContentCore(Rect finalRect) {}

  @override
  void renderCore(DrawingContext context) {
    final root = _templateRoot;
    if (root != null) {
      root.render(context);
    } else {
      renderContentCore(context);
    }
    if (isFocused && isFocusable) {
      drawFocusRing(
        context,
        bounds,
        shape: template?.focusRingShape ?? FocusRingShape.rectangle,
      );
    }
  }

  /// Draws the own content of the control, when it has no template.
  void renderContentCore(DrawingContext context) {}

  @override
  UIElement? hitTestCore(Point position) {
    final root = _templateRoot;
    return root == null ? hitTestContentCore(position) : root.hitTest(position);
  }

  /// Looks for the own content of the control under the position, when it has
  /// no template.
  UIElement? hitTestContentCore(Point position) => null;
}
