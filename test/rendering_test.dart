import 'package:duix/dui.dart';
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

  test('window tracks native display scale changes', () {
    final window = Window(content: TextBlock(text: 'HiDPI'));
    final changes = <double>[];
    window.addPropertyListener((event) {
      if (event.property == 'devicePixelRatio') {
        changes.add(event.newValue! as double);
      }
    });

    window.updateDevicePixelRatio(2);
    window.updateDevicePixelRatio(2);
    window.updateDevicePixelRatio(1.25);
    window.updateDevicePixelRatio(0);

    expect(window.devicePixelRatio, 1.25);
    expect(changes, [2, 1.25]);
    expect(window.frameScheduled, isTrue);
  });
}
