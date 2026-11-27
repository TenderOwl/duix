@Tags(['native'])
library;

import 'dart:async';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';
import 'package:test/test.dart';

void main() {
  late SdlSkiaHost host;

  setUpAll(() async {
    host = await SdlSkiaHost.initialize();
  });

  tearDownAll(() {
    host.dispose();
  });

  test('the event loop ends with the window', () async {
    final window = Window(
      width: 320,
      height: 200,
      content: Label(text: 'Event loop'),
    );
    var timerFired = false;

    final loop = host.runWindow(window);
    Timer(const Duration(milliseconds: 50), () {
      timerFired = true;
      host.closeWindow(window);
    });

    await loop;

    expect(
      timerFired,
      isTrue,
      reason: 'the loop has to give the Dart event loop a chance to run',
    );
    expect(host.isOpen(window), isFalse);
  });

  test('the event loop paints the frames of the window', () async {
    final label = Label(text: 'Frames');
    final window = Window(width: 320, height: 200, content: label);

    final loop = host.runWindow(window);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await host.closeWindow(window);
    await loop;

    expect(label.desiredSize.width, greaterThan(0));
    expect(window.paintPassCount, greaterThan(0));
  });
}
