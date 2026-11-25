import 'dart:ffi';

import 'package:duix/src/native/native_bindings.dart';
import 'package:duix/src/native/sdl_skia_host.dart';
import 'package:test/test.dart';

void main() {
  test('Dart event layout matches the 64-bit C ABI', () {
    expect(sizeOf<DuiEventStruct>(), 72);
  });

  test('Dart window metrics layout matches the 64-bit C ABI', () {
    expect(sizeOf<DuiWindowMetricsStruct>(), 32);
  });

  test('native library candidates exist for the current desktop', () {
    expect(NativeBindings.defaultLibraryCandidates, isNotEmpty);
  });

  test('diagnostics snapshot contains sizes, scales and frame counters', () {
    const diagnostics = NativeWindowDiagnostics(
      displayScale: 1.5,
      pixelDensity: 2,
      logicalWidth: 800,
      logicalHeight: 600,
      physicalWidth: 1600,
      physicalHeight: 1200,
      renderFrameCount: 4,
      presentCount: 4,
    );

    expect(
      diagnostics.toString(),
      'Native diagnostics: displayScale=1.5, pixelDensity=2.0, '
      'logical=800.0x600.0, physical=1600x1200, renderFrame=4, present=4',
    );
  });
}
