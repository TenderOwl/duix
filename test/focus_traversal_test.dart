import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('Tab traversal', () {
    test('follows logical tree order and wraps in both directions', () {
      final first = Button();
      final second = TextBox();
      final third = Button();
      final fourth = TextBox();
      final window = Window(
        content: StackPanel(
          children: [
            first,
            StackPanel(children: [second, third]),
            fourth,
          ],
        ),
      );

      window.dispatchKeyDown('tab');
      expect(window.focusedElement, same(first));
      window.dispatchKeyDown('tab');
      expect(window.focusedElement, same(second));
      window.dispatchKeyDown('tab');
      expect(window.focusedElement, same(third));
      window.dispatchKeyDown('tab');
      expect(window.focusedElement, same(fourth));
      window.dispatchKeyDown('tab');
      expect(window.focusedElement, same(first));

      window.dispatchKeyDown('tab', shiftPressed: true);
      expect(window.focusedElement, same(fourth));
    });

    test('skips non-focusable, disabled, invisible and hidden branches', () {
      final first = Button();
      final hiddenChild = Button();
      final last = Button();
      final window = Window(
        content: StackPanel(
          children: [
            TextBlock(text: 'not focusable'),
            Button()..isEnabled = false,
            Button()..isVisible = false,
            StackPanel(children: [hiddenChild])..isVisible = false,
            first,
            last,
          ],
        ),
      );

      window.dispatchKeyDown('tab');
      expect(window.focusedElement, same(first));
      window.dispatchKeyDown('tab');
      expect(window.focusedElement, same(last));
      window.dispatchKeyDown('tab');
      expect(window.focusedElement, same(first));
    });

    test('does nothing when no control can receive focus', () {
      final window = Window(
        content: StackPanel(
          children: [TextBlock(text: 'label'), Button()..isEnabled = false],
        ),
      );

      window.dispatchKeyDown('tab');
      window.dispatchKeyDown('tab', shiftPressed: true);

      expect(window.focusedElement, isNull);
    });

    test('handled key down cancels automatic traversal', () {
      final first = TextBox();
      final second = TextBox();
      final window = Window(content: StackPanel(children: [first, second]));
      first.focus();
      first.addHandler(UIElement.keyDown, (sender, args) {
        if (args.key == 'tab' && !args.shiftPressed) args.handled = true;
      });

      window.dispatchKeyDown('tab');

      expect(window.focusedElement, same(first));
      window.dispatchKeyDown('tab', shiftPressed: true);
      expect(window.focusedElement, same(second));
    });

    test('nearest focus scope contains forward and backward traversal', () {
      final outsideBefore = Button();
      final first = Button();
      final second = TextBox();
      final outsideAfter = Button();
      final scope = StackPanel(
        isFocusScope: true,
        children: [first, second],
      );
      final window = Window(
        content: StackPanel(
          children: [outsideBefore, scope, outsideAfter],
        ),
      );
      first.focus();

      window.dispatchKeyDown('tab');
      expect(window.focusedElement, same(second));
      window.dispatchKeyDown('tab');
      expect(window.focusedElement, same(first));
      window.dispatchKeyDown('tab', shiftPressed: true);
      expect(window.focusedElement, same(second));
    });

    test('nested scope takes precedence over an outer scope', () {
      final outer = Button();
      final innerFirst = Button();
      final innerSecond = Button();
      final inner = StackPanel(
        isFocusScope: true,
        children: [innerFirst, innerSecond],
      );
      final window = Window(
        content: StackPanel(
          isFocusScope: true,
          children: [outer, inner],
        ),
      );
      innerFirst.focus();

      window.dispatchKeyDown('tab');
      expect(window.focusedElement, same(innerSecond));
      window.dispatchKeyDown('tab');
      expect(window.focusedElement, same(innerFirst));
    });

    test('control and meta Tab do not trigger focus traversal', () {
      final first = TextBox();
      final second = TextBox();
      final window = Window(content: StackPanel(children: [first, second]));
      first.focus();

      window.dispatchKeyDown('tab', controlPressed: true);
      expect(window.focusedElement, same(first));
      window.dispatchKeyDown('tab', metaPressed: true);
      expect(window.focusedElement, same(first));
    });
  });
}
