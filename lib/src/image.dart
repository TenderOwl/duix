import 'dart:typed_data';

/// A decoded bitmap that a widget can draw.
///
/// Implementations own their native resources. Calling [dispose] releases
/// them; all other members throw [StateError] after disposal.
abstract interface class DrawableImage {
  /// The width of the image in logical units.
  double get width;

  /// The height of the image in logical units.
  double get height;

  /// Whether the image was released.
  bool get isDisposed;

  /// Releases the image. Safe to call more than once.
  void dispose();
}

/// Decodes images from encoded bytes.
abstract interface class ImageFactory {
  /// Decodes a PNG image.
  ///
  /// Throws a [StateError] when the bytes are not a readable PNG.
  DrawableImage decodePng(Uint8List bytes);
}
