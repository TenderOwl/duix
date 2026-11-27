import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  test('click updates binding and recording renderer output', () async {
    final counter = ObservableValue<int>(0);
    final title = Label()
      ..bind(
        Label.textProperty,
        counter.map((value) => 'Count: $value').asBinding(),
      );
    final button = Button(
      content: Label(text: 'Increment'),
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

  test('recording renderer preserves rounded rectangle geometry', () {
    final renderer = RecordingDrawingContext();
    const rect = Rect.fromLTWH(4, 6, 120, 40);
    const paint = Paint(Color(0x88FFFFFF), strokeWidth: 2);

    renderer.drawRoundedRect(rect, 20, 18, paint);

    final command = renderer.commands.single as DrawRoundedRectCommand;
    expect(command.rect, rect);
    expect(command.radiusX, 20);
    expect(command.radiusY, 18);
    expect(command.paint, same(paint));
    expect(command.strokeWidth, 2);
  });

  test('recording renderer preserves lines and their stroke', () {
    final renderer = RecordingDrawingContext();
    const paint = Paint(Color(0xFF112233), strokeWidth: 3);

    renderer.drawLine(const Point(1, 2), const Point(30, 40), paint);

    final command = renderer.commands.single as DrawLineCommand;
    expect(command.from, const Point(1, 2));
    expect(command.to, const Point(30, 40));
    expect(command.paint, same(paint));
    expect(command.strokeWidth, 3);
  });

  test('recording renderer preserves images', () {
    final renderer = RecordingDrawingContext();
    final image = _FakeImage();
    const rect = Rect.fromLTWH(2, 3, 40, 20);
    const paint = Paint(Color(0xFFFFFFFF));

    renderer.drawImage(image, rect, paint);

    final command = renderer.commands.single as DrawImageCommand;
    expect(command.image, same(image));
    expect(command.rect, rect);
    expect(command.paint, same(paint));
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
    final window = Window(content: Label(text: 'HiDPI'));
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

/// An image of a backend that is not involved in the test.
final class _FakeImage implements DrawableImage {
  @override
  double get width => 8;

  @override
  double get height => 4;

  @override
  bool get isDisposed => false;

  @override
  void dispose() {}
}
