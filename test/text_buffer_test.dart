import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('TextBuffer', () {
    test('starts with a collapsed caret at the end', () {
      final controller = TextBuffer(text: 'текст');

      expect(controller.selection, const TextSelection.collapsed(5));
      expect(controller.caretOffset, 5);
      expect(controller.selectedText, isEmpty);
    });

    test('selection preserves anchor direction and normalizes range', () {
      final controller = TextBuffer(text: 'abcdef')
        ..selection = const TextSelection(baseOffset: 5, extentOffset: 2);

      expect(controller.selection.start, 2);
      expect(controller.selection.end, 5);
      expect(controller.selection.baseOffset, 5);
      expect(controller.selectedText, 'cde');
    });

    test('inserting replaces selection and collapses the caret', () {
      final controller = TextBuffer(text: 'abcdef')
        ..selection = const TextSelection(baseOffset: 1, extentOffset: 5)
        ..insertText('XX');

      expect(controller.text, 'aXXf');
      expect(controller.selection, const TextSelection.collapsed(3));
    });

    test('external text changes clamp both selection offsets', () {
      final controller = TextBuffer(text: 'abcdef')
        ..selection = const TextSelection(baseOffset: 5, extentOffset: 2);

      controller.text = 'xy';

      expect(controller.selection, const TextSelection.collapsed(2));
    });

    test('invalid offsets and reversed ranges are rejected', () {
      final controller = TextBuffer(text: 'abc');

      expect(() => controller.moveCaret(-1), throwsRangeError);
      expect(() => controller.moveCaret(4), throwsRangeError);
      expect(
        () => controller.selection =
            const TextSelection(baseOffset: 0, extentOffset: 4),
        throwsRangeError,
      );
      expect(() => controller.replaceRange(2, 1, 'x'), throwsRangeError);
      expect(controller.text, 'abc');
    });

    test('Backspace and Delete replace a non-empty selection', () {
      final backward = TextBuffer(text: 'abcdef')
        ..selection = const TextSelection(baseOffset: 1, extentOffset: 4)
        ..deleteBackward();
      final forward = TextBuffer(text: 'abcdef')
        ..selection = const TextSelection(baseOffset: 1, extentOffset: 4)
        ..deleteForward();

      expect(backward.text, 'aef');
      expect(forward.text, 'aef');
      expect(backward.selection, const TextSelection.collapsed(1));
      expect(forward.selection, const TextSelection.collapsed(1));
    });

    test('Backspace deletes an entire surrogate pair', () {
      final controller = TextBuffer(text: 'A😀B')
        ..moveCaret(3)
        ..deleteBackward();

      expect(controller.text, 'AB');
      expect(controller.caretOffset, 1);
    });

    test('Delete removes an entire surrogate pair', () {
      final controller = TextBuffer(text: 'A😀B')
        ..moveCaret(1)
        ..deleteForward();

      expect(controller.text, 'AB');
      expect(controller.caretOffset, 1);
    });

    test('moving caret preserves anchor only when extending selection', () {
      final controller = TextBuffer(text: 'abcdef')..moveCaret(2);

      controller.moveCaret(5, extendSelection: true);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 2, extentOffset: 5),
      );
      expect(controller.selectedText, 'cde');

      controller.moveCaret(1);
      expect(controller.selection, const TextSelection.collapsed(1));
    });

    test('select all spans the complete UTF-16 text', () {
      final controller = TextBuffer(text: 'A😀Б')..selectAll();

      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 4),
      );
      expect(controller.selectedText, 'A😀Б');
    });
  });

  group('TextBox editing integration', () {
    test('text input replaces selection and updates two-way binding', () {
      final source = ObservableValue<String>('abcdef');
      final box = TextBox()
        ..bind(
          TextBox.textProperty,
          source.asBinding(),
          mode: BindingMode.twoWay,
        )
        ..selection = const TextSelection(baseOffset: 1, extentOffset: 5);
      final window = Window(content: box);

      box.focus();
      expect(box.isFocused, isTrue);
      window.dispatchTextInput('XX');

      expect(box.buffer.text, 'aXXf');
      expect(box.text, 'aXXf');
      expect(source.value, 'aXXf');
      expect(box.caretOffset, 3);
    });

    test('binding updates synchronize controller and clamp selection', () {
      final source = ObservableValue<String>('abcdef');
      final box = TextBox()
        ..bind(
          TextBox.textProperty,
          source.asBinding(),
          mode: BindingMode.twoWay,
        )
        ..selection = const TextSelection(baseOffset: 5, extentOffset: 2);

      source.value = 'xy';

      expect(box.buffer.text, 'xy');
      expect(box.selection, const TextSelection.collapsed(2));
    });
  });
}
