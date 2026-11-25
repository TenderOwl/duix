import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('TextBox IME composition', () {
    test('editing is visible without changing text or two-way binding',
        () async {
      final source = ObservableValue<String>('confirm');
      final box = TextBox()
        ..bind(
          TextBox.textProperty,
          source.asBinding(),
          mode: BindingMode.twoWay,
        )
        ..selection = const TextSelection(baseOffset: 2, extentOffset: 5);
      final window = Window(content: box);
      box.focus();
      await window.show();

      window.dispatchTextEditing(
        'かな😀',
        compositionStart: 2,
        compositionLength: 2,
      );

      expect(box.hasComposition, isTrue);
      expect(box.compositionText, 'かな😀');
      expect(
        box.compositionSelection,
        const TextSelection(baseOffset: 2, extentOffset: 4),
      );
      expect(box.text, 'confirm');
      expect(source.value, 'confirm');

      final renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(
        renderer.commands.whereType<DrawTextCommand>().map((e) => e.text),
        contains('coかな😀rm'),
      );
      expect(
        renderer.commands.whereType<DrawRectCommand>().length,
        greaterThan(1),
      );
    });

    test('text input commits replacement and clears composition', () {
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

      window.dispatchTextEditing('中文');
      window.dispatchTextInput('中文');

      expect(box.text, 'a中文f');
      expect(source.value, 'a中文f');
      expect(box.hasComposition, isFalse);
      expect(box.compositionText, isEmpty);
      expect(box.compositionSelection, isNull);
      expect(box.caretOffset, 3);
    });

    test('composition supports Cyrillic and unset selection', () {
      final box = TextBox(text: 'abc')..moveCaret(3);
      final window = Window(content: box);
      box.focus();

      window.dispatchTextEditing('привет');

      expect(box.compositionText, 'привет');
      expect(box.compositionSelection, isNull);
      expect(box.text, 'abc');
    });

    test('empty editing event clears composition without committing', () {
      final box = TextBox(text: 'abc');
      final window = Window(content: box);
      box.focus();

      window.dispatchTextEditing('test',
          compositionStart: 1, compositionLength: 2);
      window.dispatchTextEditing('');

      expect(box.hasComposition, isFalse);
      expect(box.compositionSelection, isNull);
      expect(box.text, 'abc');
    });

    test('focus loss and recognized editing commands clear composition', () {
      final box = TextBox(text: 'abc');
      final button = Button();
      final window = Window(content: StackPanel(children: [box, button]));
      box.focus();
      window.dispatchTextEditing(' composing');

      button.focus();
      expect(box.hasComposition, isFalse);

      box.focus();
      window.dispatchTextEditing(' composing');
      window.dispatchKeyDown('left');
      expect(box.hasComposition, isFalse);
      expect(box.text, 'abc');
    });
  });
}
