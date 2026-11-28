import 'colors.dart';
import 'control_template.dart';
import 'drawing.dart';
import 'events.dart';
import 'geometry.dart';
import 'headless_text_layout.dart';
import 'properties.dart';
import 'semantics.dart';
import 'size_request.dart';
import 'template_part.dart';
import 'templated_control.dart';
import 'text_buffer.dart';
import 'text_layout.dart';
import 'ui_element.dart';

/// A control that edits a text.
///
/// The text of the field is a part of the control: the control owns the text
/// and draws it, a template only places the part. The text therefore survives
/// every template.
final class TextBox extends TemplatedControl {
  TextBox({String text = '', double fontSize = 14})
      : buffer = TextBuffer(text: text),
        super(templateProperty: templateProperty) {
    _textPart = TemplatePart('text', this);
    registerPart('text', _textPart);
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

  static const templateProperty =
      DuiProperty<TextBox, ControlTemplate<TextBox>?>(
    name: 'template',
    defaultValue: null,
    affectsMeasure: true,
    affectsPaint: true,
  );

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

  /// The padding around the text inside the field.
  static const EdgeInsets _contentPadding =
      EdgeInsets.symmetric(horizontal: 8, vertical: 4);

  /// Horizontal padding of the content area, mirrored by [renderPart].
  static const double _contentPaddingHorizontal = 16;

  /// Vertical padding of the content area, mirrored by [renderPart].
  static const double _contentPaddingVertical = 8;

  /// The distance between the top of the text area and the line of text.
  static const double _textTopOffset = 3;

  /// Smallest width the control reports so an empty field stays visible.
  static const double _minimumWidth = 80;

  /// Smallest height the control reports for a single line of text.
  static const double _minimumHeight = 30;

  final TextBuffer buffer;
  late final TemplatePart _textPart;
  WindowHost? _mountedHost;
  String _compositionText = '';
  TextSelection? _compositionSelection;
  final _CachedTextLayout _measureLayout = _CachedTextLayout();
  final _CachedTextLayout _renderLayout = _CachedTextLayout();
  double _horizontalScrollOffset = 0;
  bool _isSelecting = false;

  /// The template of the text box.
  ///
  /// The template owns the look of the field: it places the part with the
  /// text and draws the frame around it. The text itself stays with the
  /// control.
  @override
  ControlTemplate<TextBox>? get template =>
      super.template as ControlTemplate<TextBox>?;

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

  /// The part of the control that holds the text.
  UIElement get textPart => _textPart;

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
    final area = _textPart.bounds;
    final layout = _layoutForRender(text);
    final local = Point(
      position.x - _textOriginX(area, layout.width),
      position.y - area.top - _textTopOffset,
    );
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
    super.arrangeCore(finalRect);
    _ensureCaretVisible();
    _syncTextInputArea();
  }

  /// The x of the left edge of the text inside the text area.
  ///
  /// The text starts at the start of the direction: the left edge of the area
  /// from left to right and its right edge from right to left. The scroll
  /// offset is counted from that start, so the text moves away from it.
  double _textOriginX(Rect area, double textWidth) {
    if (isRightToLeft) {
      return area.right - textWidth + _horizontalScrollOffset;
    }
    return area.left - _horizontalScrollOffset;
  }

  void _ensureCaretVisible([TextLayout? layout]) {
    final viewport = _textPart.bounds.width;
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
    final textWidth = resolved.width;
    final caret = resolved.caretRect(targetOffset).left;
    // The scroll offset is counted from the start of the text, so the caret
    // is measured from the same edge.
    final caretX = isRightToLeft ? textWidth - caret : caret;
    var nextOffset = _horizontalScrollOffset;
    if (caretX < nextOffset) {
      nextOffset = caretX;
    } else if (caretX > nextOffset + viewport - 1) {
      nextOffset = caretX - viewport + 1;
    }
    final contentWidth = textWidth > caretX ? textWidth : caretX.toDouble();
    final maximumOffset =
        contentWidth > viewport ? contentWidth - viewport + 1 : 0.0;
    _horizontalScrollOffset = nextOffset.clamp(0.0, maximumOffset);
  }

  void _syncTextInputArea() {
    _ensureCaretVisible();
    final host = _mountedHost;
    if (host == null || !isFocused) return;
    final area = _textPart.bounds;
    final width = area.width.clamp(1.0, double.infinity);
    final height = (area.height - 6).clamp(1.0, double.infinity);
    final layout = _layoutForRender(text);
    final originX = _textOriginX(area, layout.width);
    final cursorX = originX - area.left + layout.caretRect(caretOffset).left;
    host.updateTextInputArea(
      this,
      Rect.fromLTWH(area.left, area.top + _textTopOffset, width, height),
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
  Size measureContentCore(Size availableSize) {
    final size = _textPart.measure(availableSize);
    return Size(
      size.width + _contentPaddingHorizontal,
      size.height + _contentPaddingVertical,
    );
  }

  @override
  Size measurePart(UIElement part, Size availableSize) {
    if (!identical(part, _textPart)) {
      return super.measurePart(part, availableSize);
    }
    final layout = _layoutForMeasure();
    return Size(layout.width, layout.height);
  }

  @override
  SizeRequest measureRequest(Size availableSize) => SizeRequest(
        minimum: const Size(_minimumWidth, _minimumHeight),
        natural: measureCore(availableSize),
      );

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
    final layout = _layoutForRender(displayText);
    _ensureCaretVisible(layout);
    final origin = Point(
      _textOriginX(area, layout.width),
      area.top + _textTopOffset,
    );

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

  TextLayout _layoutForMeasure() {
    final host = window;
    final factory = host?.textLayoutFactory ?? _headlessFactory;
    final options = TextLayoutOptions(
      text: text,
      fontSize: fontSize,
      maxWidth: double.infinity,
      scale: host?.displayScale ?? 1,
      direction: flowDirection,
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
      direction: flowDirection,
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
