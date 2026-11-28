import 'drawing.dart';
import 'geometry.dart';
import 'templated_control.dart';
import 'ui_element.dart';

/// A part of a control that a template can place.
///
/// A part carries what the control cannot draw on its own: the text of a text
/// box, the scrolled content of a scrollable area. The control owns the part
/// and draws the content through it, so a template never replaces the content
/// of a control: it only decides where the part sits.
///
/// A part that no template places stays with the control, which draws it in
/// the area the control reserves for it.
final class TemplatePart extends UIElement {
  TemplatePart(this.name, this.owner);

  /// The name a template uses to find the part.
  final String name;

  /// The control that owns the part.
  final TemplatedControl owner;

  @override
  Size measureCore(Size availableSize) =>
      owner.measurePart(this, availableSize);

  @override
  void arrangeCore(Rect finalRect) => owner.arrangePart(this, finalRect);

  @override
  void renderCore(DrawingContext context) => owner.renderPart(this, context);

  @override
  UIElement? hitTestCore(Point position) => owner.hitTestPart(this, position);
}
