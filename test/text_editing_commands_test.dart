import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('TextBox keyboard commands', () {
    test('Left and Right collapse selection to its corresponding edge', () {
      final box = TextBox(text: 'abcdef')
        ..selection = const TextSelection(baseOffset: 5, extentOffset: 2);
      final window = Window(content: box);
      box.focus();

      window.dispatchKeyDown('left');
      expect(box.selection, const TextSelection.collapsed(2));

      box.selection = const TextSelection(baseOffset: 5, extentOffset: 2);
      window.dispatchKeyDown('right');
      expect(box.selection, const TextSelection.collapsed(5));
    });

    test('Shift preserves the anchor in both selection directions', () {
      final box = TextBox(text: 'abcdef')..moveCaret(4);
      final window = Window(content: box);
      box.focus();

      window.dispatchKeyDown('left', shiftPressed: true);
      window.dispatchKeyDown('left', shiftPressed: true);
      expect(
        box.selection,
        const TextSelection(baseOffset: 4, extentOffset: 2),
      );

      window.dispatchKeyDown('right', shiftPressed: true);
      window.dispatchKeyDown('right', shiftPressed: true);
      window.dispatchKeyDown('right', shiftPressed: true);
      expect(
        box.selection,
        const TextSelection(baseOffset: 4, extentOffset: 5),
      );
    });

    test('Home and End move or extend to text boundaries', () {
      final box = TextBox(text: 'abc😀')..moveCaret(2);
      final window = Window(content: box);
      box.focus();

      window.dispatchKeyDown('home', shiftPressed: true);
      expect(
          box.selection, const TextSelection(baseOffset: 2, extentOffset: 0));
      window.dispatchKeyDown('end', shiftPressed: true);
      expect(
          box.selection, const TextSelection(baseOffset: 2, extentOffset: 5));
      window.dispatchKeyDown('home');
      expect(box.selection, const TextSelection.collapsed(0));
    });

    test('Ctrl and Cmd navigate by words without splitting Unicode', () {
      final box = TextBox(text: 'one привет😀 three')..moveCaret(0);
      final window = Window(content: box);
      box.focus();

      window.dispatchKeyDown('right', controlPressed: true);
      expect(box.caretOffset, 3);
      window.dispatchKeyDown('right', metaPressed: true);
      expect(box.caretOffset, 12);
      window.dispatchKeyDown('left', controlPressed: true);
      expect(box.caretOffset, 4);
      window.dispatchKeyDown('right', controlPressed: true, shiftPressed: true);
      expect(
          box.selection, const TextSelection(baseOffset: 4, extentOffset: 12));
      expect(box.selectedText, 'привет😀');
    });

    test('Backspace and Delete are routed editing commands', () {
      final box = TextBox(text: 'A😀B')..moveCaret(3);
      final window = Window(content: box);
      box.focus();

      window.dispatchKeyDown('backspace');
      expect(box.text, 'AB');
      window.dispatchKeyDown('delete');
      expect(box.text, 'A');
    });

    test('Select All and Copy preserve text and selection', () {
      final clipboard = _FakeClipboard();
      final box = TextBox(text: 'A😀Б');
      final window = Window(content: box)..clipboardHandler = clipboard;
      box.focus();

      window.dispatchKeyDown('a', controlPressed: true);
      window.dispatchKeyDown('c', metaPressed: true);

      expect(box.selectedText, 'A😀Б');
      expect(clipboard.text, 'A😀Б');
      expect(box.text, 'A😀Б');
      expect(
          box.selection, const TextSelection(baseOffset: 0, extentOffset: 4));
    });

    test('Cut and Paste update text, caret and two-way binding', () {
      final clipboard = _FakeClipboard();
      final source = ObservableValue<String>('abc😀def');
      final box = TextBox()
        ..bind(
          TextBox.textProperty,
          source.asBinding(),
          mode: BindingMode.twoWay,
        )
        ..selection = const TextSelection(baseOffset: 1, extentOffset: 5);
      final window = Window(content: box)..clipboardHandler = clipboard;
      box.focus();

      window.dispatchKeyDown('x', controlPressed: true);
      expect(box.text, 'adef');
      expect(source.value, 'adef');
      expect(clipboard.text, 'bc😀');
      expect(box.caretOffset, 1);

      window.dispatchKeyDown('v', metaPressed: true);
      expect(box.text, 'abc😀def');
      expect(source.value, 'abc😀def');
      expect(box.caretOffset, 5);
    });

    test('empty clipboard does not erase a selection', () {
      final clipboard = _FakeClipboard();
      final box = TextBox(text: 'abc')
        ..selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      final window = Window(content: box)..clipboardHandler = clipboard;
      box.focus();

      window.dispatchKeyDown('v', controlPressed: true);
      expect(box.text, 'abc');
      expect(box.selectedText, 'abc');
    });

    test('unrecognized and unmodified shortcut keys remain unhandled', () {
      final box = TextBox(text: 'abc');
      final window = Window(content: box);
      final unhandled = <String>[];
      box.addHandler(UIElement.keyDown, (sender, args) {
        unhandled.add(args.key);
      });
      box.focus();

      window.dispatchKeyDown('a');
      window.dispatchKeyDown('unknown');
      expect(unhandled, ['a', 'unknown']);
      expect(box.text, 'abc');
      expect(box.selection.isCollapsed, isTrue);
    });
  });
}

final class _FakeClipboard implements ClipboardHandler {
  String? text;

  @override
  String? readClipboardText() => text;

  @override
  bool writeClipboardText(String text) {
    this.text = text;
    return true;
  }
}
