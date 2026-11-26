// ignore_for_file: library_private_types_in_public_api

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class DuiHostOpaque extends Opaque {}

final class DuiWindowOpaque extends Opaque {}

final class DuiTextLayoutOpaque extends Opaque {}

final class DuiEventStruct extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int type;

  @Uint64()
  external int windowId;

  @Double()
  external double x;

  @Double()
  external double y;

  @Double()
  external double width;

  @Double()
  external double height;

  @Int32()
  external int keyCode;

  @Uint16()
  external int modifiers;

  external Pointer<Utf8> textUtf8;

  @Int32()
  external int compositionStart;

  @Int32()
  external int compositionLength;

  @Int32()
  external int scanCode;
}

final class DuiWindowMetricsStruct extends Struct {
  @Uint32()
  external int structSize;

  @Int32()
  external int physicalWidth;

  @Int32()
  external int physicalHeight;

  @Double()
  external double displayScale;

  @Double()
  external double pixelDensity;
}

final class DuiTextLayoutOptionsStruct extends Struct {
  @Uint32()
  external int structSize;

  external Pointer<Utf8> textUtf8;

  @Size()
  external int textLength;

  external Pointer<Utf8> fontFamilyUtf8;

  @Size()
  external int fontFamilyLength;

  @Double()
  external double fontSize;

  @Double()
  external double maxWidth;

  @Double()
  external double scale;

  @Int32()
  external int alignment;
}

final class DuiTextMetricsStruct extends Struct {
  @Uint32()
  external int structSize;

  @Double()
  external double width;

  @Double()
  external double height;

  @Double()
  external double baseline;
}

final class DuiTextPositionStruct extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int offsetUtf16;
}

final class DuiRectStruct extends Struct {
  @Uint32()
  external int structSize;

  @Double()
  external double left;

  @Double()
  external double top;

  @Double()
  external double width;

  @Double()
  external double height;
}

final class NativeTextMetrics {
  const NativeTextMetrics({
    required this.width,
    required this.height,
    required this.baseline,
  });

  final double width;
  final double height;
  final double baseline;
}

final class NativeRect {
  const NativeRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

final class NativeEvent {
  const NativeEvent({
    required this.type,
    required this.windowId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.keyCode,
    required this.modifiers,
    required this.text,
    required this.compositionStart,
    required this.compositionLength,
    required this.scanCode,
  });

  final int type;
  final int windowId;
  final double x;
  final double y;
  final double width;
  final double height;
  final int keyCode;
  final int modifiers;
  final String? text;
  final int compositionStart;
  final int compositionLength;
  final int scanCode;
}

final class NativeWindowMetrics {
  const NativeWindowMetrics({
    required this.physicalWidth,
    required this.physicalHeight,
    required this.displayScale,
    required this.pixelDensity,
  });

  final int physicalWidth;
  final int physicalHeight;
  final double displayScale;
  final double pixelDensity;
}

typedef _AbiVersionNative = Uint32 Function();
typedef _LastErrorNative = Pointer<Utf8> Function();
typedef _ClipboardSetNative = Int32 Function(Pointer<Utf8>);
typedef _ClipboardGetNative = Pointer<Utf8> Function();
typedef _ClipboardFreeNative = Void Function(Pointer<Utf8>);
typedef _HostCreateNative = Pointer<DuiHostOpaque> Function();
typedef _HostDestroyNative = Void Function(Pointer<DuiHostOpaque>);
typedef _HostNextEventNative = Int32 Function(
  Pointer<DuiHostOpaque>,
  Pointer<DuiEventStruct>,
);
typedef _HostWaitEventNative = Int32 Function(
  Pointer<DuiHostOpaque>,
  Pointer<DuiEventStruct>,
  Int32,
);
typedef _HostWakeUpNative = Int32 Function(Pointer<DuiHostOpaque>);
typedef LiveResizeCallbackNative = Void Function(
  Pointer<Void>,
  Uint64,
  Double,
  Double,
);
typedef LiveResizeCallbackDart = void Function(
  Pointer<Void>,
  int,
  double,
  double,
);
typedef _HostSetLiveResizeCallbackNative = Int32 Function(
  Pointer<DuiHostOpaque>,
  Pointer<NativeFunction<LiveResizeCallbackNative>>,
  Pointer<Void>,
);
typedef _HostSetLiveResizeCallbackDart = int Function(
  Pointer<DuiHostOpaque>,
  Pointer<NativeFunction<LiveResizeCallbackNative>>,
  Pointer<Void>,
);
typedef _WindowCreateNative = Pointer<DuiWindowOpaque> Function(
  Pointer<DuiHostOpaque>,
  Pointer<Utf8>,
  Int32,
  Int32,
);
typedef _WindowDestroyNative = Void Function(
  Pointer<DuiHostOpaque>,
  Pointer<DuiWindowOpaque>,
);
typedef _WindowSetSizeNative = Int32 Function(
  Pointer<DuiWindowOpaque>,
  Int32,
  Int32,
);
typedef _WindowIdNative = Uint64 Function(Pointer<DuiWindowOpaque>);
typedef _WindowContentScaleNative = Double Function(Pointer<DuiWindowOpaque>);
typedef _WindowMetricsNative = Int32 Function(
  Pointer<DuiWindowOpaque>,
  Pointer<DuiWindowMetricsStruct>,
);
typedef _WindowBackgroundNative = Void Function(
  Pointer<DuiWindowOpaque>,
  Uint32,
);
typedef _FrameNative = Int32 Function(Pointer<DuiWindowOpaque>);
typedef _WindowPushClipNative = Int32 Function(
  Pointer<DuiWindowOpaque>,
  Double,
  Double,
  Double,
  Double,
);
typedef _DrawRectNative = Void Function(
  Pointer<DuiWindowOpaque>,
  Double,
  Double,
  Double,
  Double,
  Uint32,
);
typedef _DrawRoundedRectNative = Void Function(
  Pointer<DuiWindowOpaque>,
  Double,
  Double,
  Double,
  Double,
  Double,
  Double,
  Uint32,
  Double,
);
typedef _DrawTextNative = Void Function(
  Pointer<DuiWindowOpaque>,
  Pointer<Utf8>,
  Double,
  Double,
  Double,
  Uint32,
  Int32,
);
typedef _TextLayoutCreateNative = Pointer<DuiTextLayoutOpaque> Function(
  Pointer<DuiTextLayoutOptionsStruct>,
);
typedef _TextLayoutDestroyNative = Void Function(
  Pointer<DuiTextLayoutOpaque>,
);
typedef _TextLayoutMeasureNative = Int32 Function(
  Pointer<DuiTextLayoutOpaque>,
  Pointer<DuiTextMetricsStruct>,
);
typedef _TextLayoutDrawNative = Int32 Function(
  Pointer<DuiWindowOpaque>,
  Pointer<DuiTextLayoutOpaque>,
  Double,
  Double,
  Uint32,
);
typedef _TextLayoutHitTestNative = Int32 Function(
  Pointer<DuiTextLayoutOpaque>,
  Double,
  Double,
  Pointer<DuiTextPositionStruct>,
);
typedef _TextLayoutCaretRectNative = Int32 Function(
  Pointer<DuiTextLayoutOpaque>,
  Uint32,
  Pointer<DuiRectStruct>,
);
typedef _TextLayoutSelectionRectsNative = Int32 Function(
  Pointer<DuiTextLayoutOpaque>,
  Uint32,
  Uint32,
  Pointer<DuiRectStruct>,
  Uint32,
  Pointer<Uint32>,
);

typedef _AbiVersionDart = int Function();
typedef _LastErrorDart = Pointer<Utf8> Function();
typedef _ClipboardSetDart = int Function(Pointer<Utf8>);
typedef _ClipboardGetDart = Pointer<Utf8> Function();
typedef _ClipboardFreeDart = void Function(Pointer<Utf8>);
typedef _HostCreateDart = Pointer<DuiHostOpaque> Function();
typedef _HostDestroyDart = void Function(Pointer<DuiHostOpaque>);
typedef _HostNextEventDart = int Function(
  Pointer<DuiHostOpaque>,
  Pointer<DuiEventStruct>,
);
typedef _HostWaitEventDart = int Function(
  Pointer<DuiHostOpaque>,
  Pointer<DuiEventStruct>,
  int,
);
typedef _HostWakeUpDart = int Function(Pointer<DuiHostOpaque>);
typedef _WindowCreateDart = Pointer<DuiWindowOpaque> Function(
  Pointer<DuiHostOpaque>,
  Pointer<Utf8>,
  int,
  int,
);
typedef _WindowDestroyDart = void Function(
  Pointer<DuiHostOpaque>,
  Pointer<DuiWindowOpaque>,
);
typedef _WindowSetSizeDart = int Function(
  Pointer<DuiWindowOpaque>,
  int,
  int,
);
typedef _WindowIdDart = int Function(Pointer<DuiWindowOpaque>);
typedef _WindowContentScaleDart = double Function(Pointer<DuiWindowOpaque>);
typedef _WindowMetricsDart = int Function(
  Pointer<DuiWindowOpaque>,
  Pointer<DuiWindowMetricsStruct>,
);
typedef _WindowBackgroundDart = void Function(Pointer<DuiWindowOpaque>, int);
typedef _WindowTextInputAreaNative = Int32 Function(
  Pointer<DuiWindowOpaque>,
  Double,
  Double,
  Double,
  Double,
  Double,
);
typedef _WindowTextInputAreaDart = int Function(
  Pointer<DuiWindowOpaque>,
  double,
  double,
  double,
  double,
  double,
);
typedef _FrameDart = int Function(Pointer<DuiWindowOpaque>);
typedef _WindowPushClipDart = int Function(
  Pointer<DuiWindowOpaque>,
  double,
  double,
  double,
  double,
);
typedef _DrawRectDart = void Function(
  Pointer<DuiWindowOpaque>,
  double,
  double,
  double,
  double,
  int,
);
typedef _DrawRoundedRectDart = void Function(
  Pointer<DuiWindowOpaque>,
  double,
  double,
  double,
  double,
  double,
  double,
  int,
  double,
);
typedef _DrawTextDart = void Function(
  Pointer<DuiWindowOpaque>,
  Pointer<Utf8>,
  double,
  double,
  double,
  int,
  int,
);
typedef _TextLayoutCreateDart = Pointer<DuiTextLayoutOpaque> Function(
  Pointer<DuiTextLayoutOptionsStruct>,
);
typedef _TextLayoutDestroyDart = void Function(
  Pointer<DuiTextLayoutOpaque>,
);
typedef _TextLayoutMeasureDart = int Function(
  Pointer<DuiTextLayoutOpaque>,
  Pointer<DuiTextMetricsStruct>,
);
typedef _TextLayoutDrawDart = int Function(
  Pointer<DuiWindowOpaque>,
  Pointer<DuiTextLayoutOpaque>,
  double,
  double,
  int,
);
typedef _TextLayoutHitTestDart = int Function(
  Pointer<DuiTextLayoutOpaque>,
  double,
  double,
  Pointer<DuiTextPositionStruct>,
);
typedef _TextLayoutCaretRectDart = int Function(
  Pointer<DuiTextLayoutOpaque>,
  int,
  Pointer<DuiRectStruct>,
);
typedef _TextLayoutSelectionRectsDart = int Function(
  Pointer<DuiTextLayoutOpaque>,
  int,
  int,
  Pointer<DuiRectStruct>,
  int,
  Pointer<Uint32>,
);

final class NativeBindings {
  NativeBindings._(DynamicLibrary library)
      : abiVersion = library.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
          'dui_abi_version',
        ),
        _lastError = library.lookupFunction<_LastErrorNative, _LastErrorDart>(
          'dui_last_error_message',
        ),
        _clipboardSet =
            library.lookupFunction<_ClipboardSetNative, _ClipboardSetDart>(
          'dui_clipboard_set_text',
        ),
        _clipboardGet =
            library.lookupFunction<_ClipboardGetNative, _ClipboardGetDart>(
          'dui_clipboard_get_text',
        ),
        _clipboardFree =
            library.lookupFunction<_ClipboardFreeNative, _ClipboardFreeDart>(
          'dui_clipboard_free_text',
        ),
        hostCreate = library.lookupFunction<_HostCreateNative, _HostCreateDart>(
          'dui_host_create',
        ),
        hostDestroy =
            library.lookupFunction<_HostDestroyNative, _HostDestroyDart>(
          'dui_host_destroy',
        ),
        hostNextEvent =
            library.lookupFunction<_HostNextEventNative, _HostNextEventDart>(
          'dui_host_next_event',
        ),
        hostWaitEvent =
            library.lookupFunction<_HostWaitEventNative, _HostWaitEventDart>(
          'dui_host_wait_event',
        ),
        hostWakeUp = library.lookupFunction<_HostWakeUpNative, _HostWakeUpDart>(
          'dui_host_wake_up',
        ),
        hostSetLiveResizeCallback = library.lookupFunction<
            _HostSetLiveResizeCallbackNative, _HostSetLiveResizeCallbackDart>(
          'dui_host_set_live_resize_callback',
        ),
        windowCreate =
            library.lookupFunction<_WindowCreateNative, _WindowCreateDart>(
          'dui_window_create',
        ),
        windowDestroy =
            library.lookupFunction<_WindowDestroyNative, _WindowDestroyDart>(
          'dui_window_destroy',
        ),
        windowSetSize =
            library.lookupFunction<_WindowSetSizeNative, _WindowSetSizeDart>(
          'dui_window_set_size',
        ),
        windowGetId = library.lookupFunction<_WindowIdNative, _WindowIdDart>(
          'dui_window_get_id',
        ),
        windowGetContentScale = library
            .lookupFunction<_WindowContentScaleNative, _WindowContentScaleDart>(
          'dui_window_get_content_scale',
        ),
        _windowGetMetrics =
            library.lookupFunction<_WindowMetricsNative, _WindowMetricsDart>(
          'dui_window_get_metrics',
        ),
        windowSetBackground = library
            .lookupFunction<_WindowBackgroundNative, _WindowBackgroundDart>(
          'dui_window_set_background',
        ),
        windowStartTextInput = library.lookupFunction<_FrameNative, _FrameDart>(
          'dui_window_start_text_input',
        ),
        windowStopTextInput = library.lookupFunction<_FrameNative, _FrameDart>(
          'dui_window_stop_text_input',
        ),
        windowTextInputActive =
            library.lookupFunction<_FrameNative, _FrameDart>(
          'dui_window_text_input_active',
        ),
        windowSetTextInputArea = library.lookupFunction<
            _WindowTextInputAreaNative, _WindowTextInputAreaDart>(
          'dui_window_set_text_input_area',
        ),
        windowBeginFrame = library.lookupFunction<_FrameNative, _FrameDart>(
          'dui_window_begin_frame',
        ),
        _windowPushClip =
            library.lookupFunction<_WindowPushClipNative, _WindowPushClipDart>(
          'dui_window_push_clip_rect',
        ),
        _windowPopClip = library.lookupFunction<_FrameNative, _FrameDart>(
          'dui_window_pop_clip',
        ),
        drawRect = library.lookupFunction<_DrawRectNative, _DrawRectDart>(
          'dui_draw_rect',
        ),
        drawRoundedRect = library
            .lookupFunction<_DrawRoundedRectNative, _DrawRoundedRectDart>(
          'dui_draw_rounded_rect',
        ),
        drawText = library.lookupFunction<_DrawTextNative, _DrawTextDart>(
          'dui_draw_text',
        ),
        _textLayoutCreate = library
            .lookupFunction<_TextLayoutCreateNative, _TextLayoutCreateDart>(
          'dui_text_layout_create',
        ),
        textLayoutDestroy = library
            .lookupFunction<_TextLayoutDestroyNative, _TextLayoutDestroyDart>(
          'dui_text_layout_destroy',
        ),
        _textLayoutMeasure = library
            .lookupFunction<_TextLayoutMeasureNative, _TextLayoutMeasureDart>(
          'dui_text_layout_measure',
        ),
        _textLayoutDraw =
            library.lookupFunction<_TextLayoutDrawNative, _TextLayoutDrawDart>(
          'dui_text_layout_draw',
        ),
        _textLayoutHitTest = library
            .lookupFunction<_TextLayoutHitTestNative, _TextLayoutHitTestDart>(
          'dui_text_layout_hit_test',
        ),
        _textLayoutCaretRect = library.lookupFunction<
            _TextLayoutCaretRectNative, _TextLayoutCaretRectDart>(
          'dui_text_layout_caret_rect',
        ),
        _textLayoutSelectionRects = library.lookupFunction<
            _TextLayoutSelectionRectsNative, _TextLayoutSelectionRectsDart>(
          'dui_text_layout_selection_rects',
        ),
        windowPresent = library.lookupFunction<_FrameNative, _FrameDart>(
          'dui_window_present',
        ) {
    if (abiVersion() != 1) {
      throw StateError('Unsupported dui_native ABI version: ${abiVersion()}.');
    }
  }

  final _AbiVersionDart abiVersion;
  final _LastErrorDart _lastError;
  final _ClipboardSetDart _clipboardSet;
  final _ClipboardGetDart _clipboardGet;
  final _ClipboardFreeDart _clipboardFree;
  final _HostCreateDart hostCreate;
  final _HostDestroyDart hostDestroy;
  final _HostNextEventDart hostNextEvent;
  final _HostWaitEventDart hostWaitEvent;
  final _HostWakeUpDart hostWakeUp;
  final _HostSetLiveResizeCallbackDart hostSetLiveResizeCallback;
  final _WindowCreateDart windowCreate;
  final _WindowDestroyDart windowDestroy;
  final _WindowSetSizeDart windowSetSize;
  final _WindowIdDart windowGetId;
  final _WindowContentScaleDart windowGetContentScale;
  final _WindowMetricsDart _windowGetMetrics;
  final _WindowBackgroundDart windowSetBackground;
  final _FrameDart windowStartTextInput;
  final _FrameDart windowStopTextInput;
  final _FrameDart windowTextInputActive;
  final _WindowTextInputAreaDart windowSetTextInputArea;
  final _FrameDart windowBeginFrame;
  final _WindowPushClipDart _windowPushClip;
  final _FrameDart _windowPopClip;
  final _DrawRectDart drawRect;
  final _DrawRoundedRectDart drawRoundedRect;
  final _DrawTextDart drawText;
  final _TextLayoutCreateDart _textLayoutCreate;
  final _TextLayoutDestroyDart textLayoutDestroy;
  final _TextLayoutMeasureDart _textLayoutMeasure;
  final _TextLayoutDrawDart _textLayoutDraw;
  final _TextLayoutHitTestDart _textLayoutHitTest;
  final _TextLayoutCaretRectDart _textLayoutCaretRect;
  final _TextLayoutSelectionRectsDart _textLayoutSelectionRects;
  final _FrameDart windowPresent;

  String get lastError {
    final pointer = _lastError();
    return pointer == nullptr
        ? 'Unknown native error.'
        : pointer.toDartString();
  }

  void pushClipRect(
    Pointer<DuiWindowOpaque> window,
    double x,
    double y,
    double width,
    double height,
  ) {
    if (_windowPushClip(window, x, y, width, height) == 0) {
      throw StateError('Could not push native clip: $lastError');
    }
  }

  void popClip(Pointer<DuiWindowOpaque> window) {
    if (_windowPopClip(window) == 0) {
      throw StateError('Could not restore native clip: $lastError');
    }
  }

  bool writeClipboardText(String text) {
    final pointer = text.toNativeUtf8();
    try {
      if (_clipboardSet(pointer) == 0) {
        throw StateError('Could not write clipboard text: $lastError');
      }
      return true;
    } finally {
      calloc.free(pointer);
    }
  }

  String? readClipboardText() {
    final pointer = _clipboardGet();
    if (pointer == nullptr) return null;
    try {
      final text = pointer.toDartString();
      return text.isEmpty ? null : text;
    } finally {
      _clipboardFree(pointer);
    }
  }

  NativeWindowMetrics windowMetrics(
      Pointer<DuiWindowOpaque> window, Arena arena) {
    final metrics = arena<DuiWindowMetricsStruct>();
    if (_windowGetMetrics(window, metrics) == 0) {
      throw StateError('Could not read native window metrics: $lastError');
    }
    final value = metrics.ref;
    return NativeWindowMetrics(
      physicalWidth: value.physicalWidth,
      physicalHeight: value.physicalHeight,
      displayScale: value.displayScale,
      pixelDensity: value.pixelDensity,
    );
  }

  NativeEvent? nextEvent(Pointer<DuiHostOpaque> host, Arena arena) {
    final event = arena<DuiEventStruct>();
    final result = hostNextEvent(host, event);
    return _decodeEvent(event, result);
  }

  NativeEvent? waitEvent(
    Pointer<DuiHostOpaque> host,
    Arena arena, {
    int timeoutMs = -1,
  }) {
    final event = arena<DuiEventStruct>();
    final result = hostWaitEvent(host, event, timeoutMs);
    return _decodeEvent(event, result);
  }

  void wakeUp(Pointer<DuiHostOpaque> host) {
    if (hostWakeUp(host) == 0) {
      throw StateError('Could not wake up SDL host: $lastError');
    }
  }

  NativeEvent? _decodeEvent(Pointer<DuiEventStruct> event, int result) {
    if (result < 0) throw StateError(lastError);
    if (result == 0) return null;
    final value = event.ref;
    return NativeEvent(
      type: value.type,
      windowId: value.windowId,
      x: value.x,
      y: value.y,
      width: value.width,
      height: value.height,
      keyCode: value.keyCode,
      modifiers: value.modifiers,
      text: value.textUtf8 == nullptr ? null : value.textUtf8.toDartString(),
      compositionStart: value.compositionStart,
      compositionLength: value.compositionLength,
      scanCode: value.scanCode,
    );
  }

  Pointer<DuiTextLayoutOpaque> textLayoutCreate({
    required String text,
    required double fontSize,
    required double maxWidth,
    required double scale,
    required Arena arena,
    String? fontFamily,
    int alignment = 0,
  }) {
    final textUtf8 = text.toNativeUtf8(allocator: arena);
    final familyUtf8 = fontFamily?.toNativeUtf8(allocator: arena);
    final options = arena<DuiTextLayoutOptionsStruct>();
    final value = options.ref;
    value.structSize = sizeOf<DuiTextLayoutOptionsStruct>();
    value.textUtf8 = textUtf8;
    value.textLength = utf8.encode(text).length;
    value.fontFamilyUtf8 = familyUtf8 ?? nullptr;
    value.fontFamilyLength =
        fontFamily == null ? 0 : utf8.encode(fontFamily).length;
    value.fontSize = fontSize;
    value.maxWidth = maxWidth;
    value.scale = scale;
    value.alignment = alignment;
    final layout = _textLayoutCreate(options);
    if (layout == nullptr) {
      throw StateError('Could not create native text layout: $lastError');
    }
    return layout;
  }

  NativeTextMetrics textLayoutMeasure(
    Pointer<DuiTextLayoutOpaque> layout,
    Arena arena,
  ) {
    final metrics = arena<DuiTextMetricsStruct>();
    if (_textLayoutMeasure(layout, metrics) == 0) {
      throw StateError('Could not measure native text layout: $lastError');
    }
    final value = metrics.ref;
    return NativeTextMetrics(
      width: value.width,
      height: value.height,
      baseline: value.baseline,
    );
  }

  void textLayoutDraw(
    Pointer<DuiWindowOpaque> window,
    Pointer<DuiTextLayoutOpaque> layout,
    double x,
    double y,
    int rgba,
  ) {
    if (_textLayoutDraw(window, layout, x, y, rgba) == 0) {
      throw StateError('Could not draw native text layout: $lastError');
    }
  }

  int textLayoutHitTest(
    Pointer<DuiTextLayoutOpaque> layout,
    double x,
    double y,
    Arena arena,
  ) {
    final position = arena<DuiTextPositionStruct>();
    if (_textLayoutHitTest(layout, x, y, position) == 0) {
      throw StateError('Could not hit test native text layout: $lastError');
    }
    return position.ref.offsetUtf16;
  }

  NativeRect textLayoutCaretRect(
    Pointer<DuiTextLayoutOpaque> layout,
    int offsetUtf16,
    Arena arena,
  ) {
    final rect = arena<DuiRectStruct>();
    if (_textLayoutCaretRect(layout, offsetUtf16, rect) == 0) {
      throw StateError('Could not get native caret rectangle: $lastError');
    }
    return _nativeRect(rect.ref);
  }

  List<NativeRect> textLayoutSelectionRects(
    Pointer<DuiTextLayoutOpaque> layout,
    int startUtf16,
    int endUtf16,
    Arena arena,
  ) {
    final count = arena<Uint32>();
    if (_textLayoutSelectionRects(
          layout,
          startUtf16,
          endUtf16,
          nullptr,
          0,
          count,
        ) ==
        0) {
      throw StateError(
          'Could not count native selection rectangles: $lastError');
    }
    final requiredCount = count.value;
    if (requiredCount == 0) return const [];
    final rects = arena<DuiRectStruct>(requiredCount);
    if (_textLayoutSelectionRects(
          layout,
          startUtf16,
          endUtf16,
          rects,
          requiredCount,
          count,
        ) ==
        0) {
      throw StateError(
          'Could not read native selection rectangles: $lastError');
    }
    return List<NativeRect>.generate(
      count.value,
      (index) => _nativeRect((rects + index).ref),
      growable: false,
    );
  }

  static NativeRect _nativeRect(DuiRectStruct value) => NativeRect(
        left: value.left,
        top: value.top,
        width: value.width,
        height: value.height,
      );

  static NativeBindings open({String? libraryPath}) {
    final candidates = <String>[
      if (libraryPath != null) libraryPath,
      if (Platform.environment['DUI_NATIVE_LIBRARY'] case final path?) path,
      ...defaultLibraryCandidates,
    ];
    final errors = <String>[];
    for (final candidate in candidates) {
      try {
        return NativeBindings._(DynamicLibrary.open(candidate));
      } catch (error) {
        errors.add('$candidate: $error');
      }
    }
    throw StateError(
      'Could not load dui_native. Set DUI_NATIVE_LIBRARY or pass libraryPath.\n'
      '${errors.join('\n')}',
    );
  }

  static List<String> get defaultLibraryCandidates {
    if (Platform.isWindows) {
      return const [
        'dui_native.dll',
        'native/build/bin/dui_native.dll',
        'native/build/bin/Release/dui_native.dll',
      ];
    }
    if (Platform.isMacOS) {
      return const [
        'libdui_native.dylib',
        'native/build/bin/libdui_native.dylib',
      ];
    }
    return const [
      'libdui_native.so',
      'native/build/bin/libdui_native.so',
    ];
  }
}
