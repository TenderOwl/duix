import 'dart:async';
import 'dart:typed_data';

import 'clipboard.dart';
import 'drawing.dart';
import 'events.dart';
import 'file_dialog.dart';
import 'focus_manager.dart';
import 'frame_scheduler.dart';
import 'geometry.dart';
import 'headless_text_layout.dart';
import 'observable.dart';
import 'text_layout.dart';
import 'ui_element.dart';

export 'clipboard.dart' show ClipboardHandler, ClipboardMimeTypes;
export 'file_dialog.dart' show FileDialogHandler;

abstract interface class NativeHost {
  Future<void> showWindow(Window window);
  Future<void> closeWindow(Window window);
}

abstract interface class TextInputHandler {
  void startTextInput(Window window);
  void stopTextInput(Window window);
  void setTextInputArea(Window window, Rect area, double cursorX);
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
  late final FocusManager focusManager = FocusManager(this);
  Control? _pointerCapture;
  Set<Control> _hoveredControls = <Control>{};
  TextInputHandler? textInputHandler;
  ClipboardHandler? clipboardHandler;
  FileDialogHandler? fileDialogHandler;
  final _scheduler = FrameScheduler();
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
  @override
  Control? get focusedElement => focusManager.focusedElement;
  bool get frameScheduled => _scheduler.frameScheduled;
  int get scheduledFrameCount => _scheduler.scheduledFrameCount;
  int get layoutPassCount => _scheduler.layoutPassCount;
  int get paintPassCount => _scheduler.paintPassCount;

  void setFrameRequestHandler(void Function()? handler) {
    _scheduler.setFrameRequestHandler(handler);
  }

  @override
  void startTextInput(Control control) {
    if (_isVisible && identical(focusManager.focusedElement, control)) {
      textInputHandler?.startTextInput(this);
    }
  }

  @override
  void stopTextInput(Control control) {
    textInputHandler?.stopTextInput(this);
  }

  @override
  void updateTextInputArea(Control control, Rect area, double cursorX) {
    if (_isVisible && identical(focusManager.focusedElement, control)) {
      textInputHandler?.setTextInputArea(this, area, cursorX);
    }
  }

  @override
  String? readClipboardText() => clipboardHandler?.readClipboardText();

  @override
  bool writeClipboardText(String text) =>
      clipboardHandler?.writeClipboardText(text) ?? false;

  @override
  bool hasClipboardData(String mimeType) =>
      clipboardHandler?.hasClipboardData(mimeType) ?? false;

  @override
  Uint8List? readClipboardData(String mimeType) =>
      clipboardHandler?.readClipboardData(mimeType);

  @override
  bool writeClipboardData(Map<String, List<int>> formats) =>
      clipboardHandler?.writeClipboardData(formats) ?? false;

  @override
  List<String> readClipboardMimeTypes() =>
      clipboardHandler?.readClipboardMimeTypes() ?? const <String>[];

  @override
  bool clearClipboard() => clipboardHandler?.clearClipboard() ?? false;

  @override
  Future<String?> showOpenFileDialog({String? title}) =>
      fileDialogHandler?.showOpenFileDialog(this, title: title) ??
      Future<String?>.value();

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
  @override
  UIElement? get rootElement => _content;
  set content(UIElement? value) {
    if (identical(_content, value)) return;
    _clearHover();
    _content?.attachToParent(null);
    _content?.mountTo(null);
    _content = value;
    _content?.attachToParent(null);
    _content?.mountTo(this);
    requestFrame();
  }

  Future<void> show() async {
    _isVisible = true;
    final focused = focusManager.focusedElement;
    if (focused != null) {
      startTextInput(focused);
      focused.onTextInputActivated();
    }
    requestFrame();
  }

  void close() {
    _isVisible = false;
    _clearHover();
    _content?.mountTo(null);
  }

  void resize(double width, double height) {
    final size = Size(width, height);
    if (_logicalSize == size) return;
    _logicalSize = size;
    _content?.invalidateMeasure();
    requestFrame();
  }

  @override
  void requestFrame() => _scheduler.requestFrame();

  @override
  bool requestFocus(Control control) => focusManager.requestFocus(control);

  @override
  void validateFocus() => focusManager.validate();

  @override
  bool capturePointer(Control control) {
    if (!control.isMounted || !identical(control.window, this)) return false;
    _pointerCapture = control;
    return true;
  }

  @override
  void releasePointer(Control control) {
    if (identical(_pointerCapture, control)) _pointerCapture = null;
  }

  @override
  bool hasPointerCapture(Control control) =>
      identical(_pointerCapture, control);

  void dispatchPointerDown(
    Point position, {
    PointerButton button = PointerButton.primary,
  }) {
    updateLayout();
    final target = _content?.hitTest(position);
    if (target == null) return;
    final preview = PointerEventArgs(
      pointerId: 1,
      position: position,
      button: button,
    )..originalSource = target;
    target.raiseEvent(UIElement.previewPointerDown, preview);
    if (preview.handled) return;
    target.raiseEvent(
      UIElement.pointerDown,
      PointerEventArgs(pointerId: 1, position: position, button: button)
        ..originalSource = target,
    );
  }

  void dispatchPointerMove(Point position) {
    final target = _pointerCapture ?? _content?.hitTest(position);
    _updateHover(target);
    target?.raiseEvent(
      UIElement.pointerMove,
      PointerEventArgs(pointerId: 1, position: position)
        ..originalSource = target,
    );
  }

  void _updateHover(UIElement? target) {
    final next = <Control>{};
    UIElement? current = target;
    while (current != null) {
      if (current is Control) next.add(current);
      current = current.logicalParent;
    }
    for (final control in _hoveredControls.difference(next)) {
      control.updatePointerOver(false);
    }
    for (final control in next.difference(_hoveredControls)) {
      control.updatePointerOver(true);
    }
    _hoveredControls = next;
  }

  void _clearHover() {
    for (final control in _hoveredControls) {
      control.updatePointerOver(false);
    }
    _hoveredControls = <Control>{};
  }

  void dispatchPointerUp(
    Point position, {
    PointerButton button = PointerButton.primary,
  }) {
    final target = _pointerCapture ?? _content?.hitTest(position);
    target?.raiseEvent(
      UIElement.pointerUp,
      PointerEventArgs(pointerId: 1, position: position, button: button)
        ..originalSource = target,
    );
    if (button == PointerButton.primary) _pointerCapture = null;
  }

  void dispatchMouseWheel(
    Point position, {
    double deltaX = 0,
    double deltaY = 0,
  }) {
    if (!deltaX.isFinite || !deltaY.isFinite) {
      throw ArgumentError('Mouse wheel deltas must be finite.');
    }
    updateLayout();
    final target = _content?.hitTest(position);
    target?.raiseEvent(
      UIElement.mouseWheel,
      MouseWheelEventArgs(
        position: position,
        deltaX: deltaX,
        deltaY: deltaY,
      )..originalSource = target,
    );
  }

  void dispatchTextInput(String text) {
    focusManager.focusedElement
        ?.raiseEvent(UIElement.textInput, TextInputEventArgs(text));
  }

  void dispatchTextEditing(
    String text, {
    int compositionStart = -1,
    int compositionLength = -1,
  }) {
    focusManager.focusedElement?.raiseEvent(
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
    int physicalKeyCode = 0,
    int logicalKeyCode = 0,
  }) {
    final args = KeyEventArgs(
      key,
      shiftPressed: shiftPressed,
      controlPressed: controlPressed,
      metaPressed: metaPressed,
      physicalKeyCode: physicalKeyCode,
      logicalKeyCode: logicalKeyCode,
    );
    focusManager.focusedElement?.raiseEvent(UIElement.keyDown, args);
    if (!args.handled && key == 'tab' && !controlPressed && !metaPressed) {
      focusManager.moveFocus(reverse: shiftPressed);
    }
  }

  void updateLayout() {
    final root = _content;
    if (root == null) return;
    _scheduler.layout(() {
      root.measure(logicalSize);
      root.arrange(Rect.fromLTWH(0, 0, logicalSize.width, logicalSize.height));
    });
  }

  void renderFrame(DrawingContext context) {
    if (!_scheduler.tryBeginFrame()) return;
    final root = _content;
    if (root == null || !_isVisible) return;
    updateLayout();
    _scheduler.paint(() => root.render(context));
  }
}
