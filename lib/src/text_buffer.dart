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

  void selectAll() {
    selection = TextSelection(baseOffset: 0, extentOffset: _text.length);
  }

  void _validateOffset(int offset) {
    if (offset < 0 || offset > _text.length) {
      throw RangeError.range(offset, 0, _text.length, 'offset');
    }
  }

  int _previousCodePointOffset(int offset) {
    if (offset >= 2 &&
        _isLowSurrogate(_text.codeUnitAt(offset - 1)) &&
        _isHighSurrogate(_text.codeUnitAt(offset - 2))) {
      return offset - 2;
    }
    return offset - 1;
  }

  int _nextCodePointOffset(int offset) {
    if (offset + 1 < _text.length &&
        _isHighSurrogate(_text.codeUnitAt(offset)) &&
        _isLowSurrogate(_text.codeUnitAt(offset + 1))) {
      return offset + 2;
    }
    return offset + 1;
  }
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;
bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
