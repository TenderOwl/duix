@Tags(['native'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:duix/src/native/native_bindings.dart';
import 'package:duix/src/native/native_image.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

/// A 4x3 PNG image with a gradient.
final _png = base64.decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAIAAAA7ljmRAAAAKklEQVR4nA3HMQEAMAzDMAM'
  'riMDpaSgBUYCbPgEOLh5CnLjx8lOnbr36AOO3DflsbMvSAAAAAElFTkSuQmCC',
);

void main() {
  late NativeBindings bindings;

  setUpAll(() {
    bindings = NativeBindings.open();
  });

  test('a PNG image is decoded with its pixel size', () {
    final image = NativeImageFactory(bindings).decodePng(_png);

    expect(image.width, 4);
    expect(image.height, 3);
    expect(image.isDisposed, isFalse);

    image.dispose();
    expect(image.isDisposed, isTrue);
    expect(() => image.width, throwsStateError);
  });

  test('bytes that are not a PNG are rejected', () {
    final factory = NativeImageFactory(bindings);

    expect(
      () => factory.decodePng(Uint8List.fromList([1, 2, 3, 4])),
      throwsStateError,
    );
    expect(() => factory.decodePng(Uint8List(0)), throwsStateError);
  });

  test('an image is drawn into a frame', () {
    final host = bindings.hostCreate();
    expect(host, isNot(nullptr), reason: bindings.lastError);
    var window = nullptr.cast<DuiWindowOpaque>();
    try {
      window = bindings.windowCreate(host, 'Image ABI'.toNativeUtf8(), 160, 80);
      expect(window, isNot(nullptr), reason: bindings.lastError);
      final image = NativeImageFactory(bindings).decodePng(_png) as NativeImage;
      final paint = calloc<DuiPaintStruct>();
      paint.ref
        ..structSize = sizeOf<DuiPaintStruct>()
        ..rgba = 0xFFFFFFFF
        ..opacity = 1;
      try {
        expect(bindings.windowBeginFrame(window), 1,
            reason: bindings.lastError);
        bindings.drawImage(window, image.handle, 4, 4, 0, 0, paint);
        bindings.drawImage(window, image.handle, 8, 8, 32, 24, paint);
        expect(bindings.windowPresent(window), 1, reason: bindings.lastError);
      } finally {
        calloc.free(paint);
        image.dispose();
      }
    } finally {
      bindings.windowDestroy(host, window);
      bindings.hostDestroy(host);
    }
  });
}
