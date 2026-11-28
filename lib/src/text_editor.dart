import 'colors.dart';
import 'drawing.dart';
import 'events.dart';
import 'geometry.dart';
import 'headless_text_layout.dart';
import 'observable.dart';
import 'properties.dart';
import 'semantics.dart';
import 'template_part.dart';
import 'templated_control.dart';
import 'text_buffer.dart';
import 'text_layout.dart';
import 'ui_element.dart';

/// The editing core that the text controls share.
///
/// [TextBox] and [TextArea] edit the text the same way: the same buffer, the
/// same commands, the same composition and the same rules of the selection.
/// They differ in the axis of the text and in the way the content is scrolled,
/// and the subclasses answer that with the hooks of this class.
abstract class TextEditor extends TemplatedControl {
  TextEditor({
    required DuiProperty<dynamic, String> textProperty,
    required DuiProperty<dynamic, double> fontSizeProperty,
    required super.templateProperty,
    String text = '',
    double fontSize = 14,
  })  : buffer = TextBuffer(text: text),
        _textProperty = textProperty,
        _fontSizeProperty = fontSizeProperty {
    _textPart = TemplatePart('text', this);
    registerPart('text', _textPart);
    setValue(_textProperty, text);
    setValue(_fontSizeProperty, fontSize);
    buffer.addPropertyListener(_bufferChanged);
    addHandler(UIElement.pointerDown, _pointerDown);
    addHandler(UIElement.pointerMove, _pointerMove);
    addHandler(UIElement.pointerUp, _pointerUp);
    addHandler(UIElement.textInput, _textInput);
    addHandler(UIElement.textEditing, _textEditing);
    addHandler(UIElement.keyDown, _keyDown);
  }

  /// The property that holds the text of the control.
  final DuiProperty<dynamic, String> _textProperty;

  /// The property that holds the size of the font of the control.
  final DuiProperty<dynamic, double> _fontSizeProperty;

  /// The text and the selection of the control.
  final TextBuffer buffer;

  late final TemplatePart _textPart;
  WindowHost? _mountedHost;
  String _compositionText = '';
  TextSelection? _compositionSelection;
  final CachedTextLayout _measureLayout = CachedTextLayout();
  final CachedTextLayout _renderLayout = CachedTextLayout();
  bool _isSelecting = false;

  /// The text of the control.
  String get text => getValue(_textProperty);
  set text(String value) => setValue(_textProperty, value);

  /// The size of the font of the control.
  double get fontSize => getValue(_fontSizeProperty);
  set fontSize(double value) => setValue(_fontSizeProperty, value);

  /// The selected part of the text.
  TextSelection get selection => buffer.selection;
  set selection(TextSelection value) => buffer.selection = value;

  /// The offset of the caret in the text.
  int get caretOffset => buffer.caretOffset;

  /// The selected text.
  String get selectedText => buffer.selectedText;

  /// The text that the input method composes right now.
  String get compositionText => _compositionText;

  /// The range that the input method composes right now.
  TextSelection? get compositionSelection => _compositionSelection;

  /// Whether the input method composes a text right now.
  bool get hasComposition => _compositionText.isNotEmpty;

  /// The part of the control that holds the text.
  UIElement get textPart => _textPart;

  /// The padding around the text inside the field.
  static const EdgeInsets _contentPadding =
      EdgeInsets.symmetric(horizontal: 8, vertical: 4);

  /// Horizontal padding of the content area, mirrored by [renderPart].
  ///
  /// The padding is added to the size of the text, so a control that lays the
  /// text out itself knows how much space the padding takes.
  static const double contentPaddingHorizontal = 16;

  /// Vertical padding of the content area, mirrored by [renderPart].
  static const double contentPaddingVertical = 8;

  /// The distance between the top of the text area and the line of text.
  static const double _textTopOffset = 3;

  static const _headlessFactory = HeadlessTextLayoutFactory();

  /// The width the text is laid out in.
  ///
  /// A single line field lays the text out without a width limit and scrolls
  /// it horizontally, a multiline field wraps the text into the width of the
  /// area.
  double layoutWidthFor(Size availableSize);

  /// The horizontal offset of the text inside the area.
  double get horizontalScrollOffset => 0;

  /// The vertical offset of the text inside the area.
  double get verticalScrollOffset => 0;

  /// Whether the scroll of the content follows the caret.
  ///
  /// A single line field scrolls only to show the caret. A multiline field has
  /// a scroll of its own, and the user can scroll the text away from the
  /// caret.
  bool get scrollFollowsCaret => true;

  /// Keeps the caret inside the visible part of the text.
  void ensureCaretVisible([TextLayout? layout]);

  /// The height of the area that the input method shows its window near.
  double inputAreaHeight(Rect area, TextLayout layout) => area.height - 6;

  /// Moves the caret to the start of the line.
  void moveCaretToLineStart({bool extendSelection = false}) =>
      buffer.moveCaretToStart(extendSelection: extendSelection);

  /// Moves the caret to the end of the line.
  void moveCaretToLineEnd({bool extendSelection = false}) =>
      buffer.moveCaretToEnd(extendSelection: extendSelection);

  /// Handles the keys that the common editing keys do not cover.
  ///
  /// The control that returns true has handled the key.
  bool handleExtraKey(KeyEventArgs args) => false;

  /// The point of the screen where the text starts.
  ///
  /// The text starts at the start of the direction: the left edge of the area
  /// from left to right and its right edge from right to left. The offsets of
  /// the scroll move the text away from that start.
  Point contentOrigin(Rect area, double textWidth) {
    final left = isRightToLeft
        ? area.right - textWidth + horizontalScrollOffset
        : area.left - horizontalScrollOffset;
    return Point(left, area.top + _textTopOffset - verticalScrollOffset);
  }

  /// The layout of the text for the measure.
  TextLayout layoutForMeasure(Size availableSize) {
    final host = window;
    final factory = host?.textLayoutFactory ?? _headlessFactory;
    final options = _optionsFor(text, availableSize);
    if (_renderLayout.matches(options, factory)) {
      _measureLayout.dispose();
      return _renderLayout.current!;
    }
    return _measureLayout.resolve(options, factory);
  }

  /// The layout of the text for the render.
  TextLayout layoutForRender(String displayText) {
    final host = window;
    final factory = host?.textLayoutFactory ?? _headlessFactory;
    final options = _optionsFor(displayText, _textPart.bounds.size);
    if (_measureLayout.matches(options, factory)) {
      _renderLayout.dispose();
      return _measureLayout.current!;
    }
    return _renderLayout.resolve(options, factory);
  }

  TextLayoutOptions _optionsFor(String value, Size availableSize) =>
      TextLayoutOptions(
        text: value,
        fontSize: fontSize,
        maxWidth: layoutWidthFor(availableSize),
        scale: window?.displayScale ?? 1,
        direction: flowDirection,
      );

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

  void _bufferChanged(PropertyChangedEvent event) {
    onBufferChanged();
    if (event.property == TextBuffer.textProperty && text != event.newValue) {
      text = event.newValue as String;
    }
    if (event.property == TextBuffer.selectionProperty) {
      invalidatePaint();
    }
    ensureCaretVisible();
    _syncTextInputArea();
  }

  /// Called when the text or the selection of the control changes.
  void onBufferChanged() {}

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
    final area = _textPart.bounds;
    final layout = layoutForRender(text);
    final origin = contentOrigin(area, layout.width);
    final local = Point(position.x - origin.x, position.y - origin.y);
    final offset = layout.hitTest(local).offset.clamp(0, text.length);
    if (offset > 0 &&
        offset < text.length &&
        _isHighSurrogate(text.codeUnitAt(offset - 1)) &&
        _isLowSurrogate(text.codeUnitAt(offset))) {
      final before = offset - 1;
      final after = offset + 1;
      // The caret of the closer grapheme wins. The direction of the text
      // decides on which side of the pair the caret of a grapheme stands.
      final beforeX = layout.caretRect(before).left;
      final afterX = layout.caretRect(after).left;
      final midpoint = (beforeX + afterX) / 2;
      final isBefore =
          beforeX <= afterX ? local.x < midpoint : local.x > midpoint;
      return isBefore ? before : after;
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
    if (handleExtraKey(args)) {
      _clearComposition();
      args.handled = true;
      return;
    }
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
        moveCaretToLineStart(extendSelection: args.shiftPressed);
      case 'end':
        moveCaretToLineEnd(extendSelection: args.shiftPressed);
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
    super.arrangeCore(finalRect);
    if (scrollFollowsCaret) ensureCaretVisible();
    _syncTextInputArea();
  }

  void _syncTextInputArea() {
    if (scrollFollowsCaret) ensureCaretVisible();
    final host = _mountedHost;
    if (host == null || !isFocused) return;
    final area = _textPart.bounds;
    final width = area.width.clamp(1.0, double.infinity);
    final layout = layoutForRender(text);
    final origin = contentOrigin(area, layout.width);
    final cursorX = origin.x - area.left + layout.caretRect(caretOffset).left;
    host.updateTextInputArea(
      this,
      Rect.fromLTWH(
        area.left,
        area.top + _textTopOffset,
        width,
        inputAreaHeight(area, layout).clamp(1.0, double.infinity),
      ),
      cursorX,
    );
  }

  @override
  void onDuiPropertyChanged<T>(
    DuiProperty<dynamic, T> property,
    T oldValue,
    T newValue,
  ) {
    if (identical(property, _textProperty) && buffer.text != newValue) {
      _clearComposition();
      buffer.text = newValue as String;
    }
    super.onDuiPropertyChanged(property, oldValue, newValue);
  }

  @override
  Size measureContentCore(Size availableSize) {
    final size = _textPart.measure(availableSize);
    return Size(
      size.width + contentPaddingHorizontal,
      size.height + contentPaddingVertical,
    );
  }

  @override
  Size measurePart(UIElement part, Size availableSize) {
    if (!identical(part, _textPart)) {
      return super.measurePart(part, availableSize);
    }
    final layout = layoutForMeasure(availableSize);
    return Size(layout.width, layout.height);
  }

  @override
  Rect partRect(UIElement part, Rect contentRect) {
    if (!identical(part, _textPart)) {
      return super.partRect(part, contentRect);
    }
    return contentRect.deflate(_contentPadding);
  }

  @override
  void renderContentCore(DrawingContext context) {
    context.drawRect(bounds, const Paint(Colors.white));
  }

  @override
  void renderPart(UIElement part, DrawingContext context) {
    if (!identical(part, _textPart)) return;
    final area = _textPart.bounds;
    final compositionBase = selection.start;
    final displayText = hasComposition
        ? text.replaceRange(selection.start, selection.end, compositionText)
        : text;
    final layout = layoutForRender(displayText);
    ensureCaretVisible(layout);
    final origin = contentOrigin(area, layout.width);

    context.pushClipRect(area);
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
}
