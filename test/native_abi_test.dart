import 'dart:ffi';

import 'package:duix/src/native/native_bindings.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

void main() {
  late NativeBindings bindings;

  setUpAll(() {
    bindings = NativeBindings.open();
  });

  test('ABI version is supported', () {
    expect(bindings.abiVersion(), 1);
  });

  test('host can be created and destroyed repeatedly', () {
    for (var iteration = 0; iteration < 2; iteration++) {
      final host = bindings.hostCreate();
      expect(host, isNot(nullptr), reason: bindings.lastError);
      bindings.hostDestroy(host);
    }
  });

  test('null event arguments return an error', () {
    using((arena) {
      final event = arena<DuiEventStruct>();
      expect(bindings.hostNextEvent(nullptr, event), -1);
      expect(bindings.lastError, contains('Invalid event arguments'));
    });
  });

  test('null frame and metrics arguments return errors', () {
    expect(bindings.windowBeginFrame(nullptr), 0);
    expect(bindings.lastError, isNotEmpty);
    expect(bindings.windowPresent(nullptr), 0);
    expect(bindings.lastError, contains('No active frame'));

    using((arena) {
      expect(
        () => bindings.windowMetrics(nullptr, arena),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Invalid window metrics arguments'),
          ),
        ),
      );
    });
  });

  test('null destruction arguments are ignored', () {
    expect(() => bindings.hostDestroy(nullptr), returnsNormally);
    expect(() => bindings.windowDestroy(nullptr, nullptr), returnsNormally);
  });
}
