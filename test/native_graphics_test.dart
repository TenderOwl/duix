@Tags(['native'])
library;

import 'dart:ffi';

import 'package:duix/src/native/native_bindings.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

void main() {
  late NativeBindings bindings;

  setUpAll(() {
    bindings = NativeBindings.open();
  });

  test('a path with a shadow is drawn into a frame', () {
    final host = bindings.hostCreate();
    expect(host, isNot(nullptr), reason: bindings.lastError);
    var window = nullptr.cast<DuiWindowOpaque>();
    final commands = calloc<DuiPathCommandStruct>(4);
    final paint = calloc<DuiPaintStruct>();
    try {
      window =
          bindings.windowCreate(host, 'Graphics ABI'.toNativeUtf8(), 160, 80);
      expect(window, isNot(nullptr), reason: bindings.lastError);

      commands[0]
        ..operation = 0
        ..x1 = 8
        ..y1 = 8;
      commands[1]
        ..operation = 1
        ..x1 = 120
        ..y1 = 20;
      commands[2]
        ..operation = 2
        ..x1 = 80
        ..y1 = 60
        ..x2 = 40
        ..y2 = 60;
      commands[3].operation = 4;

      paint.ref
        ..structSize = sizeOf<DuiPaintStruct>()
        ..rgba = 0xAA3584E4
        ..strokeWidth = 0
        ..opacity = 0.75
        ..blendMode = 2
        ..shadowRgba = 0x80000000
        ..shadowBlur = 6
        ..shadowDx = 2
        ..shadowDy = 4;

      expect(bindings.windowBeginFrame(window), 1, reason: bindings.lastError);
      bindings.drawPath(window, commands, 4, paint);
      expect(bindings.windowPresent(window), 1, reason: bindings.lastError);
    } finally {
      calloc.free(commands);
      calloc.free(paint);
      bindings.windowDestroy(host, window);
      bindings.hostDestroy(host);
    }
  });

  test('an empty path draws nothing and does not fail', () {
    final host = bindings.hostCreate();
    expect(host, isNot(nullptr), reason: bindings.lastError);
    var window = nullptr.cast<DuiWindowOpaque>();
    final paint = calloc<DuiPaintStruct>();
    try {
      window = bindings.windowCreate(host, 'Empty path'.toNativeUtf8(), 80, 60);
      expect(window, isNot(nullptr), reason: bindings.lastError);
      paint.ref
        ..structSize = sizeOf<DuiPaintStruct>()
        ..rgba = 0xFFFFFFFF
        ..opacity = 1;

      expect(bindings.windowBeginFrame(window), 1, reason: bindings.lastError);
      bindings.drawPath(window, nullptr, 0, paint);
      expect(bindings.windowPresent(window), 1, reason: bindings.lastError);
    } finally {
      calloc.free(paint);
      bindings.windowDestroy(host, window);
      bindings.hostDestroy(host);
    }
  });
}
