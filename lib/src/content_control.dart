import 'drawing.dart';
import 'geometry.dart';
import 'ui_element.dart';

abstract class ContentControl extends Control {
  ContentControl({UIElement? content}) : _content = content {
    _content?.attachToParent(this);
  }

  UIElement? _content;

  UIElement? get content => _content;
  set content(UIElement? value) {
    if (identical(_content, value)) return;
    if (value?.logicalParent != null) {
      throw StateError('The content already belongs to another parent.');
    }
    _content?.attachToParent(null);
    _content?.mountTo(null);
    _content = value;
    _content?.attachToParent(this);
    _content?.mountTo(window);
    invalidateMeasure();
  }

  @override
  Iterable<UIElement> get logicalChildren =>
      _content == null ? const [] : [_content!];

  @override
  void onMounted() {
    _content?.mountTo(window);
  }

  @override
  Size measureCore(Size availableSize) =>
      _content?.measure(availableSize) ?? Size.zero;

  @override
  void arrangeCore(Rect finalRect) {
    _content?.arrange(finalRect);
  }

  @override
  void renderCore(DrawingContext context) {
    _content?.render(context);
  }

  @override
  UIElement? hitTestCore(Point position) => _content?.hitTest(position);
}
