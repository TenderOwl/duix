import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../drawing.dart';
import '../geometry.dart';
import '../window.dart';
import 'native_bindings.dart';

final class _NativeWindowSession {
  _NativeWindowSession(this.pointer, this.id);

  final Pointer<DuiWindowOpaque> pointer;
  final int id;
  bool open = true;
}

final class SdlSkiaHost implements NativeHost {
  SdlSkiaHost._(this.bindings) : _host = bindings.hostCreate() {
    if (_host == nullptr) {
      throw StateError('Could not create SDL host: ${bindings.lastError}');
    }
  }

  final NativeBindings bindings;
  final Pointer<DuiHostOpaque> _host;
  final _sessions = <Window, _NativeWindowSession>{};
  final _windowsById = <int, Window>{};
  bool _disposed = false;

  static Future<SdlSkiaHost> initialize({String? libraryPath}) async {
    return SdlSkiaHost._(NativeBindings.open(libraryPath: libraryPath));
  }

  bool isOpen(Window window) => _sessions[window]?.open ?? false;

  @override
  Future<void> showWindow(Window window) async {
    _checkNotDisposed();
    if (isOpen(window)) return;
    final title = window.title.toNativeUtf8();
    try {
      final pointer = bindings.windowCreate(
        _host,
        title,
        window.logicalSize.width.round(),
        window.logicalSize.height.round(),
      );
      if (pointer == nullptr) {
        throw StateError('Could not create SDL window: ${bindings.lastError}');
      }
      final id = bindings.windowGetId(pointer);
      _sessions[window] = _NativeWindowSession(pointer, id);
      _windowsById[id] = window;
      await window.show();
      presentWindow(window);
    } finally {
      calloc.free(title);
    }
  }

  @override
  Future<void> closeWindow(Window window) async {
    _destroySession(window);
    window.close();
  }

  void pumpEvents() {
    _checkNotDisposed();
    using((arena) {
      while (true) {
        final event = bindings.nextEvent(_host, arena);
        if (event == null) break;
        _dispatchEvent(event);
      }
    });
  }

  void presentWindow(Window window) {
    _checkNotDisposed();
    final session = _sessions[window];
    if (session == null || !session.open || !window.isVisible) return;
    bindings.windowSetBackground(session.pointer, window.background.value);
    if (bindings.windowBeginFrame(session.pointer) == 0) {
      throw StateError('Could not begin native frame: ${bindings.lastError}');
    }
    try {
      window.renderFrame(NativeDrawingContext(bindings, session.pointer));
    } finally {
      if (bindings.windowPresent(session.pointer) == 0) {
        throw StateError(
            'Could not present native frame: ${bindings.lastError}');
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    for (final window in _sessions.keys.toList()) {
      _destroySession(window);
      window.close();
    }
    bindings.hostDestroy(_host);
    _disposed = true;
  }

  void _dispatchEvent(NativeEvent event) {
    if (event.type == 1) {
      for (final window in _sessions.keys.toList()) {
        _destroySession(window);
        window.close();
      }
      return;
    }

    final window = _windowsById[event.windowId];
    if (window == null || !isOpen(window)) return;
    switch (event.type) {
      case 2:
        _destroySession(window);
        window.close();
      case 3:
        window.resize(event.width, event.height);
      case 4:
        window.dispatchPointerDown(Point(event.x, event.y));
      case 5:
        window.dispatchPointerUp(Point(event.x, event.y));
      case 7:
        final text = event.text;
        if (text != null) window.dispatchTextInput(text);
    }
  }

  void _destroySession(Window window) {
    final session = _sessions.remove(window);
    if (session == null || !session.open) return;
    session.open = false;
    _windowsById.remove(session.id);
    bindings.windowDestroy(_host, session.pointer);
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('The SDL host is disposed.');
  }
}

final class NativeDrawingContext implements DrawingContext {
  NativeDrawingContext(this.bindings, this.window);

  final NativeBindings bindings;
  final Pointer<DuiWindowOpaque> window;

  @override
  void drawRect(Rect rect, Paint paint) {
    bindings.drawRect(
      window,
      rect.left,
      rect.top,
      rect.width,
      rect.height,
      paint.color.value,
    );
  }

  @override
  void drawText(
    String text,
    Point position, {
    required double fontSize,
    required Color color,
    TextAlignment alignment = TextAlignment.start,
  }) {
    final nativeText = text.toNativeUtf8();
    try {
      bindings.drawText(
        window,
        nativeText,
        position.x,
        position.y,
        fontSize,
        color.value,
        alignment.index,
      );
    } finally {
      calloc.free(nativeText);
    }
  }
}
