import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('TextBox rendering', () {
    test('long text is enclosed in the content clip', () async {
      final box = TextBox(text: 'very long text ' * 8);
      final window = Window(width: 120, height: 30, content: box);
      await window.show();
      final renderer = RecordingDrawingContext();

      window.renderFrame(renderer);

      final push = renderer.commands.whereType<PushClipRectCommand>().single;
      _expectRect(push.rect, 8, 4, 104, 22);
      final pushIndex = renderer.commands.indexOf(push);
      final textIndex = renderer.commands.indexWhere(
        (command) => command is DrawTextCommand,
      );
      final popIndex = renderer.commands.indexWhere(
        (command) => command is PopClipCommand,
      );
      expect(textIndex, greaterThan(pushIndex));
      expect(popIndex, greaterThan(textIndex));
      expect(popIndex, renderer.commands.length - 1);
    });

    test('End, Home and arrow keys scroll a long line to keep caret visible',
        () async {
      final box = TextBox(text: 'abcdefghijklmno');
      final window = Window(width: 80, height: 30, content: box);
      box.focus();
      await window.show();

      var renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      var text = renderer.commands.whereType<DrawTextCommand>().single;
      var caret = _caret(renderer);
      expect(text.position.x, lessThan(8));
      expect(caret.rect.left, inInclusiveRange(8, 72));

      window.dispatchKeyDown('home');
      renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      text = renderer.commands.whereType<DrawTextCommand>().single;
      caret = _caret(renderer);
      expect(text.position.x, 8);
      expect(caret.rect.left, 8);

      window.dispatchKeyDown('right');
      renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(
        renderer.commands.whereType<DrawTextCommand>().single.position.x,
        8,
      );
      expect(_caret(renderer).rect.left, closeTo(16.4, 0.0001));

      window.dispatchKeyDown('end');
      renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(
        renderer.commands.whereType<DrawTextCommand>().single.position.x,
        lessThan(8),
      );
      expect(_caret(renderer).rect.left, inInclusiveRange(8, 72));
    });

    test('focused collapsed selection draws a visible caret', () async {
      final box = TextBox(text: 'abcdef')..moveCaret(2);
      final window = Window(width: 120, height: 30, content: box);
      box.focus();
      await window.show();
      final renderer = RecordingDrawingContext();

      window.renderFrame(renderer);

      final caretIndex = renderer.commands.indexWhere(
        (command) =>
            command is DrawRectCommand &&
            command.paint.color.value == 0xFF202020,
      );
      expect(caretIndex, greaterThan(0));
      final caret = renderer.commands[caretIndex] as DrawRectCommand;
      _expectRect(caret.rect, 24.8, 7, 1, 18.2);
      final textIndex = renderer.commands.indexWhere(
        (command) => command is DrawTextCommand,
      );
      expect(caretIndex, greaterThan(textIndex));
      final popIndex = renderer.commands.indexWhere(
        (command) => command is PopClipCommand,
      );
      expect(popIndex, greaterThan(caretIndex));
    });

    test('unfocused collapsed selection does not draw a caret', () async {
      final box = TextBox(text: 'abcdef')..moveCaret(2);
      final window = Window(width: 120, height: 30, content: box);
      await window.show();
      final renderer = RecordingDrawingContext();

      window.renderFrame(renderer);

      expect(
        renderer.commands.whereType<DrawRectCommand>().where(
              (command) => command.paint.color.value == 0xFF202020,
            ),
        isEmpty,
      );
    });

    test('ordinary selection is highlighted before text without a caret',
        () async {
      final box = TextBox(text: 'abcdef')
        ..selection = const TextSelection(baseOffset: 1, extentOffset: 4);
      final window = Window(width: 120, height: 30, content: box);
      box.focus();
      await window.show();
      final renderer = RecordingDrawingContext();

      window.renderFrame(renderer);

      final selectionIndex = renderer.commands.indexWhere(
        (command) =>
            command is DrawRectCommand &&
            command.paint.color.value == 0x5580CFFF,
      );
      expect(selectionIndex, greaterThan(0));
      final selection = renderer.commands[selectionIndex] as DrawRectCommand;
      _expectRect(selection.rect, 16.4, 7, 25.2, 18.2);
      final textIndex = renderer.commands.indexWhere(
        (command) => command is DrawTextCommand,
      );
      expect(selectionIndex, lessThan(textIndex));
      expect(
        renderer.commands.whereType<DrawRectCommand>().where(
              (command) => command.paint.color.value == 0xFF202020,
            ),
        isEmpty,
      );
    });

    test('composition keeps its distinct highlight without a normal caret',
        () async {
      final box = TextBox(text: 'abcdef')..moveCaret(3);
      final window = Window(width: 120, height: 30, content: box);
      box.focus();
      await window.show();
      window.dispatchTextEditing(
        'か😀',
        compositionStart: 0,
        compositionLength: 1,
      );
      final renderer = RecordingDrawingContext();

      window.renderFrame(renderer);

      expect(
        renderer.commands.whereType<DrawRectCommand>().where(
              (command) => command.paint.color.value == 0x5599CCFF,
            ),
        isNotEmpty,
      );
      expect(
        renderer.commands.whereType<DrawRectCommand>().where(
              (command) => command.paint.color.value == 0xFF202020,
            ),
        isEmpty,
      );
      final popIndex = renderer.commands.indexWhere(
        (command) => command is PopClipCommand,
      );
      expect(popIndex, greaterThan(0));
      expect(popIndex, lessThan(renderer.commands.length - 1));
    });
  });
}

DrawRectCommand _caret(RecordingDrawingContext renderer) => renderer.commands
    .whereType<DrawRectCommand>()
    .singleWhere((command) => command.paint.color.value == 0xFF202020);

void _expectRect(
  Rect rect,
  double left,
  double top,
  double width,
  double height,
) {
  expect(rect.left, closeTo(left, 0.0001));
  expect(rect.top, closeTo(top, 0.0001));
  expect(rect.width, closeTo(width, 0.0001));
  expect(rect.height, closeTo(height, 0.0001));
}
