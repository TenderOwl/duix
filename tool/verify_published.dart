// Loads the native library of the assembled distribution.
//
// The script points the loader at the library of the distribution folder, so
// it proves that the published package carries a working library and not only
// a file of the right name.
import 'package:duix/src/native/native_bindings.dart';
import 'package:ffi/ffi.dart';

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    throw ArgumentError('The path of the library is required.');
  }
  final library = NativeBindings.open(libraryPath: arguments.first);
  final abi = library.abiVersion();
  if (abi != 6) {
    throw StateError('Unexpected ABI version $abi.');
  }

  final arena = Arena();
  try {
    final layout = library.textLayoutCreate(
      text: 'Привет, 世界',
      fontSize: 16,
      maxWidth: 1000,
      scale: 1,
      arena: arena,
    );
    final metrics = library.textLayoutMeasure(layout, arena);
    library.textLayoutDestroy(layout);
    if (metrics.width <= 0) {
      throw StateError('The text layout of the package has no width.');
    }
    print(
      'dui_native ABI $abi loaded from ${library.libraryPath}, '
      'shaped width ${metrics.width.toStringAsFixed(1)}.',
    );
  } finally {
    arena.releaseAll();
  }
}
