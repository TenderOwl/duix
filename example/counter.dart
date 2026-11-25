import 'package:duix/dui.dart';

final class MemoryHost implements NativeHost {
  @override
  Future<void> showWindow(Window window) => window.show();

  @override
  Future<void> closeWindow(Window window) async => window.close();
}

Future<void> main() async {
  final counter = ObservableValue<int>(0);

  final title = TextBlock(fontSize: 24)
    ..bind(
      TextBlock.textProperty,
      counter.map((value) => 'Нажатий: $value').asBinding(),
    );

  final button = Button(
    content: TextBlock(text: 'Увеличить'),
    onClick: () => counter.value++,
  );

  final window = Window(
    title: 'Retained counter',
    width: 400,
    height: 240,
    content: StackPanel(
      spacing: 12,
      padding: const EdgeInsets.all(20),
      children: [title, button],
    ),
  );

  final application = Application(host: MemoryHost());
  await application.run(window);

  final renderer = RecordingDrawingContext();
  window.renderFrame(renderer);
  print('До нажатия: ${title.text}');

  final clickPosition = Point(
    button.bounds.left + 5,
    button.bounds.top + 5,
  );
  window.dispatchPointerDown(clickPosition);
  window.dispatchPointerUp(clickPosition);

  renderer.commands.clear();
  window.renderFrame(renderer);
  print('После нажатия: ${title.text}');
  print(
      'Тот же TextBlock: ${identical(title, window.content!.logicalChildren.first)}');
  print('Команд отрисовки: ${renderer.commands.length}');

  await application.shutdown(window);
}
