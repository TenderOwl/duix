import 'package:dui_retained/dui.dart';
import 'package:test/test.dart';

void main() {
  test('click updates binding and recording renderer output', () async {
    final counter = ObservableValue<int>(0);
    final title = TextBlock()
      ..bind(
        TextBlock.textProperty,
        counter.map((value) => 'Count: $value').asBinding(),
      );
    final button = Button(
      content: TextBlock(text: 'Increment'),
      onClick: () => counter.value++,
    );
    final window = Window(
      width: 300,
      height: 150,
      content: StackPanel(children: [title, button]),
    );
    await window.show();
    final renderer = RecordingDrawingContext();
    window.renderFrame(renderer);

    final point = Point(button.bounds.left + 2, button.bounds.top + 2);
    window.dispatchPointerDown(point);
    window.dispatchPointerUp(point);
    renderer.commands.clear();
    window.renderFrame(renderer);

    expect(title.text, 'Count: 1');
    expect(
      renderer.commands
          .whereType<DrawTextCommand>()
          .map((command) => command.text),
      containsAll(['Count: 1', 'Increment']),
    );
  });

  test('window uses an opaque white background by default', () {
    final window = Window();

    expect(window.background, Color.white);
    expect(window.background.value, 0xFFFFFFFF);

    window.background = const Color(0xFF202020);
    expect(window.background.value, 0xFF202020);
    expect(window.frameScheduled, isTrue);
  });
}
