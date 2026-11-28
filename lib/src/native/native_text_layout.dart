import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../drawing.dart';
import '../geometry.dart';
import '../text_layout.dart';
import 'native_bindings.dart';

abstract interface class NativeTextDrawingContext implements DrawingContext {
  Pointer<DuiWindowOpaque> get window;
}

final class NativeTextLayoutFactory implements TextLayoutFactory {
  const NativeTextLayoutFactory(this.bindings);

  final NativeBindings bindings;

  @override
  TextLayout create(TextLayoutOptions options) {
    return using((arena) {
      // A layout without a width limit has no line to align the text in: the
      // text fills the whole line, so the alignment would move it away.
      final alignment = options.maxWidth.isFinite
          ? resolveTextAlignment(options.alignment, options.direction)
          : 0;
      final handle = bindings.textLayoutCreate(
        text: options.text,
        fontSize: options.fontSize,
        maxWidth: options.maxWidth,
        scale: options.scale,
        fontFamily: options.fontFamily,
        alignment: alignment,
        direction: options.direction == FlowDirection.rightToLeft ? 1 : 0,
        arena: arena,
      );
      final metrics = bindings.textLayoutMeasure(handle, arena);
      return NativeTextLayout._(
        bindings,
        handle,
        metrics.width,
        metrics.height,
        metrics.baseline,
      );
    });
  }
}

final class NativeTextLayout implements TextLayout {
  NativeTextLayout._(
    this.bindings,
    this.handle,
    this._width,
    this._height,
    this._baseline,
  );

  final NativeBindings bindings;
  final Pointer<DuiTextLayoutOpaque> handle;
  final double _width;
  final double _height;
  final double _baseline;
  bool _isDisposed = false;

  @override
  double get width {
    _checkNotDisposed();
    return _width;
  }

  @override
  double get height {
    _checkNotDisposed();
    return _height;
  }

  @override
  double get baseline {
    _checkNotDisposed();
    return _baseline;
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
    if (context is! NativeTextDrawingContext) {
      throw ArgumentError.value(
        context,
        'context',
        'Native text layout requires NativeTextDrawingContext.',
      );
    }
    bindings.textLayoutDraw(
      context.window,
      handle,
      position.x,
      position.y,
      paint.color.value,
    );
  }

  @override
  TextPosition hitTest(Point position) {
    _checkNotDisposed();
    return TextPosition(
      using((arena) => bindings.textLayoutHitTest(
            handle,
            position.x,
            position.y,
            arena,
          )),
    );
  }

  @override
  Rect caretRect(int offset) {
    _checkNotDisposed();
    final rect = using(
      (arena) => bindings.textLayoutCaretRect(handle, offset, arena),
    );
    return _rect(rect);
  }

  @override
  List<Rect> selectionRects(int start, int end) {
    _checkNotDisposed();
    final rects = using(
      (arena) => bindings.textLayoutSelectionRects(handle, start, end, arena),
    );
    return List<Rect>.unmodifiable(rects.map(_rect));
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    bindings.textLayoutDestroy(handle);
    _isDisposed = true;
  }

  static Rect _rect(NativeRect rect) => Rect.fromLTWH(
        rect.left,
        rect.top,
        rect.width,
        rect.height,
      );

  void _checkNotDisposed() {
    if (_isDisposed) throw StateError('The text layout is disposed.');
  }
}
