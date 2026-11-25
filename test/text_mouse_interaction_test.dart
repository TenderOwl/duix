import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('TextBox mouse interaction', () {
    test('primary click positions the caret through TextLayout', () {
      final box = TextBox(text: 'abcdef');
      final window = Window(width: 400, height: 100, content: box);

      window.dispatchPointerDown(_textPoint(3));
      window.dispatchPointerUp(_textPoint(3));

      expect(box.isFocused, isTrue);
      expect(box.selection, const TextSelection.collapsed(3));
      expect(box.hasPointerCapture, isFalse);
    });

    test('drag selects text and preserves the anchor', () {
      final source = ObservableValue<String>('abcdef');
      final box = TextBox()
        ..bind(
          TextBox.textProperty,
          source.asBinding(),
          mode: BindingMode.twoWay,
        );
      final window = Window(width: 400, height: 100, content: box);

      window.dispatchPointerDown(_textPoint(1));
      window.dispatchPointerUp(
        _textPoint(1),
        button: PointerButton.secondary,
      );
      expect(box.hasPointerCapture, isTrue);

      window.dispatchPointerMove(_textPoint(4));

      expect(box.hasPointerCapture, isTrue);
      expect(
        box.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
      expect(box.selectedText, 'bcd');
      expect(source.value, 'abcdef');

      window.dispatchPointerUp(_textPoint(4));
      expect(box.hasPointerCapture, isFalse);
    });

    test('captured drag outside the control selects backwards', () {
      final box = TextBox(text: 'abcdef');
      final window = Window(width: 400, height: 100, content: box);

      window.dispatchPointerDown(_textPoint(4));
      window.dispatchPointerMove(const Point(-100, 12));
      expect(box.hasPointerCapture, isTrue);
      window.dispatchPointerUp(const Point(-100, 12));

      expect(
        box.selection,
        const TextSelection(baseOffset: 4, extentOffset: 0),
      );
      expect(box.selectedText, 'abcd');
      expect(box.hasPointerCapture, isFalse);
    });

    test('mouse hit testing accounts for horizontal scrolling', () async {
      final box = TextBox(text: 'abcdefghijklmno');
      final window = Window(width: 80, height: 30, content: box);
      await window.show();
      expect(box.caretOffset, box.text.length);

      window.dispatchPointerDown(const Point(8, 12));
      window.dispatchPointerUp(const Point(8, 12));

      expect(box.caretOffset, greaterThan(5));
      expect(box.caretOffset, lessThan(box.text.length));
    });

    test('pointer move without drag does not change the caret', () {
      final box = TextBox(text: 'abcdef');
      final window = Window(width: 400, height: 100, content: box);
      window.dispatchPointerDown(_textPoint(2));
      window.dispatchPointerUp(_textPoint(2));

      window.dispatchPointerMove(_textPoint(5));

      expect(box.selection, const TextSelection.collapsed(2));
    });

    test('focus loss and unmount release an active pointer capture', () {
      final box = TextBox(text: 'abcdef');
      final button = Button();
      final window = Window(
        width: 400,
        height: 100,
        content: StackPanel(children: [box, button]),
      );

      window.dispatchPointerDown(_textPoint(1));
      expect(box.hasPointerCapture, isTrue);
      button.focus();
      expect(box.hasPointerCapture, isFalse);

      box.focus();
      window.dispatchPointerDown(_textPoint(1));
      expect(box.hasPointerCapture, isTrue);
      window.content = null;
      expect(box.hasPointerCapture, isFalse);
    });

    test('clicking during composition edits confirmed text only', () {
      final box = TextBox(text: 'abcdef');
      final window = Window(width: 400, height: 100, content: box);
      box.focus();
      window.dispatchTextEditing('IME');

      window.dispatchPointerDown(_textPoint(2));
      window.dispatchPointerUp(_textPoint(2));

      expect(box.hasComposition, isFalse);
      expect(box.text, 'abcdef');
      expect(box.selection, const TextSelection.collapsed(2));
    });

    test('hit testing never leaves the caret inside a surrogate pair', () {
      final box = TextBox(text: 'A😀B');
      final window = Window(width: 400, height: 100, content: box);

      window.dispatchPointerDown(_textPoint(1.6));
      window.dispatchPointerUp(_textPoint(1.6));
      expect(box.selection, const TextSelection.collapsed(1));

      window.dispatchPointerDown(_textPoint(2));
      window.dispatchPointerUp(_textPoint(2));
      expect(box.selection, const TextSelection.collapsed(3));
    });

    test('secondary click does not focus or modify selection', () {
      final box = TextBox(text: 'abcdef')..moveCaret(4);
      final window = Window(width: 400, height: 100, content: box);

      window.dispatchPointerDown(
        _textPoint(2),
        button: PointerButton.secondary,
      );
      window.dispatchPointerUp(
        _textPoint(2),
        button: PointerButton.secondary,
      );

      expect(box.isFocused, isFalse);
      expect(box.selection, const TextSelection.collapsed(4));
    });
  });
}

Point _textPoint(double characterOffset) =>
    Point(8 + characterOffset * 8.4, 12);
