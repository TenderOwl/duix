// Loads the native library the way a packaged application does.
//
// The library has to be found next to the executable, so the program is
// started from another working directory by tools/package.py. The shaped text
// proves that the ICU data file was found next to the library as well: the
// Unicode stack of Skia reads it at runtime.
import 'package:duix/src/native/native_bindings.dart';
import 'package:ffi/ffi.dart';

void main() {
  final bindings = NativeBindings.open();
  final abi = bindings.abiVersion();
  if (abi != 3) {
    throw StateError('Unexpected ABI version $abi.');
  }

  final arena = Arena();
  try {
    final layout = bindings.textLayoutCreate(
      text: 'Привет, 世界',
      fontSize: 16,
      maxWidth: 1000,
      scale: 1,
      arena: arena,
    );
    final metrics = bindings.textLayoutMeasure(layout, arena);
    bindings.textLayoutDestroy(layout);
    if (metrics.width <= 0) {
      throw StateError('The text layout of the bundle has no width.');
    }
    print(
      'dui_native ABI $abi loaded from the bundle, '
      'shaped width ${metrics.width.toStringAsFixed(1)}.',
    );
  } finally {
    arena.releaseAll();
  }
}
