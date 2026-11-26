import 'colors.dart';
import 'drawing.dart';
import 'events.dart';
import 'focus_decoration.dart';
import 'geometry.dart';
import 'headless_text_layout.dart';
import 'properties.dart';
import 'semantics.dart';
import 'text_buffer.dart';
import 'text_layout.dart';
import 'ui_element.dart';

final class TextBox extends Control {
  TextBox({String text = '', double fontSize = 14})
      : buffer = TextBuffer(text: text) {
    setValue(textProperty, text);
    setValue(fontSizeProperty, fontSize);
    buffer.addPropertyListener((event) {
      if (event.property == TextBuffer.textProperty &&
          this.text != event.newValue) {
        this.text = event.newValue as String;
      }
      if (event.property == TextBuffer.selectionProperty) {
        invalidatePaint();
      }
      _ensureCaretVisible();
      _syncTextInputArea();
    });
    addHandler(UIElement.pointerDown, _pointerDown);
    addHandler(UIElement.pointerMove, _pointerMove);
    addHandler(UIElement.pointerUp, _pointerUp);
    addHandler(UIElement.textInput, _textInput);
    addHandler(UIElement.textEditing, _textEditing);
    addHandler(UIElement.keyDown, _keyDown);
  }

  static const textProperty = DuiProperty<TextBox, String>(
    name: 'text',
    defaultValue: '',
    affectsMeasure: true,
    affectsPaint: true,
  );
  static const fontSizeProperty = DuiProperty<TextBox, double>(
    name: 'fontSize',
    defaultValue: 14,
    affectsMeasure: true,
    affectsPaint: true,
  );

  static const _headlessFactory = HeadlessTextLayoutFactory();

  /// Horizontal padding of the content area, mirrored by [renderCore].
  static const double _contentPaddingHorizontal = 16;

  /// Vertical padding of the content area, mirrored by [renderCore].
  static const double _contentPaddingVertical = 8;

  /// Smallest width the control reports so an empty field stays visible.
  static const double _minimumWidth = 80;

  /// Smallest height the control reports for a single line of text.
  static const double _minimumHeight = 30;

  final TextBuffer buffer;
  WindowHost? _mountedHost;
  String _compositionText = '';
  TextSelection? _compositionSelection;
  final _CachedTextLayout _measureLayout = _CachedTextLayout();
  final _CachedTextLayout _renderLayout = _CachedTextLayout();
  double _horizontalScrollOffset = 0;
  bool _isSelecting = false;

  String get text => getValue(textProperty);
  set text(String value) => setValue(textProperty, value);

  double get fontSize => getValue(fontSizeProperty);
  set fontSize(double value) => setValue(fontSizeProperty, value);

  TextSelection get selection => buffer.selection;
  set selection(TextSelection value) => buffer.selection = value;

  int get caretOffset => buffer.caretOffset;
  String get selectedText => buffer.selectedText;
  String get compositionText => _compositionText;
  TextSelection? get compositionSelection => _compositionSelection;
  bool get hasComposition => _compositionText.isNotEmpty;

  void insertText(String value) {
    _clearComposition();
    buffer.insertText(value);
  }

  void deleteBackward() => buffer.deleteBackward();
  void deleteForward() => buffer.deleteForward();
  void moveCaret(int offset, {bool extendSelection = false}) =>
      buffer.moveCaret(offset, extendSelection: extendSelection);
  void selectAll() => buffer.selectAll();

  bool copySelection() {
    if (selection.isCollapsed) return false;
    return _mountedHost?.writeClipboardText(selectedText) ?? false;
  }

  bool cutSelection() {
    if (selection.isCollapsed || !copySelection()) return false;
    buffer.replaceSelection('');
    return true;
  }

  bool paste() {
    final value = _mountedHost?.readClipboardText();
    if (value == null || value.isEmpty) return false;
    buffer.replaceSelection(value);
    return true;
  }

  void _pointerDown(Object sender, PointerEventArgs args) {
    if (!isEnabled || args.button != PointerButton.primary) return;
    _clearComposition();
    focus();
    buffer.moveCaret(_hitTestOffset(args.position));
    _isSelecting = true;
    capturePointer();
    args.handled = true;
  }

  void _pointerMove(Object sender, PointerEventArgs args) {
    if (!_isSelecting) return;
    buffer.moveCaret(
      _hitTestOffset(args.position),
      extendSelection: true,
    );
    args.handled = true;
  }

  void _pointerUp(Object sender, PointerEventArgs args) {
    if (!_isSelecting || args.button != PointerButton.primary) return;
    buffer.moveCaret(
      _hitTestOffset(args.position),
      extendSelection: true,
    );
    _cancelPointerSelection();
    args.handled = true;
  }

  int _hitTestOffset(Point position) {
    final local = Point(
      position.x - bounds.left - 8 + _horizontalScrollOffset,
      position.y - bounds.top - 7,
    );
    final layout = _layoutForRender(text);
    final offset = layout.hitTest(local).offset.clamp(0, text.length);
    if (offset > 0 &&
        offset < text.length &&
        _isHighSurrogate(text.codeUnitAt(offset - 1)) &&
        _isLowSurrogate(text.codeUnitAt(offset))) {
      final before = offset - 1;
      final after = offset + 1;
      final midpoint =
          (layout.caretRect(before).left + layout.caretRect(after).left) / 2;
      return local.x < midpoint ? before : after;
    }
    return offset;
  }

  static bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  static bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

  void _cancelPointerSelection() {
    if (!_isSelecting) return;
    _isSelecting = false;
    _mountedHost?.releasePointer(this);
  }

  void _textInput(Object sender, TextInputEventArgs args) {
    insertText(args.text);
    args.handled = true;
  }

  void _textEditing(Object sender, TextEditingEventArgs args) {
    _compositionText = args.text;
    if (args.compositionStart >= 0 && args.compositionLength >= 0) {
      final start = args.compositionStart.clamp(0, args.text.length);
      final end = (args.compositionStart + args.compositionLength)
          .clamp(start, args.text.length);
      _compositionSelection =
          TextSelection(baseOffset: start, extentOffset: end);
    } else {
      _compositionSelection = null;
    }
    invalidatePaint();
    args.handled = true;
  }

  void _clearComposition() {
    if (_compositionText.isEmpty && _compositionSelection == null) return;
    _compositionText = '';
    _compositionSelection = null;
    invalidatePaint();
  }

  void _keyDown(Object sender, KeyEventArgs args) {
    final shortcut = args.primaryShortcutPressed;
    switch (args.key) {
      case 'left':
        buffer.moveCaretLeft(
          byWord: shortcut,
          extendSelection: args.shiftPressed,
        );
      case 'right':
        buffer.moveCaretRight(
          byWord: shortcut,
          extendSelection: args.shiftPressed,
        );
      case 'home':
        buffer.moveCaretToStart(extendSelection: args.shiftPressed);
      case 'end':
        buffer.moveCaretToEnd(extendSelection: args.shiftPressed);
      case 'backspace':
        buffer.deleteBackward();
      case 'delete':
        buffer.deleteForward();
      case 'a' when shortcut:
        selectAll();
      case 'c' when shortcut:
        copySelection();
      case 'x' when shortcut:
        cutSelection();
      case 'v' when shortcut:
        paste();
      default:
        return;
    }
    _clearComposition();
    args.handled = true;
  }

  @override
  void onMounted() {
    _mountedHost = window;
    invalidateMeasure();
    if (isFocused) window?.startTextInput(this);
  }

  @override
  void onUnmounted() {
    _cancelPointerSelection();
    _clearComposition();
    _measureLayout.dispose();
    _renderLayout.dispose();
    invalidateMeasure();
    if (isFocused) _mountedHost?.stopTextInput(this);
    _mountedHost = null;
  }

  @override
  SemanticsRole get semanticsRole => SemanticsRole.textBox;

  @override
  String get semanticsValue => text;

  @override
  SemanticsState get semanticsState => SemanticsState(
        focused: isFocused,
        disabled: !isEnabled,
        editable: isEnabled,
      );

  @override
  (int, int)? get semanticsSelection =>
      (buffer.selection.start, buffer.selection.end);

  @override
  void onDisposed() {
    _measureLayout.dispose();
    _renderLayout.dispose();
  }

  @override
  void onFocusChanged(bool value) {
    if (value) {
      window?.startTextInput(this);
      _syncTextInputArea();
    } else {
      _cancelPointerSelection();
      _clearComposition();
      _mountedHost?.stopTextInput(this);
    }
  }

  @override
  void onTextInputActivated() => _syncTextInputArea();

  @override
  void arrangeCore(Rect finalRect) {
    _ensureCaretVisible();
    _syncTextInputArea();
  }

  void _ensureCaretVisible([TextLayout? layout]) {
    final viewport = (bounds.width - 16).clamp(0.0, double.infinity);
    if (viewport <= 0) {
      _horizontalScrollOffset = 0;
      return;
    }

    final displayText = hasComposition
        ? text.replaceRange(selection.start, selection.end, compositionText)
        : text;
    var targetOffset = caretOffset;
    if (hasComposition) {
      final active = compositionSelection;
      targetOffset = selection.start +
          (active == null ? compositionText.length : active.end);
    }
    final resolved = layout ?? _layoutForRender(displayText);
    final caretX = resolved.caretRect(targetOffset).left;
    var nextOffset = _horizontalScrollOffset;
    if (caretX < nextOffset) {
      nextOffset = caretX;
    } else if (caretX > nextOffset + viewport - 1) {
      nextOffset = caretX - viewport + 1;
    }
    final contentWidth =
        resolved.width > caretX ? resolved.width : caretX.toDouble();
    final maximumOffset =
        contentWidth > viewport ? contentWidth - viewport + 1 : 0.0;
    _horizontalScrollOffset = nextOffset.clamp(0.0, maximumOffset);
  }

  void _syncTextInputArea() {
    _ensureCaretVisible();
    final host = _mountedHost;
    if (host == null || !isFocused) return;
    final width = (bounds.width - 16).clamp(1.0, double.infinity);
    final height = (bounds.height - 14).clamp(1.0, double.infinity);
    final layout = _layoutForRender(text);
    final cursorX =
        layout.caretRect(caretOffset).left - _horizontalScrollOffset;
    host.updateTextInputArea(
      this,
      Rect.fromLTWH(bounds.left + 8, bounds.top + 7, width, height),
      cursorX,
    );
  }

  @override
  void onDuiPropertyChanged<T>(
    DuiProperty<dynamic, T> property,
    T oldValue,
    T newValue,
  ) {
    if (property == textProperty && buffer.text != newValue) {
      _clearComposition();
      buffer.text = newValue as String;
    }
    super.onDuiPropertyChanged(property, oldValue, newValue);
  }

  @override
  Size measureCore(Size availableSize) {
    final layout = _layoutForMeasure();
    var width = layout.width + _contentPaddingHorizontal;
    var height = layout.height + _contentPaddingVertical;
    if (width < _minimumWidth) width = _minimumWidth;
    if (height < _minimumHeight) height = _minimumHeight;
    if (availableSize.width.isFinite && width > availableSize.width) {
      width = availableSize.width;
    }
    return Size(width, height);
  }

  @override
  void renderCore(DrawingContext context) {
    context.drawRect(bounds, const Paint(Colors.white));
    if (isFocused) drawFocusRing(context, bounds);
    final contentBounds = Rect.fromLTWH(
      bounds.left + 8,
      bounds.top + 4,
      (bounds.width - 16).clamp(0, double.infinity),
      (bounds.height - 8).clamp(0, double.infinity),
    );
    final compositionBase = selection.start;
    final displayText = hasComposition
        ? text.replaceRange(selection.start, selection.end, compositionText)
        : text;
    final layout = _layoutForRender(displayText);
    _ensureCaretVisible(layout);
    final origin = Point(
      bounds.left + 8 - _horizontalScrollOffset,
      bounds.top + 7,
    );

    context.pushClipRect(contentBounds);
    try {
      if (!hasComposition && !selection.isCollapsed) {
        for (final rect in layout.selectionRects(
          selection.start,
          selection.end,
        )) {
          context.drawRect(
            Rect.fromLTWH(
              origin.x + rect.left,
              origin.y + rect.top,
              rect.width,
              rect.height,
            ),
            const Paint(Color(0x5580CFFF)),
          );
        }
      }

      if (hasComposition) {
        final active = compositionSelection ??
            TextSelection(baseOffset: 0, extentOffset: compositionText.length);
        for (final rect in layout.selectionRects(
          compositionBase + active.start,
          compositionBase + active.end,
        )) {
          context.drawRect(
            Rect.fromLTWH(
              origin.x + rect.left,
              origin.y + rect.top,
              rect.width,
              rect.height,
            ),
            const Paint(Color(0x5599CCFF)),
          );
        }
        for (final rect in layout.selectionRects(
          compositionBase,
          compositionBase + compositionText.length,
        )) {
          context.drawRect(
            Rect.fromLTWH(
              origin.x + rect.left,
              origin.y + rect.bottom - 1,
              rect.width,
              2,
            ),
            const Paint(Color(0xFF336699)),
          );
        }
      }
      layout.draw(context, origin);

      if (isFocused && !hasComposition && selection.isCollapsed) {
        final caret = layout.caretRect(caretOffset);
        context.drawRect(
          Rect.fromLTWH(
            origin.x + caret.left,
            origin.y + caret.top,
            1,
            caret.height > 0 ? caret.height : layout.height,
          ),
          const Paint(Color(0xFF202020)),
        );
      }
    } finally {
      context.popClip();
    }
  }

  TextLayout _layoutForMeasure() {
    final host = window;
    final factory = host?.textLayoutFactory ?? _headlessFactory;
    final options = TextLayoutOptions(
      text: text,
      fontSize: fontSize,
      maxWidth: double.infinity,
      scale: host?.displayScale ?? 1,
    );
    if (_renderLayout.matches(options, factory)) {
      _measureLayout.dispose();
      return _renderLayout.current!;
    }
    return _measureLayout.resolve(options, factory);
  }

  TextLayout _layoutForRender(String displayText) {
    final host = window;
    final factory = host?.textLayoutFactory ?? _headlessFactory;
    final options = TextLayoutOptions(
      text: displayText,
      fontSize: fontSize,
      maxWidth: double.infinity,
      scale: host?.displayScale ?? 1,
    );
    if (_measureLayout.matches(options, factory)) {
      _renderLayout.dispose();
      return _measureLayout.current!;
    }
    return _renderLayout.resolve(options, factory);
  }
}

/// A text layout together with the options and factory that produced it.
///
/// The layout is reused while the options stay equal and released as soon as
/// the text, font size, scale or backend changes.
final class _CachedTextLayout {
  TextLayout? _layout;
  TextLayoutOptions? _options;
  TextLayoutFactory? _factory;

  TextLayout? get current => _layout;

  bool matches(TextLayoutOptions options, TextLayoutFactory factory) {
    final layout = _layout;
    return layout != null &&
        !layout.isDisposed &&
        identical(_factory, factory) &&
        _options == options;
  }

  TextLayout resolve(TextLayoutOptions options, TextLayoutFactory factory) {
    if (matches(options, factory)) return _layout!;
    dispose();
    final created = factory.create(options);
    _layout = created;
    _options = options;
    _factory = factory;
    return created;
  }

  void dispose() {
    _layout?.dispose();
    _layout = null;
    _options = null;
    _factory = null;
  }
}
