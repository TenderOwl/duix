// ignore_for_file: library_private_types_in_public_api

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class DuiHostOpaque extends Opaque {}

final class DuiWindowOpaque extends Opaque {}

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

  external Pointer<Utf8> textUtf8;
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
    required this.text,
  });

  final int type;
  final int windowId;
  final double x;
  final double y;
  final double width;
  final double height;
  final int keyCode;
  final String? text;
}

typedef _AbiVersionNative = Uint32 Function();
typedef _LastErrorNative = Pointer<Utf8> Function();
typedef _HostCreateNative = Pointer<DuiHostOpaque> Function();
typedef _HostDestroyNative = Void Function(Pointer<DuiHostOpaque>);
typedef _HostNextEventNative = Int32 Function(
  Pointer<DuiHostOpaque>,
  Pointer<DuiEventStruct>,
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
typedef _WindowIdNative = Uint64 Function(Pointer<DuiWindowOpaque>);
typedef _WindowBackgroundNative = Void Function(
  Pointer<DuiWindowOpaque>,
  Uint32,
);
typedef _FrameNative = Int32 Function(Pointer<DuiWindowOpaque>);
typedef _DrawRectNative = Void Function(
  Pointer<DuiWindowOpaque>,
  Double,
  Double,
  Double,
  Double,
  Uint32,
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

typedef _AbiVersionDart = int Function();
typedef _LastErrorDart = Pointer<Utf8> Function();
typedef _HostCreateDart = Pointer<DuiHostOpaque> Function();
typedef _HostDestroyDart = void Function(Pointer<DuiHostOpaque>);
typedef _HostNextEventDart = int Function(
  Pointer<DuiHostOpaque>,
  Pointer<DuiEventStruct>,
);
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
typedef _WindowIdDart = int Function(Pointer<DuiWindowOpaque>);
typedef _WindowBackgroundDart = void Function(Pointer<DuiWindowOpaque>, int);
typedef _FrameDart = int Function(Pointer<DuiWindowOpaque>);
typedef _DrawRectDart = void Function(
  Pointer<DuiWindowOpaque>,
  double,
  double,
  double,
  double,
  int,
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

final class NativeBindings {
  NativeBindings._(DynamicLibrary library)
      : abiVersion = library.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
          'dui_abi_version',
        ),
        _lastError = library.lookupFunction<_LastErrorNative, _LastErrorDart>(
          'dui_last_error_message',
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
        windowCreate =
            library.lookupFunction<_WindowCreateNative, _WindowCreateDart>(
          'dui_window_create',
        ),
        windowDestroy =
            library.lookupFunction<_WindowDestroyNative, _WindowDestroyDart>(
          'dui_window_destroy',
        ),
        windowGetId = library.lookupFunction<_WindowIdNative, _WindowIdDart>(
          'dui_window_get_id',
        ),
        windowSetBackground = library
            .lookupFunction<_WindowBackgroundNative, _WindowBackgroundDart>(
          'dui_window_set_background',
        ),
        windowBeginFrame = library.lookupFunction<_FrameNative, _FrameDart>(
          'dui_window_begin_frame',
        ),
        drawRect = library.lookupFunction<_DrawRectNative, _DrawRectDart>(
          'dui_draw_rect',
        ),
        drawText = library.lookupFunction<_DrawTextNative, _DrawTextDart>(
          'dui_draw_text',
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
  final _HostCreateDart hostCreate;
  final _HostDestroyDart hostDestroy;
  final _HostNextEventDart hostNextEvent;
  final _WindowCreateDart windowCreate;
  final _WindowDestroyDart windowDestroy;
  final _WindowIdDart windowGetId;
  final _WindowBackgroundDart windowSetBackground;
  final _FrameDart windowBeginFrame;
  final _DrawRectDart drawRect;
  final _DrawTextDart drawText;
  final _FrameDart windowPresent;

  String get lastError {
    final pointer = _lastError();
    return pointer == nullptr
        ? 'Unknown native error.'
        : pointer.toDartString();
  }

  NativeEvent? nextEvent(Pointer<DuiHostOpaque> host, Arena arena) {
    final event = arena<DuiEventStruct>();
    final result = hostNextEvent(host, event);
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
      text: value.textUtf8 == nullptr ? null : value.textUtf8.toDartString(),
    );
  }

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
