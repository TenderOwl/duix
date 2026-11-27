import 'package:duix/dui.dart';
import 'package:test/test.dart';

/// A button at the top left of a window, with the position of its middle.
({Window window, Button button, Point inside}) _scene() {
  final button = Button(content: Label(text: 'Go'));
  final window = Window(
    width: 400,
    height: 400,
    content: StackPanel(children: [button]),
  );
  window.updateLayout();
  return (
    window: window,
    button: button,
    inside: Point(
      button.bounds.left + button.bounds.width / 2,
      button.bounds.top + button.bounds.height / 2,
    ),
  );
}

void main() {
  group('the state of a control', () {
    test('a fresh control is enabled and nothing else', () {
      final scene = _scene();

      expect(
        scene.button.state,
        const WidgetState(
          enabled: true,
          hovered: false,
          pressed: false,
          focused: false,
        ),
      );
    });

    test('the pointer over the control makes it hovered', () {
      final scene = _scene();

      scene.window.dispatchPointerMove(scene.inside);

      expect(scene.button.state.hovered, isTrue);
    });

    test('the pointer down and up press and release the control', () {
      var clicks = 0;
      final button =
          Button(content: Label(text: 'Go'), onClick: () => clicks++);
      final window = Window(
        width: 400,
        height: 400,
        content: StackPanel(children: [button]),
      );
      window.updateLayout();
      final inside = Point(
        button.bounds.left + button.bounds.width / 2,
        button.bounds.top + button.bounds.height / 2,
      );

      window.dispatchPointerDown(inside);
      expect(button.state.pressed, isTrue);

      window.dispatchPointerUp(inside);
      expect(button.state.pressed, isFalse);
      expect(clicks, 1);
    });

    test('the pointer that leaves the control cancels the press', () {
      var clicks = 0;
      final button =
          Button(content: Label(text: 'Go'), onClick: () => clicks++);
      final window = Window(
        width: 400,
        height: 400,
        content: StackPanel(children: [button]),
      );
      window.updateLayout();
      final inside = Point(
        button.bounds.left + button.bounds.width / 2,
        button.bounds.top + button.bounds.height / 2,
      );

      window.dispatchPointerMove(inside);
      expect(button.state.hovered, isTrue);

      window.dispatchPointerDown(inside);
      expect(button.state.pressed, isTrue);

      window.dispatchPointerMove(const Point(380, 380));
      expect(button.state.hovered, isFalse);
      expect(button.state.pressed, isFalse);

      window.dispatchPointerUp(const Point(380, 380));
      expect(
        clicks,
        0,
        reason: 'a release outside the control does not activate it',
      );
    });

    test('a disabled control is never pressed', () {
      final scene = _scene();
      scene.button.isEnabled = false;

      scene.window.dispatchPointerDown(scene.inside);

      expect(scene.button.state.enabled, isFalse);
      expect(scene.button.state.pressed, isFalse);
    });

    test('the focus is part of the state', () {
      final scene = _scene();

      expect(scene.button.state.focused, isFalse);
      scene.button.focus();
      expect(scene.button.state.focused, isTrue);
    });

    test('the semantics state follows the state of the control', () {
      final scene = _scene();

      expect(scene.button.semanticsState.focused, isFalse);
      expect(scene.button.semanticsState.pressed, isFalse);
      expect(scene.button.semanticsState.disabled, isFalse);

      scene.button.focus();
      expect(scene.button.semanticsState.focused, isTrue);

      scene.button.isEnabled = false;
      expect(scene.button.semanticsState.disabled, isTrue);
    });
  });
}
