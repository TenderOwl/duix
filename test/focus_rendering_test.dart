import 'package:duix/dui.dart';
import 'package:test/test.dart';

const _focusRingColor = 0xFF356AC3;

void main() {
  group('focus rendering', () {
    test('Button draws a focus ring only while focused', () async {
      final button = Button(content: TextBlock(text: 'Action'));
      final window = Window(width: 120, height: 50, content: button);
      await window.show();

      var renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(_focusRing(renderer), isEmpty);

      button.focus();
      renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      final ring = _focusRing(renderer);
      expect(ring, hasLength(4));
      _expectRect(ring[0].rect, 0, 0, 120, 2);
      _expectRect(ring[1].rect, 0, 48, 120, 2);
      _expectRect(ring[2].rect, 0, 2, 2, 46);
      _expectRect(ring[3].rect, 118, 2, 2, 46);

      final other = Button();
      window.content = other;
      renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(_focusRing(renderer), isEmpty);
    });

    test('TextBox draws a focus ring together with its caret', () async {
      final box = TextBox(text: 'Text');
      final window = Window(width: 120, height: 30, content: box);
      await window.show();

      var renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(_focusRing(renderer), isEmpty);

      box.focus();
      renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(_focusRing(renderer), hasLength(4));
      expect(
        renderer.commands.whereType<DrawRectCommand>().where(
              (command) => command.paint.color.value == 0xFF202020,
            ),
        hasLength(1),
      );

      box.isEnabled = false;
      renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(_focusRing(renderer), isEmpty);
    });
  });
}

List<DrawRectCommand> _focusRing(RecordingDrawingContext renderer) =>
    renderer.commands
        .whereType<DrawRectCommand>()
        .where((command) => command.paint.color.value == _focusRingColor)
        .toList();

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
