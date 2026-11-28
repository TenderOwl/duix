import 'control_template.dart';
import 'drawing.dart';
import 'geometry.dart';
import 'templated_control.dart';
import 'ui_element.dart';

typedef ContentChangedListener = void Function(
  UIElement? oldContent,
  UIElement? newContent,
);

/// A control that holds a single child.
///
/// The control can be restyled without touching the content: a template
/// replaces the visual subtree of the control and presents the content
/// through a [ContentPresenter].
abstract class ContentControl extends TemplatedControl {
  ContentControl({
    UIElement? content,
    super.templateProperty,
  }) : _content = content {
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
  Iterable<UIElement> get logicalChildren {
    final children = <UIElement>[...super.logicalChildren];
    if (!hasTemplate) {
      final current = _content;
      if (current != null) children.add(current);
    }
    return children;
  }

  /// The accessible name of a content control comes from its content.
  @override
  String get semanticsName => _content?.semanticsName ?? '';

  @override
  void removeChild(UIElement child) {
    if (identical(_content, child)) content = null;
  }

  @override
  void onMounted() {
    _content?.mountTo(window);
  }

  /// Takes the content back, when the old template is gone.
  ///
  /// The content belongs to the presenter of the old template, so the control
  /// takes it back before the new template presents it again.
  @override
  void onTemplateReplacing() {
    final current = _content;
    if (current == null) return;
    current
      ..attachToParent(this)
      ..mountTo(window);
  }

  @override
  Size measureContentCore(Size availableSize) =>
      _content?.measure(availableSize) ?? Size.zero;

  @override
  void arrangeContentCore(Rect finalRect) {
    _content?.arrange(finalRect);
  }

  @override
  void renderContentCore(DrawingContext context) {
    _content?.render(context);
  }

  @override
  UIElement? hitTestContentCore(Point position) => _content?.hitTest(position);
}
