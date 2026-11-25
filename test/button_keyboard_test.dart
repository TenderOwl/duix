import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('Button keyboard activation', () {
    test('Space and Enter activate a focused Button exactly once', () {
      var clicks = 0;
      final button = Button(onClick: () => clicks++);
      final window = Window(content: button);
      button.focus();

      window.dispatchKeyDown('space');
      expect(clicks, 1);
      window.dispatchKeyDown('enter');
      expect(clicks, 2);
      window.dispatchKeyDown('a');
      window.dispatchKeyDown('space', controlPressed: true);
      expect(clicks, 2);
    });

    test('handled activation does not bubble to a parent Button', () {
      var innerClicks = 0;
      var outerClicks = 0;
      final inner = Button(onClick: () => innerClicks++);
      final outer = Button(content: inner, onClick: () => outerClicks++);
      final window = Window(content: outer);
      inner.focus();

      window.dispatchKeyDown('enter');

      expect(innerClicks, 1);
      expect(outerClicks, 0);
    });

    test('disabled Button does not activate from a routed key event', () {
      var clicks = 0;
      final button = Button(onClick: () => clicks++)..isEnabled = false;
      Window(content: button);

      button.raiseEvent(UIElement.keyDown, KeyEventArgs('enter'));

      expect(clicks, 0);
    });
  });

  test('key events expose logical and physical key codes', () {
    final button = Button();
    final window = Window(content: button);
    button.focus();
    KeyEventArgs? received;
    button.addHandler(UIElement.keyDown, (sender, args) => received = args);

    window.dispatchKeyDown(
      'b',
      physicalKeyCode: 4,
      logicalKeyCode: 98,
      shiftPressed: true,
    );

    expect(received, isNotNull);
    expect(received!.key, 'b');
    expect(received!.logicalKeyCode, 98);
    expect(received!.physicalKeyCode, 4);
    expect(received!.shiftPressed, isTrue);
  });
}
