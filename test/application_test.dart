import 'dart:async';

import 'package:duix/dui.dart';
import 'package:test/test.dart';

/// A host that only records what the application asks of it.
final class _RecordingHost implements NativeHost {
  int shown = 0;
  int closed = 0;
  int run = 0;
  Completer<void>? gate;

  @override
  Future<void> showWindow(Window window) async {
    shown++;
    await window.show();
  }

  @override
  Future<void> closeWindow(Window window) async {
    closed++;
    window.close();
  }

  @override
  Future<void> runWindow(Window window) async {
    run++;
    await showWindow(window);
    await gate?.future;
  }
}

void main() {
  test('the application shows the window and runs it', () async {
    final host = _RecordingHost();
    final application = Application(host: host);
    final window = Window(
      width: 320,
      height: 200,
      content: Label(text: 'Application'),
    );

    await application.run(window);

    expect(host.run, 1);
    expect(host.shown, 1);
    expect(host.closed, 0);
    expect(window.isVisible, isTrue);
  });

  test('the shutdown closes the window', () async {
    final host = _RecordingHost();
    final application = Application(host: host);
    final window = Window(
      width: 320,
      height: 200,
      content: Label(text: 'Application'),
    );

    await application.run(window);
    await application.shutdown(window);

    expect(host.closed, 1);
    expect(window.isVisible, isFalse);
  });

  test('a second run of a running application is refused', () async {
    final host = _RecordingHost()..gate = Completer<void>();
    final application = Application(host: host);
    final window = Window(
      width: 320,
      height: 200,
      content: Label(text: 'Application'),
    );

    final first = application.run(window);
    await Future<void>.delayed(Duration.zero);

    await expectLater(
      application.run(window),
      throwsA(isA<StateError>()),
    );

    host.gate!.complete();
    await first;
  });
}
