import 'dart:math' as math;

import 'control_template.dart';
import 'events.dart';
import 'geometry.dart';
import 'observable.dart';
import 'properties.dart';
import 'scroll_bar.dart';
import 'size_request.dart';
import 'text_editor.dart';
import 'text_layout.dart';
import 'ui_element.dart';

/// A control that edits several lines of text.
///
/// The text of the field is a part of the control, and the vertical scroll bar
/// is the second part: the control owns both of them, a template only places
/// them.
///
/// The text is wrapped into the width of the area, so a long text grows down
/// and the field scrolls it vertically. Shift+Enter starts a new line, the
/// arrows move the caret between the lines, and the wheel scrolls the text.
final class TextArea extends TextEditor {
  TextArea({super.text, super.fontSize})
      : super(
          textProperty: textProperty,
          fontSizeProperty: fontSizeProperty,
          templateProperty: templateProperty,
        ) {
    _scrollBar = ScrollBar(orientation: Orientation.vertical);
    registerPart('verticalScrollBar', _scrollBar);
    _scrollBar.addPropertyListener(_scrollBarChanged);
    addHandler(UIElement.mouseWheel, _mouseWheel);
  }

  static const templateProperty =
      DuiProperty<TextArea, ControlTemplate<TextArea>?>(
    name: 'template',
    defaultValue: null,
    affectsMeasure: true,
    affectsPaint: true,
  );

  static const textProperty = DuiProperty<TextArea, String>(
    name: 'text',
    defaultValue: '',
    affectsMeasure: true,
    affectsPaint: true,
  );
  static const fontSizeProperty = DuiProperty<TextArea, double>(
    name: 'fontSize',
    defaultValue: 14,
    affectsMeasure: true,
    affectsPaint: true,
  );

  /// The thickness of the vertical scroll bar of the area.
  static const double scrollBarThickness = ScrollBar.defaultThickness;

  /// The distance the wheel scrolls the text.
  static const double wheelScrollDistance = 48.0;

  /// Smallest width the control reports so an empty area stays visible.
  static const double _minimumWidth = 80;

  /// Smallest height the control reports so an empty area stays visible.
  static const double _minimumHeight = 60;

  late final ScrollBar _scrollBar;
  double _verticalScrollOffset = 0;
  double _contentHeight = 0;
  bool _isScrollBarVisible = false;
  bool _isSyncingScrollBar = false;
  bool _followsCaret = true;

  /// The template of the text area.
  ///
  /// The template owns the look of the area: it places the part with the text
  /// and the part with the scroll bar. The text itself stays with the control.
  @override
  ControlTemplate<TextArea>? get template =>
      super.template as ControlTemplate<TextArea>?;

  /// The vertical scroll bar of the area.
  ScrollBar get verticalScrollBar => _scrollBar;

  /// The offset of the vertical scroll of the text.
  double get verticalOffset => _verticalScrollOffset;
  set verticalOffset(double value) => scrollTo(value);

  /// Whether the vertical scroll bar of the area is shown.
  bool get isScrollBarVisible => _isScrollBarVisible;

  /// The height of the text inside the area.
  double get contentHeight => _contentHeight;

  @override
  double get verticalScrollOffset => _verticalScrollOffset;

  /// The area has a scroll of its own, so the user can scroll the text away
  /// from the caret. The scroll follows the caret again as soon as the caret
  /// moves.
  @override
  bool get scrollFollowsCaret => _followsCaret;

  @override
  void onBufferChanged() {
    // The caret moved, so the scroll follows it again.
    _followsCaret = true;
  }

  @override
  double layoutWidthFor(Size availableSize) {
    final width = availableSize.width;
    if (!width.isFinite || width <= 0) return double.infinity;
    return width;
  }

  /// Scrolls the text to the given offset.
  bool scrollTo(double offset) {
    final next = offset.clamp(0.0, _maximumOffset).toDouble();
    if (next == _verticalScrollOffset) return false;
    _verticalScrollOffset = next;
    _followsCaret = false;
    invalidateArrange();
    _syncScrollBar();
    return true;
  }

  /// Scrolls the text by the given distance.
  bool scrollBy(double distance) => scrollTo(_verticalScrollOffset + distance);

  double get _maximumOffset =>
      math.max(0.0, _contentHeight - _viewportHeight).toDouble();

  double get _viewportHeight => textPart.bounds.height;

  @override
  void ensureCaretVisible([TextLayout? layout]) {
    final viewport = _viewportHeight;
    if (viewport <= 0) {
      _verticalScrollOffset = 0;
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
    final resolved = layout ?? layoutForRender(displayText);
    final caret = resolved.caretRect(targetOffset);
    var nextOffset = _verticalScrollOffset;
    if (caret.top < nextOffset) {
      nextOffset = caret.top;
    } else if (caret.bottom > nextOffset + viewport) {
      nextOffset = caret.bottom - viewport;
    }
    final maximumOffset = math.max(0, resolved.height - viewport).toDouble();
    _verticalScrollOffset = nextOffset.clamp(0.0, maximumOffset);
  }

  @override
  void moveCaretToLineStart({bool extendSelection = false}) {
    final offset = caretOffset;
    if (offset == 0) {
      moveCaret(0, extendSelection: extendSelection);
      return;
    }
    final index = text.lastIndexOf('\n', offset - 1);
    moveCaret(index < 0 ? 0 : index + 1, extendSelection: extendSelection);
  }

  @override
  void moveCaretToLineEnd({bool extendSelection = false}) {
    final offset = caretOffset;
    final index = text.indexOf('\n', offset);
    moveCaret(index < 0 ? text.length : index,
        extendSelection: extendSelection);
  }

  @override
  bool handleExtraKey(KeyEventArgs args) {
    if (args.primaryShortcutPressed) return false;
    switch (args.key) {
      case 'up':
        _moveCaretVertically(-1, extendSelection: args.shiftPressed);
        return true;
      case 'down':
        _moveCaretVertically(1, extendSelection: args.shiftPressed);
        return true;
      case 'enter' when args.shiftPressed:
        insertText('\n');
        return true;
      default:
        return false;
    }
  }

  /// Moves the caret to the line above or below, keeping the column.
  void _moveCaretVertically(double direction, {bool extendSelection = false}) {
    final layout = layoutForRender(text);
    final caret = layout.caretRect(caretOffset);
    final lineHeight = caret.height > 0 ? caret.height : layout.height;
    final target = layout.hitTest(
      Point(caret.left, caret.top + direction * lineHeight),
    );
    moveCaret(target.offset.clamp(0, text.length),
        extendSelection: extendSelection);
  }

  void _mouseWheel(Object sender, MouseWheelEventArgs args) {
    if (!isEnabled) return;
    final handled = scrollBy(args.deltaY * wheelScrollDistance);
    args.handled = handled;
  }

  @override
  Size measurePart(UIElement part, Size availableSize) {
    if (!identical(part, textPart)) {
      return super.measurePart(part, availableSize);
    }
    // The scroll bar takes a part of the width, and the width decides how
    // the text is wrapped, so the measure settles the scroll bar and the
    // width of the text together.
    var size = Size.zero;
    for (var pass = 0; pass < 4; pass++) {
      size = super.measurePart(part, _contentSize(availableSize));
      _contentHeight = size.height;
      final visible =
          _needsScrollBar(size.height, _viewportHeightFor(availableSize));
      if (visible == _isScrollBarVisible) break;
      _isScrollBarVisible = visible;
    }
    return size;
  }

  /// The size the text is laid out in.
  ///
  /// The text sits in the area without the padding of the control and without
  /// the scroll bar, so the wrapping of the measure is the wrapping that the
  /// render shows.
  Size _contentSize(Size availableSize) => Size(
        math.max(
          0,
          availableSize.width -
              TextEditor.contentPaddingHorizontal -
              (_isScrollBarVisible ? scrollBarThickness : 0),
        ),
        math.max(
          0,
          availableSize.height - TextEditor.contentPaddingVertical,
        ),
      );

  /// The height the text is shown in: the height of the area without the
  /// padding of the control.
  double _viewportHeightFor(Size availableSize) => math.max(
        0,
        availableSize.height - TextEditor.contentPaddingVertical,
      );

  bool _needsScrollBar(double contentHeight, double availableHeight) {
    if (!availableHeight.isFinite) return false;
    return contentHeight > availableHeight;
  }

  @override
  Rect partRect(UIElement part, Rect contentRect) {
    if (identical(part, _scrollBar)) {
      if (!_isScrollBarVisible) return Rect.zero;
      return Rect.fromLTWH(
        isRightToLeft
            ? contentRect.left
            : contentRect.right - scrollBarThickness,
        contentRect.top,
        scrollBarThickness,
        contentRect.height,
      );
    }
    final rect = super.partRect(part, contentRect);
    if (!identical(part, textPart) || !_isScrollBarVisible) return rect;
    final width = math.max(0.0, rect.width - scrollBarThickness).toDouble();
    return Rect.fromLTWH(
      isRightToLeft ? rect.left + scrollBarThickness : rect.left,
      rect.top,
      width,
      rect.height,
    );
  }

  @override
  void arrangeCore(Rect finalRect) {
    _verticalScrollOffset = _verticalScrollOffset.clamp(0.0, _maximumOffset);
    super.arrangeCore(finalRect);
    _syncScrollBar();
  }

  void _syncScrollBar() {
    _isSyncingScrollBar = true;
    try {
      _scrollBar
        ..minimum = 0
        ..maximum = _maximumOffset
        ..value = _verticalScrollOffset
        ..viewportSize = _viewportHeight
        ..thickness = scrollBarThickness
        ..isVisible = _isScrollBarVisible;
    } finally {
      _isSyncingScrollBar = false;
    }
  }

  void _scrollBarChanged(PropertyChangedEvent event) {
    if (!identical(event.property, ScrollBar.valueProperty)) return;
    if (_isSyncingScrollBar) return;
    final value = event.newValue as double;
    if (value == _verticalScrollOffset) return;
    _verticalScrollOffset = value;
    invalidateArrange();
  }

  @override
  SizeRequest measureRequest(Size availableSize) => SizeRequest(
        minimum: const Size(_minimumWidth, _minimumHeight),
        natural: measureCore(availableSize),
      );
}
