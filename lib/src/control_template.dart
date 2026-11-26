import 'content_control.dart';
import 'focus_decoration.dart';
import 'ui_element.dart';

typedef ControlTemplateFactory<T extends Control> = UIElement Function(
  T control,
);

/// Creates one persistent visual subtree for a templated control.
final class ControlTemplate<T extends Control> {
  const ControlTemplate(
    this.factory, {
    this.focusRingShape = FocusRingShape.rectangle,
  });

  final ControlTemplateFactory<T> factory;
  final FocusRingShape focusRingShape;

  UIElement create(T control) => factory(control);
}

/// Presents the current content of a templated [ContentControl].
final class ContentPresenter extends ContentControl {
  ContentPresenter(this.host) {
    host.addContentChangedListener(_hostContentChanged);
    final current = host.content;
    current?.attachToParent(null);
    content = current;
  }

  final ContentControl host;
  bool _isAttached = true;

  @override
  bool get isFocusable => false;

  void detachFromHost() {
    if (!_isAttached) return;
    _isAttached = false;
    host.removeContentChangedListener(_hostContentChanged);
    content = null;
  }

  void _hostContentChanged(UIElement? oldContent, UIElement? newContent) {
    newContent?.attachToParent(null);
    content = newContent;
  }
}
