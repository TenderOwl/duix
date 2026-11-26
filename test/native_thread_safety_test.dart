@Tags(['native'])
library;

import 'dart:isolate';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';
import 'package:test/test.dart';

/// Creates a native host, renders a frame and releases the host again.
///
/// The host is kept alive for a while, so two isolates that run at the same
/// time really compete for it.
Future<String> _driveWindow(String title) async {
  try {
    final host = await SdlSkiaHost.initialize();
    final window = Window(
      width: 240,
      height: 160,
      content: Label(text: title),
    );
    await host.showWindow(window);
    host.pumpEvents();
    host.presentWindow(window);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await host.closeWindow(window);
    host.dispose();
    return 'ok';
  } catch (error) {
    return '$error';
  }
}

/// Shapes a text without a window, which uses the shared font collection.
String _shapeText() {
  try {
    final bindings = NativeBindings.open();
    final factory = NativeTextLayoutFactory(bindings);
    for (var index = 0; index < 20; index++) {
      final layout = factory.create(TextLayoutOptions(
        text: 'Строка $index — Привет, 世界',
        fontSize: 16,
        maxWidth: 320,
        scale: 1.5,
      ));
      try {
        if (layout.width <= 0) return 'empty layout';
      } finally {
        layout.dispose();
      }
    }
    return 'ok';
  } catch (error) {
    return '$error';
  }
}

void main() {
  test('two isolates compete for the native host without crashing', () async {
    final results = await Future.wait([
      Isolate.run(() => _driveWindow('first isolate')),
      Isolate.run(() => _driveWindow('second isolate')),
    ]);

    final winners = results.where((result) => result == 'ok').toList();
    expect(winners, hasLength(1), reason: 'results: $results');

    final loser = results.firstWhere((result) => result != 'ok');
    expect(
      loser,
      contains('Only one native host per process'),
      reason: 'the second isolate has to fail with a clear message',
    );
  });

  test('the native host is available again after it was released', () async {
    final host = await SdlSkiaHost.initialize();
    host.dispose();

    expect(await Isolate.run(() => _driveWindow('after release')), 'ok');
  });

  test('several isolates shape text at the same time', () async {
    final results = await Future.wait([
      Isolate.run(() => _shapeText()),
      Isolate.run(() => _shapeText()),
    ]);

    expect(results, everyElement('ok'), reason: 'results: $results');
  });
}
