import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../image.dart';
import 'native_bindings.dart';

/// Decodes images with the native backend.
///
/// The backend reads the pixels with Skia, so a PNG is decoded by the same
/// library that draws it.
final class NativeImageFactory implements ImageFactory {
  const NativeImageFactory(this.bindings);

  final NativeBindings bindings;

  @override
  DrawableImage decodePng(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw StateError('The image data is empty.');
    }
    final handle = bindings.imageCreateFromPng(bytes);
    if (handle == nullptr) {
      throw StateError(
        'Could not decode the PNG image: ${bindings.lastError}',
      );
    }
    final size = using((arena) => bindings.imageGetSize(handle, arena));
    return NativeImage._(bindings, handle, size.width, size.height);
  }
}

/// A decoded PNG image of the native backend.
final class NativeImage implements DrawableImage {
  NativeImage._(
    this.bindings,
    this.handle,
    this._width,
    this._height,
  );

  final NativeBindings bindings;

  /// The native handle of the decoded image.
  final Pointer<DuiImageOpaque> handle;

  final double _width;
  final double _height;
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
  bool get isDisposed => _isDisposed;

  @override
  void dispose() {
    if (_isDisposed) return;
    bindings.imageDestroy(handle);
    _isDisposed = true;
  }

  void _checkNotDisposed() {
    if (_isDisposed) throw StateError('The image is disposed.');
  }
}
