import 'drawing.dart';
import 'geometry.dart';
import 'ui_element.dart';

typedef ContentChangedListener = void Function(
  UIElement? oldContent,
  UIElement? newContent,
);

abstract class ContentControl extends Control {
  ContentControl({UIElement? content}) : _content = content {
    _content?.attachToParent(this);
  }

  UIElement? _content;
  final _contentChangedListeners = <ContentChangedListener>[];

  UIElement? get content => _content;
  set content(UIElement? value) {
    if (identical(_content, value)) return;
    if (value?.logicalParent != null) {
      throw StateError('The content already belongs to another parent.');
    }
    final oldContent = _content;
    _content?.attachToParent(null);
    _content?.mountTo(null);
    _content = value;
    _content?.attachToParent(this);
    _content?.mountTo(window);
    for (final listener in List.of(_contentChangedListeners)) {
      listener(oldContent, value);
    }
    invalidateMeasure();
  }

  void addContentChangedListener(ContentChangedListener listener) {
    _contentChangedListeners.add(listener);
  }

  void removeContentChangedListener(ContentChangedListener listener) {
    _contentChangedListeners.remove(listener);
  }

  @override
  Iterable<UIElement> get logicalChildren =>
      _content == null ? const [] : [_content!];

  @override
  void removeChild(UIElement child) {
    if (identical(_content, child)) content = null;
  }

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
