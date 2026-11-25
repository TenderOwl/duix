import 'drawing.dart';
import 'events.dart';
import 'geometry.dart';
import 'headless_text_layout.dart';
import 'properties.dart';
import 'text_buffer.dart';
import 'text_layout.dart';
import 'ui_element.dart';

final class TextBlock extends Control {
  TextBlock({
    String text = '',
    double fontSize = 14,
    Color color = Colors.black,
    TextAlignment alignment = TextAlignment.start,
  }) : _alignment = alignment {
    setValue(textProperty, text);
    setValue(fontSizeProperty, fontSize);
    setValue(colorProperty, color);
  }

  static const textProperty = DuiProperty<TextBlock, String>(
    name: 'text',
    defaultValue: '',
    affectsMeasure: true,
    affectsPaint: true,
  );
  static const fontSizeProperty = DuiProperty<TextBlock, double>(
    name: 'fontSize',
    defaultValue: 14,
    affectsMeasure: true,
    affectsPaint: true,
  );
  static const colorProperty = DuiProperty<TextBlock, Color>(
    name: 'color',
    defaultValue: Colors.black,
    affectsPaint: true,
  );

  static const _headlessFactory = HeadlessTextLayoutFactory();

  TextAlignment _alignment;
  TextLayout? _textLayout;
  TextLayoutOptions? _textLayoutOptions;
  TextLayoutFactory? _textLayoutFactory;

  String get text => getValue(textProperty);
  set text(String value) => setValue(textProperty, value);

  double get fontSize => getValue(fontSizeProperty);
  set fontSize(double value) => setValue(fontSizeProperty, value);

  Color get color => getValue(colorProperty);
  set color(Color value) => setValue(colorProperty, value);

  TextAlignment get alignment => _alignment;
  set alignment(TextAlignment value) {
    if (_alignment == value) return;
    _alignment = value;
    invalidateMeasure();
  }

  @override
  bool get isFocusable => false;

  @override
  Size measureCore(Size availableSize) {
    final layout = _layoutFor(availableSize.width);
    return Size(layout.width, layout.height);
  }

  @override
  void renderCore(DrawingContext context) {
    final layout = _textLayout ?? _layoutFor(bounds.width);
    layout.draw(
      context,
      Point(bounds.left, bounds.top),
      paint: Paint(color),
    );
  }

  @override
  void onMounted() {
    invalidateMeasure();
  }

  @override
  void onUnmounted() {
    _clearTextLayout();
    invalidateMeasure();
  }

  TextLayout _layoutFor(double maxWidth) {
    final host = window;
    final factory = host?.textLayoutFactory ?? _headlessFactory;
    final options = TextLayoutOptions(
      text: text,
      fontSize: fontSize,
      maxWidth: maxWidth,
      scale: host?.displayScale ?? 1,
      alignment: alignment,
    );
    final current = _textLayout;
    if (current != null &&
        !current.isDisposed &&
        identical(_textLayoutFactory, factory) &&
        _textLayoutOptions == options) {
      return current;
    }

    _clearTextLayout();
    final created = factory.create(options);
    _textLayout = created;
    _textLayoutOptions = options;
    _textLayoutFactory = factory;
    return created;
  }

  void _clearTextLayout() {
    _textLayout?.dispose();
    _textLayout = null;
    _textLayoutOptions = null;
    _textLayoutFactory = null;
  }
}

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

final class Button extends ContentControl {
  Button({super.content, void Function()? onClick}) {
    if (onClick != null) addClickHandler(onClick);
    addHandler(UIElement.pointerDown, _pointerDown);
    addHandler(UIElement.pointerUp, _pointerUp);
  }

  final _clickHandlers = <void Function()>[];
  bool _isPressed = false;

  bool get isPressed => _isPressed;

  void addClickHandler(void Function() handler) => _clickHandlers.add(handler);
  void removeClickHandler(void Function() handler) =>
      _clickHandlers.remove(handler);

  void _pointerDown(Object sender, PointerEventArgs args) {
    if (!isEnabled) return;
    _isPressed = true;
    focus();
    invalidatePaint();
  }

  void _pointerUp(Object sender, PointerEventArgs args) {
    if (!_isPressed) return;
    _isPressed = false;
    invalidatePaint();
    for (final handler in List<void Function()>.of(_clickHandlers)) {
      handler();
    }
    args.handled = true;
  }

  @override
  Size measureCore(Size availableSize) {
    final childSize = super.measureCore(availableSize);
    return Size(childSize.width + 24, childSize.height + 12);
  }

  @override
  void arrangeCore(Rect finalRect) {
    content?.arrange(Rect.fromLTWH(
      finalRect.left + 12,
      finalRect.top + 6,
      (finalRect.width - 24).clamp(0, double.infinity),
      (finalRect.height - 12).clamp(0, double.infinity),
    ));
  }

  @override
  void renderCore(DrawingContext context) {
    context.drawRect(
      bounds,
      Paint(isPressed ? const Color(0xFFB0B0B0) : const Color(0xFFE0E0E0)),
    );
    super.renderCore(context);
  }
}

final class TextBox extends Control {
  TextBox({String text = ''}) : buffer = TextBuffer(text: text) {
    setValue(textProperty, text);
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

  static const _headlessFactory = HeadlessTextLayoutFactory();

  final TextBuffer buffer;
  WindowHost? _mountedHost;
  String _compositionText = '';
  TextSelection? _compositionSelection;
  TextLayout? _renderLayout;
  TextLayoutOptions? _renderLayoutOptions;
  TextLayoutFactory? _renderLayoutFactory;
  double _horizontalScrollOffset = 0;
  bool _isSelecting = false;

  String get text => getValue(textProperty);
  set text(String value) => setValue(textProperty, value);

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
    if (isFocused) window?.startTextInput(this);
  }

  @override
  void onUnmounted() {
    _cancelPointerSelection();
    _clearComposition();
    _clearRenderLayout();
    if (isFocused) _mountedHost?.stopTextInput(this);
    _mountedHost = null;
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
  Size measureCore(Size availableSize) => Size(
        (text.length * 8.4 + 16).clamp(80, availableSize.width),
        30,
      );

  @override
  void renderCore(DrawingContext context) {
    context.drawRect(bounds, const Paint(Colors.white));
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

  TextLayout _layoutForRender(String displayText) {
    final host = window;
    final factory = host?.textLayoutFactory ?? _headlessFactory;
    final options = TextLayoutOptions(
      text: displayText,
      fontSize: 14,
      maxWidth: double.infinity,
      scale: host?.displayScale ?? 1,
    );
    final current = _renderLayout;
    if (current != null &&
        !current.isDisposed &&
        identical(_renderLayoutFactory, factory) &&
        _renderLayoutOptions == options) {
      return current;
    }
    _clearRenderLayout();
    final created = factory.create(options);
    _renderLayout = created;
    _renderLayoutOptions = options;
    _renderLayoutFactory = factory;
    return created;
  }

  void _clearRenderLayout() {
    _renderLayout?.dispose();
    _renderLayout = null;
    _renderLayoutOptions = null;
    _renderLayoutFactory = null;
  }
}

final class Border extends ContentControl {
  Border({
    super.content,
    Color color = Colors.black,
    EdgeInsets padding = EdgeInsets.zero,
  })  : _color = color,
        _padding = padding;

  Color _color;
  EdgeInsets _padding;

  Color get color => _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    invalidatePaint();
  }

  EdgeInsets get padding => _padding;
  set padding(EdgeInsets value) {
    if (_padding == value) return;
    _padding = value;
    invalidateMeasure();
  }

  @override
  bool get isFocusable => false;

  @override
  Size measureCore(Size availableSize) {
    final inner = Size(
      (availableSize.width - padding.horizontal).clamp(0, double.infinity),
      (availableSize.height - padding.vertical).clamp(0, double.infinity),
    );
    return padding.inflateSize(super.measureCore(inner));
  }

  @override
  void arrangeCore(Rect finalRect) {
    content?.arrange(finalRect.deflate(padding));
  }

  @override
  void renderCore(DrawingContext context) {
    context.drawRect(bounds, Paint(color));
    super.renderCore(context);
  }
}

abstract final class Colors {
  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);
}
