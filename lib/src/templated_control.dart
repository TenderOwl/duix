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
///
/// A control can also offer named parts. A part is a piece of the control that
/// the template places: the text of a text box, the scroll bars of a
/// scrollable area. The control keeps the part and draws its content, so a
/// template never takes the content away: it only decides where the part
/// sits. A part that no template places stays with the control.
abstract class TemplatedControl extends Control {
  TemplatedControl({
    DuiProperty<dynamic, ControlTemplate<dynamic>?>? templateProperty,
  }) : _templateProperty = templateProperty;

  final DuiProperty<dynamic, ControlTemplate<dynamic>?>? _templateProperty;
  final Map<String, UIElement> _parts = <String, UIElement>{};

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

  /// Registers a named part of the control.
  ///
  /// A template finds the part with [part] and places it where it belongs.
  /// The control keeps the part, so the content of the control survives the
  /// template: a part that no template places stays with the control.
  void registerPart(String name, UIElement element) {
    if (_parts.containsKey(name)) {
      throw StateError('The control already has a part named "$name".');
    }
    if (identical(element.logicalParent, this)) {
      throw StateError('The part "$name" already belongs to the control.');
    }
    _parts[name] = element;
    element.attachToParent(this);
  }

  /// The part with the given name, if the control has one.
  UIElement? part(String name) => _parts[name];

  /// All parts of the control.
  Iterable<UIElement> get templateParts => _parts.values;

  /// The parts that no template has placed.
  ///
  /// The control keeps these parts itself, measures them, arranges them and
  /// draws them, so the content of the control is never lost.
  Iterable<UIElement> get _hostedParts =>
      _parts.values.where((element) => identical(element.logicalParent, this));

  bool _isInvalidatingParts = false;

  @override
  void invalidateMeasure() {
    super.invalidateMeasure();
    _invalidateParts();
  }

  @override
  void invalidateArrange() {
    super.invalidateArrange();
    _invalidateParts();
  }

  /// Forgets the measure of the parts of the control.
  ///
  /// The parts show the content of the control, so they have to be measured
  /// again whenever the control is measured again.
  void _invalidateParts() {
    if (_isInvalidatingParts) return;
    _isInvalidatingParts = true;
    try {
      for (final element in _parts.values) {
        element.invalidateMeasure();
      }
    } finally {
      _isInvalidatingParts = false;
    }
  }

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
      _detachParts(previous);
      previous
        ..attachToParent(null)
        ..mountTo(null);
      _disposeTemplate(previous);
    }
    _templateRoot = null;
    onTemplateReplacing();
    // The parts leave the control, so the template is free to place them.
    for (final element in _parts.values) {
      if (identical(element.logicalParent, this)) {
        element.attachToParent(null);
      }
    }
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
    // The parts that no template has placed stay with the control.
    for (final element in _parts.values) {
      if (element.logicalParent == null) {
        element
          ..attachToParent(this)
          ..mountTo(window);
      }
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

  /// Takes the parts of the control out of the template that holds them.
  ///
  /// The parts belong to the control and outlive the template, so they are
  /// taken out before the template is disposed.
  void _detachParts(UIElement root) {
    for (final child in List<UIElement>.of(root.logicalChildren)) {
      if (_parts.containsValue(child)) {
        _detachPart(child);
        continue;
      }
      _detachParts(child);
    }
  }

  void _detachPart(UIElement element) {
    element.logicalParent?.removeChild(element);
    element.attachToParent(null);
  }

  void _disposeTemplate(UIElement root) {
    for (final child in root.logicalChildren) {
      _disposeTemplate(child);
    }
    root.dispose();
  }

  @override
  Iterable<UIElement> get logicalChildren {
    final children = <UIElement>[];
    final root = _templateRoot;
    if (root != null) children.add(root);
    children.addAll(_hostedParts);
    return children;
  }

  @override
  Size measureCore(Size availableSize) {
    final root = _templateRoot;
    if (root == null) return measureContentCore(availableSize);
    var size = root.measure(availableSize);
    for (final element in _hostedParts) {
      final partSize = element.measure(availableSize);
      if (partSize.width > size.width) {
        size = Size(partSize.width, size.height);
      }
      if (partSize.height > size.height) {
        size = Size(size.width, partSize.height);
      }
    }
    return size;
  }

  /// Measures the own content of the control, when it has no template.
  Size measureContentCore(Size availableSize) => Size.zero;

  /// Measures a part of the control.
  ///
  /// The control decides how large a part is. The base implementation asks
  /// for nothing, so a part that no control sizes stays empty.
  Size measurePart(UIElement part, Size availableSize) => Size.zero;

  @override
  void arrangeCore(Rect finalRect) {
    final root = _templateRoot;
    if (root == null) {
      arrangeContentCore(finalRect);
    } else {
      root.arrange(finalRect);
    }
    for (final element in _hostedParts) {
      element.arrange(partRect(element, finalRect));
    }
  }

  /// Arranges the own content of the control, when it has no template.
  void arrangeContentCore(Rect finalRect) {}

  /// Arranges a part of the control.
  void arrangePart(UIElement part, Rect finalRect) {}

  /// The area a part gets, when no template places it.
  ///
  /// The area is the rectangle of the control the part belongs to. The base
  /// implementation gives the part the whole control.
  Rect partRect(UIElement part, Rect contentRect) => contentRect;

  @override
  void renderCore(DrawingContext context) {
    final root = _templateRoot;
    if (root == null) {
      renderContentCore(context);
    } else {
      root.render(context);
    }
    for (final element in _hostedParts) {
      element.render(context);
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

  /// Draws a part of the control.
  void renderPart(UIElement part, DrawingContext context) {}

  @override
  UIElement? hitTestCore(Point position) {
    final root = _templateRoot;
    return root == null ? hitTestContentCore(position) : root.hitTest(position);
  }

  /// Looks for the own content of the control under the position, when it has
  /// no template.
  UIElement? hitTestContentCore(Point position) => null;

  /// Looks for the content of a part under the position.
  UIElement? hitTestPart(UIElement part, Point position) => null;
}
