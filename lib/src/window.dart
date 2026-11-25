import 'dart:async';

import 'drawing.dart';
import 'events.dart';
import 'geometry.dart';
import 'headless_text_layout.dart';
import 'observable.dart';
import 'text_layout.dart';
import 'ui_element.dart';

abstract interface class NativeHost {
  Future<void> showWindow(Window window);
  Future<void> closeWindow(Window window);
}

abstract interface class TextInputHandler {
  void startTextInput(Window window);
  void stopTextInput(Window window);
  void setTextInputArea(Window window, Rect area, double cursorX);
}

abstract interface class ClipboardHandler {
  String? readClipboardText();
  bool writeClipboardText(String text);
}

final class Application {
  Application({required this.host});

  final NativeHost host;
  bool _running = false;

  Future<void> run(Window mainWindow) async {
    if (_running) throw StateError('The application is already running.');
    _running = true;
    await host.showWindow(mainWindow);
  }

  Future<void> shutdown(Window window) async {
    await host.closeWindow(window);
    _running = false;
  }
}

final class Window extends ObservableObject implements WindowHost {
  Window({
    String title = '',
    double width = 800,
    double height = 600,
    Color background = Color.white,
    TextLayoutFactory textLayoutFactory = const HeadlessTextLayoutFactory(),
    UIElement? content,
  })  : _title = title,
        _logicalSize = Size(width, height),
        _background = background,
        _textLayoutFactory = textLayoutFactory {
    this.content = content;
  }

  String _title;
  Size _logicalSize;
  Color _background;
  TextLayoutFactory _textLayoutFactory;
  double _devicePixelRatio = 1;
  UIElement? _content;
  Control? _focused;
  TextInputHandler? textInputHandler;
  ClipboardHandler? clipboardHandler;
  bool _frameScheduled = false;
  bool _isVisible = false;

  String get title => _title;
  set title(String value) {
    if (_title == value) return;
    final oldValue = _title;
    _title = value;
    notifyPropertyChanged('title', oldValue, value);
  }

  Color get background => _background;
  set background(Color value) {
    if (_background == value) return;
    final oldValue = _background;
    _background = value;
    requestFrame();
    notifyPropertyChanged('background', oldValue, value);
  }

  Size get logicalSize => _logicalSize;
  double get devicePixelRatio => _devicePixelRatio;
  bool get isVisible => _isVisible;
  Control? get focusedElement => _focused;
  bool get frameScheduled => _frameScheduled;

  @override
  void startTextInput(Control control) {
    if (_isVisible && identical(_focused, control)) {
      textInputHandler?.startTextInput(this);
    }
  }

  @override
  void stopTextInput(Control control) {
    textInputHandler?.stopTextInput(this);
  }

  @override
  void updateTextInputArea(Control control, Rect area, double cursorX) {
    if (_isVisible && identical(_focused, control)) {
      textInputHandler?.setTextInputArea(this, area, cursorX);
    }
  }

  @override
  String? readClipboardText() => clipboardHandler?.readClipboardText();

  @override
  bool writeClipboardText(String text) =>
      clipboardHandler?.writeClipboardText(text) ?? false;

  @override
  double get displayScale => _devicePixelRatio;

  @override
  TextLayoutFactory get textLayoutFactory => _textLayoutFactory;
  set textLayoutFactory(TextLayoutFactory value) {
    if (identical(_textLayoutFactory, value)) return;
    _textLayoutFactory = value;
    _content?.invalidateMeasure();
    requestFrame();
  }

  void updateDevicePixelRatio(double value) {
    if (value <= 0 || value == _devicePixelRatio) return;
    final oldValue = _devicePixelRatio;
    _devicePixelRatio = value;
    _content?.invalidateMeasure();
    requestFrame();
    notifyPropertyChanged('devicePixelRatio', oldValue, value);
  }

  UIElement? get content => _content;
  set content(UIElement? value) {
    if (identical(_content, value)) return;
    _content?.attachToParent(null);
    _content?.mountTo(null);
    _content = value;
    _content?.attachToParent(null);
    _content?.mountTo(this);
    requestFrame();
  }

  Future<void> show() async {
    _isVisible = true;
    final focused = _focused;
    if (focused != null) {
      startTextInput(focused);
      focused.onTextInputActivated();
    }
    requestFrame();
  }

  void close() {
    _isVisible = false;
    _content?.mountTo(null);
  }

  void resize(double width, double height) {
    _logicalSize = Size(width, height);
    _content?.invalidateMeasure();
    requestFrame();
  }

  @override
  void requestFrame() {
    _frameScheduled = true;
  }

  @override
  bool requestFocus(Control control) {
    if (!control.isFocusable || !control.isEnabled) return false;
    _focused?.updateFocus(false);
    _focused = control;
    control.updateFocus(true);
    return true;
  }

  void dispatchPointerDown(Point position) {
    final root = _content;
    if (root == null) return;
    root.measure(logicalSize);
    root.arrange(Rect.fromLTWH(0, 0, logicalSize.width, logicalSize.height));
    final target = root.hitTest(position);
    if (target == null) return;
    final preview = PointerEventArgs(pointerId: 1, position: position)
      ..originalSource = target;
    target.raiseEvent(UIElement.previewPointerDown, preview);
    if (preview.handled) return;
    target.raiseEvent(
      UIElement.pointerDown,
      PointerEventArgs(pointerId: 1, position: position)
        ..originalSource = target,
    );
  }

  void dispatchPointerUp(Point position) {
    final target = _content?.hitTest(position);
    target?.raiseEvent(
      UIElement.pointerUp,
      PointerEventArgs(pointerId: 1, position: position)
        ..originalSource = target,
    );
  }

  void dispatchTextInput(String text) {
    _focused?.raiseEvent(UIElement.textInput, TextInputEventArgs(text));
  }

  void dispatchTextEditing(
    String text, {
    int compositionStart = -1,
    int compositionLength = -1,
  }) {
    _focused?.raiseEvent(
      UIElement.textEditing,
      TextEditingEventArgs(
        text,
        compositionStart: compositionStart,
        compositionLength: compositionLength,
      ),
    );
  }

  void dispatchKeyDown(
    String key, {
    bool shiftPressed = false,
    bool controlPressed = false,
    bool metaPressed = false,
  }) {
    _focused?.raiseEvent(
      UIElement.keyDown,
      KeyEventArgs(
        key,
        shiftPressed: shiftPressed,
        controlPressed: controlPressed,
        metaPressed: metaPressed,
      ),
    );
  }

  void renderFrame(DrawingContext context) {
    final root = _content;
    if (root == null || !_isVisible) {
      _frameScheduled = false;
      return;
    }
    root.measure(logicalSize);
    root.arrange(Rect.fromLTWH(0, 0, logicalSize.width, logicalSize.height));
    root.render(context);
    _frameScheduled = false;
  }
}
