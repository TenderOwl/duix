import 'dart:math' as math;

import 'drawing.dart';
import 'geometry.dart';
import 'text_layout.dart';

/// Deterministic text layout for unit tests and non-native rendering.
final class HeadlessTextLayoutFactory implements TextLayoutFactory {
  const HeadlessTextLayoutFactory();

  @override
  TextLayout create(TextLayoutOptions options) => HeadlessTextLayout._(options);
}

final class HeadlessTextLayout implements TextLayout {
  HeadlessTextLayout._(this.options)
      : _lines = _wrapLines(
          options.text,
          options.maxWidth,
          options.fontSize * 0.6,
        ),
        _lineHeight = options.fontSize * 1.3,
        _characterWidth = options.fontSize * 0.6 {
    if (options.fontSize <= 0 || !options.fontSize.isFinite) {
      throw ArgumentError.value(options.fontSize, 'fontSize');
    }
    if (options.maxWidth < 0 || options.maxWidth.isNaN) {
      throw ArgumentError.value(options.maxWidth, 'maxWidth');
    }
    if (options.scale <= 0 || !options.scale.isFinite) {
      throw ArgumentError.value(options.scale, 'scale');
    }
  }

  final TextLayoutOptions options;

  /// The visual lines of the text.
  ///
  /// A logical line is broken into the pieces that fit into the width of the
  /// layout, so the lines of the layout are the lines of the screen.
  final List<_HeadlessLine> _lines;
  final double _lineHeight;
  final double _characterWidth;
  bool _isDisposed = false;

  /// Breaks the text into the lines that fit into the width of the layout.
  static List<_HeadlessLine> _wrapLines(
    String text,
    double maxWidth,
    double characterWidth,
  ) {
    final lines = <_HeadlessLine>[];
    var offset = 0;
    for (final content in text.split('\n')) {
      if (content.isEmpty) {
        lines.add(_HeadlessLine(offset, offset));
        offset += 1;
        continue;
      }
      final fit = maxWidth.isFinite && characterWidth > 0
          ? math.max(1, (maxWidth / characterWidth).floor())
          : content.length;
      var start = 0;
      while (start < content.length) {
        var end = math.min(start + fit, content.length);
        if (end < content.length) {
          // The line breaks at the last space of the piece, so a word is not
          // split when it fits.
          final space = content.lastIndexOf(' ', end - 1);
          if (space > start) end = space;
        }
        lines.add(_HeadlessLine(offset + start, offset + end));
        start = end;
        while (start < content.length && content[start] == ' ') {
          start++;
        }
      }
      offset += content.length + 1;
    }
    return lines;
  }

  @override
  double get width {
    _checkNotDisposed();
    return math.min(_textWidth, options.maxWidth);
  }

  /// The width of the longest line, without the limit of the layout.
  double get _textWidth => _lines.fold<double>(
        0,
        (maximum, line) => math.max(maximum, line.length * _characterWidth),
      );

  /// The distance between the left edge of the layout and the text.
  ///
  /// The text is aligned inside the layout the way the backend does it: the
  /// logical alignment is resolved for the direction of the layout, so the
  /// text of a right to left layout starts at the right edge.
  double get _alignmentOffset {
    final textWidth = _textWidth;
    final available = options.maxWidth.isFinite ? options.maxWidth : textWidth;
    final free = math.max(0.0, available - textWidth);
    return switch (resolveTextAlignment(options.alignment, options.direction)) {
      1 => free / 2,
      2 => free,
      _ => 0.0,
    };
  }

  @override
  double get height {
    _checkNotDisposed();
    return _lines.length * _lineHeight;
  }

  @override
  double get baseline {
    _checkNotDisposed();
    return options.fontSize;
  }

  @override
  bool get isDisposed => _isDisposed;

  @override
  void draw(
    DrawingContext context,
    Point position, {
    Paint paint = const Paint(Color(0xFF000000)),
  }) {
    _checkNotDisposed();
    for (var index = 0; index < _lines.length; index++) {
      final line = _lines[index];
      if (line.length == 0) continue;
      context.drawText(
        options.text.substring(line.start, line.end),
        Point(position.x + _alignmentOffset, position.y + index * _lineHeight),
        fontSize: options.fontSize,
        color: paint.color,
        alignment: options.alignment,
      );
    }
  }

  @override
  TextPosition hitTest(Point position) {
    _checkNotDisposed();
    final lineIndex =
        (position.y / _lineHeight).floor().clamp(0, _lines.length - 1);
    final line = _lines[lineIndex];
    final column = _characterWidth == 0
        ? 0
        : ((position.x - _alignmentOffset) / _characterWidth)
            .round()
            .clamp(0, line.length);
    return TextPosition(line.start + column);
  }

  @override
  Rect caretRect(int offset) {
    _checkNotDisposed();
    _checkOffset(offset);
    final index = _lineIndexAt(offset);
    final line = _lines[index];
    final column = (offset - line.start).clamp(0, line.length);
    return Rect.fromLTWH(
      column * _characterWidth + _alignmentOffset,
      index * _lineHeight,
      0,
      _lineHeight,
    );
  }

  @override
  List<Rect> selectionRects(int start, int end) {
    _checkNotDisposed();
    _checkOffset(start);
    _checkOffset(end);
    if (start > end) {
      throw RangeError('Selection start must not exceed selection end.');
    }
    if (start == end) return const [];

    final rects = <Rect>[];
    for (var index = 0; index < _lines.length; index++) {
      final line = _lines[index];
      final selectionStart = math.max(start, line.start);
      final selectionEnd = math.min(end, line.end);
      if (selectionStart >= selectionEnd) continue;
      rects.add(Rect.fromLTWH(
        (selectionStart - line.start) * _characterWidth + _alignmentOffset,
        index * _lineHeight,
        (selectionEnd - selectionStart) * _characterWidth,
        _lineHeight,
      ));
    }
    return List<Rect>.unmodifiable(rects);
  }

  /// The index of the line that holds the offset.
  int _lineIndexAt(int offset) {
    var index = 0;
    for (var position = 0; position < _lines.length; position++) {
      if (_lines[position].start > offset) break;
      index = position;
    }
    return index;
  }

  @override
  void dispose() {
    _isDisposed = true;
  }

  void _checkOffset(int offset) {
    if (offset < 0 || offset > options.text.length) {
      throw RangeError.range(offset, 0, options.text.length, 'offset');
    }
  }

  void _checkNotDisposed() {
    if (_isDisposed) throw StateError('The text layout is disposed.');
  }
}

/// A line of the text with the offsets it covers.
final class _HeadlessLine {
  const _HeadlessLine(this.start, this.end);

  /// The offset of the first character of the line.
  final int start;

  /// The offset behind the last character of the line.
  final int end;

  int get length => end - start;
}
