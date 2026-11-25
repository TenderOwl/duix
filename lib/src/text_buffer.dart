import 'observable.dart';

/// A text selection expressed in UTF-16 code unit offsets.
final class TextSelection {
  const TextSelection({
    required this.baseOffset,
    required this.extentOffset,
  });

  const TextSelection.collapsed(int offset)
      : this(baseOffset: offset, extentOffset: offset);

  final int baseOffset;
  final int extentOffset;

  int get start => baseOffset < extentOffset ? baseOffset : extentOffset;
  int get end => baseOffset > extentOffset ? baseOffset : extentOffset;
  bool get isCollapsed => baseOffset == extentOffset;

  @override
  bool operator ==(Object other) =>
      other is TextSelection &&
      other.baseOffset == baseOffset &&
      other.extentOffset == extentOffset;

  @override
  int get hashCode => Object.hash(baseOffset, extentOffset);

  @override
  String toString() =>
      'TextSelection(baseOffset: $baseOffset, extentOffset: $extentOffset)';
}

/// Owns editable text and selection independently from layout and rendering.
final class TextBuffer extends ObservableObject {
  TextBuffer({String text = ''})
      : _text = text,
        _selection = TextSelection.collapsed(text.length);

  static const textProperty = 'text';
  static const selectionProperty = 'selection';

  String _text;
  TextSelection _selection;

  String get text => _text;
  set text(String value) {
    if (_text == value) return;
    final oldText = _text;
    final oldSelection = _selection;
    _text = value;
    _selection = TextSelection(
      baseOffset: oldSelection.baseOffset.clamp(0, value.length),
      extentOffset: oldSelection.extentOffset.clamp(0, value.length),
    );
    notifyPropertyChanged(textProperty, oldText, value);
    if (oldSelection != _selection) {
      notifyPropertyChanged(selectionProperty, oldSelection, _selection);
    }
  }

  TextSelection get selection => _selection;
  set selection(TextSelection value) {
    _validateOffset(value.baseOffset);
    _validateOffset(value.extentOffset);
    if (_selection == value) return;
    final oldValue = _selection;
    _selection = value;
    notifyPropertyChanged(selectionProperty, oldValue, value);
  }

  int get caretOffset => _selection.extentOffset;
  String get selectedText => _text.substring(_selection.start, _selection.end);

  void insertText(String value) => replaceSelection(value);

  void replaceSelection(String replacement) {
    replaceRange(_selection.start, _selection.end, replacement);
  }

  void replaceRange(int start, int end, String replacement) {
    _validateOffset(start);
    _validateOffset(end);
    if (start > end) {
      throw RangeError('Range start $start must not exceed end $end.');
    }

    final oldText = _text;
    final oldSelection = _selection;
    final newText = _text.replaceRange(start, end, replacement);
    _text = newText;
    _selection = TextSelection.collapsed(start + replacement.length);
    if (oldText != newText) {
      notifyPropertyChanged(textProperty, oldText, newText);
    }
    if (oldSelection != _selection) {
      notifyPropertyChanged(selectionProperty, oldSelection, _selection);
    }
  }

  void deleteBackward() {
    if (!_selection.isCollapsed) {
      replaceSelection('');
      return;
    }
    final offset = caretOffset;
    if (offset == 0) return;
    replaceRange(_previousCodePointOffset(offset), offset, '');
  }

  void deleteForward() {
    if (!_selection.isCollapsed) {
      replaceSelection('');
      return;
    }
    final offset = caretOffset;
    if (offset == _text.length) return;
    replaceRange(offset, _nextCodePointOffset(offset), '');
  }

  void moveCaret(int offset, {bool extendSelection = false}) {
    selection = TextSelection(
      baseOffset: extendSelection ? selection.baseOffset : offset,
      extentOffset: offset,
    );
  }

  void moveCaretLeft({bool byWord = false, bool extendSelection = false}) {
    if (!extendSelection && !selection.isCollapsed) {
      moveCaret(selection.start);
      return;
    }
    moveCaret(
      byWord
          ? _previousWordOffset(caretOffset)
          : _previousCodePointOffset(caretOffset),
      extendSelection: extendSelection,
    );
  }

  void moveCaretRight({bool byWord = false, bool extendSelection = false}) {
    if (!extendSelection && !selection.isCollapsed) {
      moveCaret(selection.end);
      return;
    }
    moveCaret(
      byWord ? _nextWordOffset(caretOffset) : _nextCodePointOffset(caretOffset),
      extendSelection: extendSelection,
    );
  }

  void moveCaretToStart({bool extendSelection = false}) =>
      moveCaret(0, extendSelection: extendSelection);

  void moveCaretToEnd({bool extendSelection = false}) =>
      moveCaret(_text.length, extendSelection: extendSelection);

  void selectAll() {
    selection = TextSelection(baseOffset: 0, extentOffset: _text.length);
  }

  void _validateOffset(int offset) {
    if (offset < 0 || offset > _text.length) {
      throw RangeError.range(offset, 0, _text.length, 'offset');
    }
  }

  int _previousCodePointOffset(int offset) {
    if (offset == 0) return 0;
    if (offset >= 2 &&
        _isLowSurrogate(_text.codeUnitAt(offset - 1)) &&
        _isHighSurrogate(_text.codeUnitAt(offset - 2))) {
      return offset - 2;
    }
    return offset - 1;
  }

  int _nextCodePointOffset(int offset) {
    if (offset == _text.length) return offset;
    if (offset + 1 < _text.length &&
        _isHighSurrogate(_text.codeUnitAt(offset)) &&
        _isLowSurrogate(_text.codeUnitAt(offset + 1))) {
      return offset + 2;
    }
    return offset + 1;
  }

  int _previousWordOffset(int offset) {
    var current = offset;
    while (current > 0) {
      final previous = _previousCodePointOffset(current);
      if (!_isWhitespace(_codePointAt(previous))) break;
      current = previous;
    }
    if (current == 0) return 0;
    final isWord = _isWordCodePoint(
      _codePointAt(_previousCodePointOffset(current)),
    );
    while (current > 0) {
      final previous = _previousCodePointOffset(current);
      final codePoint = _codePointAt(previous);
      if (_isWhitespace(codePoint) || _isWordCodePoint(codePoint) != isWord) {
        break;
      }
      current = previous;
    }
    return current;
  }

  int _nextWordOffset(int offset) {
    var current = offset;
    while (current < _text.length && _isWhitespace(_codePointAt(current))) {
      current = _nextCodePointOffset(current);
    }
    if (current == _text.length) return current;
    final isWord = _isWordCodePoint(_codePointAt(current));
    while (current < _text.length) {
      final codePoint = _codePointAt(current);
      if (_isWhitespace(codePoint) || _isWordCodePoint(codePoint) != isWord) {
        break;
      }
      current = _nextCodePointOffset(current);
    }
    return current;
  }

  int _codePointAt(int offset) {
    final first = _text.codeUnitAt(offset);
    if (_isHighSurrogate(first) &&
        offset + 1 < _text.length &&
        _isLowSurrogate(_text.codeUnitAt(offset + 1))) {
      return 0x10000 +
          ((first - 0xD800) << 10) +
          _text.codeUnitAt(offset + 1) -
          0xDC00;
    }
    return first;
  }
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;
bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

bool _isWordCodePoint(int codePoint) =>
    codePoint > 127 ||
    codePoint == 0x5F ||
    (codePoint >= 0x30 && codePoint <= 0x39) ||
    (codePoint >= 0x41 && codePoint <= 0x5A) ||
    (codePoint >= 0x61 && codePoint <= 0x7A);

bool _isWhitespace(int codePoint) =>
    (codePoint >= 0x09 && codePoint <= 0x0D) ||
    codePoint == 0x20 ||
    codePoint == 0x85 ||
    codePoint == 0xA0 ||
    codePoint == 0x1680 ||
    (codePoint >= 0x2000 && codePoint <= 0x200A) ||
    codePoint == 0x2028 ||
    codePoint == 0x2029 ||
    codePoint == 0x202F ||
    codePoint == 0x205F ||
    codePoint == 0x3000;
