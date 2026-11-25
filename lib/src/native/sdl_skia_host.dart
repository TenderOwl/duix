import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../drawing.dart';
import '../events.dart';
import '../geometry.dart';
import '../window.dart';
import 'native_bindings.dart';
import 'native_text_layout.dart';

final class _NativeWindowSession {
  _NativeWindowSession(this.pointer, this.id);

  static const _frameRateSampleMicros = 500000;

  final Pointer<DuiWindowOpaque> pointer;
  final int id;
  final Stopwatch frameRateStopwatch = Stopwatch()..start();
  bool open = true;
  int presentCount = 0;
  int frameRateWindowStart = 0;
  double? framesPerSecond;

  String get frameRateLabel {
    final value = framesPerSecond;
    return value == null ? '0.0 FPS' : '${value.toStringAsFixed(1)} FPS';
  }

  void sampleFrameRate() {
    final elapsed = frameRateStopwatch.elapsedMicroseconds;
    if (elapsed < _frameRateSampleMicros) return;
    final presented = presentCount + 1 - frameRateWindowStart;
    framesPerSecond = presented * Duration.microsecondsPerSecond / elapsed;
    frameRateWindowStart = presentCount + 1;
    frameRateStopwatch
      ..reset()
      ..start();
  }
}

final class NativeWindowDiagnostics {
  const NativeWindowDiagnostics({
    required this.displayScale,
    required this.pixelDensity,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.physicalWidth,
    required this.physicalHeight,
    required this.scheduledFrameCount,
    required this.layoutPassCount,
    required this.paintPassCount,
    required this.presentCount,
    required this.framesPerSecond,
  });

  final double displayScale;
  final double pixelDensity;
  final double logicalWidth;
  final double logicalHeight;
  final int physicalWidth;
  final int physicalHeight;
  final int scheduledFrameCount;
  final int layoutPassCount;
  final int paintPassCount;
  final int presentCount;
  final double? framesPerSecond;

  int get renderFrameCount => paintPassCount;

  @override
  String toString() {
    return 'Native diagnostics: displayScale=$displayScale, '
        'pixelDensity=$pixelDensity, '
        'logical=${logicalWidth}x$logicalHeight, '
        'physical=${physicalWidth}x$physicalHeight, '
        'scheduled=$scheduledFrameCount, layout=$layoutPassCount, '
        'painted=$paintPassCount, presented=$presentCount, '
        'fps=${framesPerSecond?.toStringAsFixed(1) ?? '--'}';
  }
}

final class SdlSkiaHost
    implements NativeHost, TextInputHandler, ClipboardHandler {
  SdlSkiaHost._(this.bindings, {required this.diagnosticsEnabled})
      : _host = bindings.hostCreate() {
    if (_host == nullptr) {
      throw StateError('Could not create SDL host: ${bindings.lastError}');
    }
    _liveResizeCallable = NativeCallable<LiveResizeCallbackNative>.isolateLocal(
      _handleLiveResize,
    );
    if (bindings.hostSetLiveResizeCallback(
          _host,
          _liveResizeCallable.nativeFunction,
          nullptr,
        ) ==
        0) {
      final error = bindings.lastError;
      _liveResizeCallable.close();
      bindings.hostDestroy(_host);
      throw StateError('Could not register SDL resize callback: $error');
    }
  }

  final NativeBindings bindings;
  late final textLayoutFactory = NativeTextLayoutFactory(bindings);
  final bool diagnosticsEnabled;
  final Pointer<DuiHostOpaque> _host;
  late final NativeCallable<LiveResizeCallbackNative> _liveResizeCallable;
  final _sessions = <Window, _NativeWindowSession>{};
  final _windowsById = <int, Window>{};
  Object? _nativeCallbackError;
  StackTrace? _nativeCallbackStack;
  bool _disposed = false;

  static Future<SdlSkiaHost> initialize({
    String? libraryPath,
    bool diagnosticsEnabled = false,
  }) async {
    return SdlSkiaHost._(
      NativeBindings.open(libraryPath: libraryPath),
      diagnosticsEnabled: diagnosticsEnabled,
    );
  }

  bool isOpen(Window window) => _sessions[window]?.open ?? false;

  NativeWindowDiagnostics? diagnosticsFor(Window window) {
    if (!diagnosticsEnabled) return null;
    final session = _sessions[window];
    if (session == null || !session.open) return null;
    return using((arena) {
      final metrics = bindings.windowMetrics(session.pointer, arena);
      return NativeWindowDiagnostics(
        displayScale: metrics.displayScale,
        pixelDensity: metrics.pixelDensity,
        logicalWidth: window.logicalSize.width,
        logicalHeight: window.logicalSize.height,
        physicalWidth: metrics.physicalWidth,
        physicalHeight: metrics.physicalHeight,
        scheduledFrameCount: window.scheduledFrameCount,
        layoutPassCount: window.layoutPassCount,
        paintPassCount: window.paintPassCount,
        presentCount: session.presentCount,
        framesPerSecond: session.framesPerSecond,
      );
    });
  }

  @override
  Future<void> showWindow(Window window) async {
    _checkNotDisposed();
    if (isOpen(window)) return;
    window.textLayoutFactory = textLayoutFactory;
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
      window.textInputHandler = this;
      window.clipboardHandler = this;
      window.setFrameRequestHandler(_wakeUp);
      await window.show();
      presentWindow(window);
    } finally {
      calloc.free(title);
    }
  }

  @override
  Future<void> closeWindow(Window window) async {
    window.close();
    _destroySession(window);
    window.textInputHandler = null;
    window.clipboardHandler = null;
    window.setFrameRequestHandler(null);
  }

  @override
  void startTextInput(Window window) {
    final session = _sessions[window];
    if (session == null || !session.open) return;
    if (bindings.windowStartTextInput(session.pointer) == 0) {
      throw StateError('Could not start SDL text input: ${bindings.lastError}');
    }
  }

  @override
  void stopTextInput(Window window) {
    final session = _sessions[window];
    if (session == null || !session.open) return;
    if (bindings.windowStopTextInput(session.pointer) == 0) {
      throw StateError('Could not stop SDL text input: ${bindings.lastError}');
    }
  }

  bool isTextInputActive(Window window) {
    final session = _sessions[window];
    if (session == null || !session.open) return false;
    final result = bindings.windowTextInputActive(session.pointer);
    if (result < 0) {
      throw StateError('Could not query SDL text input: ${bindings.lastError}');
    }
    return result == 1;
  }

  @override
  void setTextInputArea(Window window, Rect area, double cursorX) {
    final session = _sessions[window];
    if (session == null || !session.open) return;
    if (bindings.windowSetTextInputArea(
          session.pointer,
          area.left,
          area.top,
          area.width,
          area.height,
          cursorX,
        ) ==
        0) {
      throw StateError(
          'Could not set SDL text input area: ${bindings.lastError}');
    }
  }

  @override
  String? readClipboardText() => bindings.readClipboardText();

  @override
  bool writeClipboardText(String text) => bindings.writeClipboardText(text);

  void pumpEvents() {
    _checkNotDisposed();
    _throwNativeCallbackError();
    using((arena) {
      while (true) {
        final event = bindings.nextEvent(_host, arena);
        if (event == null) break;
        _dispatchEvent(event);
      }
    });
    _throwNativeCallbackError();
  }

  /// Waits for SDL input while periodically returning control to Dart timers.
  void waitForEvent(
    Window window, {
    Duration timeout = const Duration(milliseconds: 16),
  }) {
    _checkNotDisposed();
    _throwNativeCallbackError();
    if (!isOpen(window) || window.frameScheduled) return;
    final timeoutMs = timeout.inMilliseconds;
    if (timeoutMs < -1) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be -1 or greater.');
    }
    using((arena) {
      final event = bindings.waitEvent(_host, arena, timeoutMs: timeoutMs);
      if (event != null) _dispatchEvent(event);
    });
    _throwNativeCallbackError();
  }

  void _wakeUp() {
    if (!_disposed) bindings.wakeUp(_host);
  }

  void presentWindow(Window window) {
    _checkNotDisposed();
    _throwNativeCallbackError();
    final session = _sessions[window];
    if (session == null ||
        !session.open ||
        !window.isVisible ||
        !window.frameScheduled) {
      return;
    }
    window.updateDevicePixelRatio(
      bindings.windowGetContentScale(session.pointer),
    );
    bindings.windowSetBackground(session.pointer, window.background.value);
    if (bindings.windowBeginFrame(session.pointer) == 0) {
      throw StateError('Could not begin native frame: ${bindings.lastError}');
    }
    try {
      final context = NativeDrawingContext(bindings, session.pointer);
      window.renderFrame(context);
      if (diagnosticsEnabled) {
        session.sampleFrameRate();
        _drawFrameRateOverlay(window, session, context);
      }
    } finally {
      if (bindings.windowPresent(session.pointer) == 0) {
        throw StateError(
            'Could not present native frame: ${bindings.lastError}');
      }
      session.presentCount++;
    }
  }

  void _drawFrameRateOverlay(
    Window window,
    _NativeWindowSession session,
    DrawingContext context,
  ) {
    final windowWidth = window.logicalSize.width;
    context.drawRect(
      Rect.fromLTWH(windowWidth - 104, 8, 96, 26),
      const Paint(Color(0xCC000000)),
    );
    context.drawText(
      session.frameRateLabel,
      Point(windowWidth - 16, 13),
      fontSize: 12,
      color: Color.white,
      alignment: TextAlignment.end,
    );
  }

  void _handleLiveResize(
    Pointer<Void> userData,
    int windowId,
    double width,
    double height,
  ) {
    if (_disposed) return;
    final window = _windowsById[windowId];
    if (window == null || !isOpen(window)) return;
    try {
      window.resize(width, height);
      // Live expose can repeat the current size but still requires a frame.
      window.requestFrame();
      presentWindow(window);
    } catch (error, stackTrace) {
      // Dart exceptions must not unwind through the SDL C callback.
      _nativeCallbackError ??= error;
      _nativeCallbackStack ??= stackTrace;
    }
  }

  void _throwNativeCallbackError() {
    final error = _nativeCallbackError;
    if (error == null) return;
    final stackTrace = _nativeCallbackStack ?? StackTrace.current;
    _nativeCallbackError = null;
    _nativeCallbackStack = null;
    Error.throwWithStackTrace(error, stackTrace);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    bindings.hostSetLiveResizeCallback(_host, nullptr, nullptr);
    for (final window in _sessions.keys.toList()) {
      _closeSession(window);
    }
    bindings.hostDestroy(_host);
    _liveResizeCallable.close();
  }

  void _dispatchEvent(NativeEvent event) {
    if (event.type == 1) {
      for (final window in _sessions.keys.toList()) {
        _closeSession(window);
      }
      return;
    }

    final window = _windowsById[event.windowId];
    if (window == null || !isOpen(window)) return;
    switch (event.type) {
      case 2:
        _closeSession(window);
      case 3:
        window.resize(event.width, event.height);
      case 4:
        window.dispatchPointerDown(
          Point(event.x, event.y),
          button: _pointerButton(event.keyCode),
        );
      case 5:
        window.dispatchPointerUp(
          Point(event.x, event.y),
          button: _pointerButton(event.keyCode),
        );
      case 6:
        window.dispatchPointerMove(Point(event.x, event.y));
      case 7:
        final text = event.text;
        if (text != null) window.dispatchTextInput(text);
      case 8:
        window.dispatchKeyDown(
          _keyName(event.keyCode),
          shiftPressed: event.modifiers & 0x0003 != 0,
          controlPressed: event.modifiers & 0x00C0 != 0,
          metaPressed: event.modifiers & 0x0C00 != 0,
          physicalKeyCode: event.scanCode,
          logicalKeyCode: event.keyCode,
        );
      case 9:
        final text = event.text;
        if (text != null) {
          window.dispatchTextEditing(
            text,
            compositionStart: event.compositionStart,
            compositionLength: event.compositionLength,
          );
        }
    }
  }

  void _closeSession(Window window) {
    window.close();
    _destroySession(window);
    window.textInputHandler = null;
    window.clipboardHandler = null;
    window.setFrameRequestHandler(null);
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

PointerButton _pointerButton(int button) => switch (button) {
      2 => PointerButton.middle,
      3 => PointerButton.secondary,
      _ => PointerButton.primary,
    };

String _keyName(int keyCode) => switch (keyCode) {
      0x00000008 => 'backspace',
      0x00000009 => 'tab',
      0x0000000D => 'enter',
      0x00000020 => 'space',
      0x00000061 => 'a',
      0x00000063 => 'c',
      0x00000076 => 'v',
      0x00000078 => 'x',
      0x0000007F => 'delete',
      0x4000004A => 'home',
      0x4000004D => 'end',
      0x4000004F => 'right',
      0x40000050 => 'left',
      _ => keyCode.toString(),
    };

final class NativeDrawingContext implements NativeTextDrawingContext {
  NativeDrawingContext(this.bindings, this.window);

  final NativeBindings bindings;
  @override
  final Pointer<DuiWindowOpaque> window;

  @override
  void pushClipRect(Rect rect) {
    bindings.pushClipRect(
      window,
      rect.left,
      rect.top,
      rect.width,
      rect.height,
    );
  }

  @override
  void popClip() => bindings.popClip(window);

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
