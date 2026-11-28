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
      : _lines = options.text.split('\n'),
        _lineStarts = _computeLineStarts(options.text),
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
  final List<String> _lines;
  final List<int> _lineStarts;
  final double _lineHeight;
  final double _characterWidth;
  bool _isDisposed = false;

  static List<int> _computeLineStarts(String text) {
    final starts = <int>[0];
    var offset = 0;
    final lines = text.split('\n');
    for (var index = 0; index < lines.length - 1; index++) {
      offset += lines[index].length + 1;
      starts.add(offset);
    }
    return starts;
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
    context.drawText(
      options.text,
      Point(position.x + _alignmentOffset, position.y),
      fontSize: options.fontSize,
      color: paint.color,
      alignment: options.alignment,
    );
  }

  @override
  TextPosition hitTest(Point position) {
    _checkNotDisposed();
    final lineIndex =
        (position.y / _lineHeight).floor().clamp(0, _lines.length - 1);
    final column = _characterWidth == 0
        ? 0
        : ((position.x - _alignmentOffset) / _characterWidth)
            .round()
            .clamp(0, _lines[lineIndex].length);
    return TextPosition(_lineStarts[lineIndex] + column);
  }

  @override
  Rect caretRect(int offset) {
    _checkNotDisposed();
    _checkOffset(offset);
    for (var index = 0; index < _lines.length; index++) {
      final lineEnd = _lineStarts[index] + _lines[index].length;
      if (offset <= lineEnd) {
        return Rect.fromLTWH(
          (offset - _lineStarts[index]) * _characterWidth + _alignmentOffset,
          index * _lineHeight,
          0,
          _lineHeight,
        );
      }
    }
    final last = _lines.length - 1;
    return Rect.fromLTWH(
      _lines[last].length * _characterWidth + _alignmentOffset,
      last * _lineHeight,
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
      final lineStart = _lineStarts[index];
      final lineEnd = lineStart + _lines[index].length;
      final selectionStart = math.max(start, lineStart);
      final selectionEnd = math.min(end, lineEnd);
      if (selectionStart >= selectionEnd) continue;
      rects.add(Rect.fromLTWH(
        (selectionStart - lineStart) * _characterWidth + _alignmentOffset,
        index * _lineHeight,
        (selectionEnd - selectionStart) * _characterWidth,
        _lineHeight,
      ));
    }
    return List<Rect>.unmodifiable(rects);
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
