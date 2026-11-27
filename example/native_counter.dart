import 'dart:async';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';

Future<void> main(List<String> args) async {
  final host = await SdlSkiaHost.initialize(
    diagnosticsEnabled: args.contains('--diagnostics'),
  );
  final counter = ObservableValue<int>(0);

  final title = Label(fontSize: 24)
    ..bind(
      Label.textProperty,
      counter.map((value) => 'Нажатий: $value').asBinding(),
    );

  final window = Window(
    title: 'DUI — SDL3 + Skia',
    width: 400,
    height: 240,
    content: StackPanel(
      spacing: 12,
      padding: const EdgeInsets.all(20),
      children: [
        title,
        Button(
          content: Label(text: 'Увеличить', fontSize: 16),
          onClick: () => counter.value++,
        ),
      ],
    ),
  );

  final application = Application(host: host);
  try {
    await application.run(window);
  } finally {
    host.dispose();
  }
}
