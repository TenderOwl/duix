import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('FocusManager', () {
    test('moves focus between mounted controls and preserves the public API',
        () {
      final first = Button();
      final second = TextBox();
      final window = Window(
        content: StackPanel(children: [first, second]),
      );

      expect(first.focus(), isTrue);
      expect(window.focusedElement, same(first));
      expect(window.focusManager.focusedElement, same(first));
      expect(first.isFocused, isTrue);

      expect(second.focus(), isTrue);
      expect(window.focusedElement, same(second));
      expect(first.isFocused, isFalse);
      expect(second.isFocused, isTrue);
    });

    test('rejects non-focusable, disabled, invisible and unmounted controls',
        () {
      final disabled = Button()..isEnabled = false;
      final invisible = Button()..isVisible = false;
      final text = TextBlock(text: 'not focusable');
      final window = Window(
        content: StackPanel(children: [disabled, invisible, text]),
      );

      expect(disabled.focus(), isFalse);
      expect(invisible.focus(), isFalse);
      expect(text.focus(), isFalse);
      expect(Button().focus(), isFalse);
      expect(window.focusedElement, isNull);
    });

    test('clears focus when the focused control unmounts', () {
      final box = TextBox();
      final window = Window(content: box);
      box.focus();

      window.content = null;

      expect(window.focusedElement, isNull);
      expect(box.isFocused, isFalse);
      expect(box.isMounted, isFalse);

      window.content = box;
      expect(window.focusedElement, isNull);
      expect(box.isFocused, isFalse);
      expect(box.focus(), isTrue);
    });

    test('clears focus when a control becomes disabled or invisible', () {
      final box = TextBox();
      final window = Window(content: box);
      box.focus();

      box.isEnabled = false;
      expect(window.focusedElement, isNull);
      expect(box.isFocused, isFalse);

      box.isEnabled = true;
      expect(box.focus(), isTrue);
      box.isVisible = false;
      expect(window.focusedElement, isNull);
      expect(box.isFocused, isFalse);
    });

    test('clears descendant focus when a parent becomes unavailable', () {
      final box = TextBox();
      final panel = StackPanel(children: [box]);
      final window = Window(content: panel);
      box.focus();

      panel.isVisible = false;

      expect(window.focusedElement, isNull);
      expect(box.isFocused, isFalse);
      expect(box.focus(), isFalse);
    });
  });
}
