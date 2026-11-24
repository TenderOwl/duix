import 'dart:ffi';

import 'package:dui_retained/src/native/native_bindings.dart';
import 'package:test/test.dart';

void main() {
  test('Dart event layout matches the 64-bit C ABI', () {
    expect(sizeOf<DuiEventStruct>(), 64);
  });

  test('native library candidates exist for the current desktop', () {
    expect(NativeBindings.defaultLibraryCandidates, isNotEmpty);
  });
}
