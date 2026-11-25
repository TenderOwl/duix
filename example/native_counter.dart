import 'dart:async';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';

Future<void> main(List<String> args) async {
  final host = await SdlSkiaHost.initialize(
    diagnosticsEnabled: args.contains('--diagnostics'),
  );
  final counter = ObservableValue<int>(0);

  final title = TextBlock(fontSize: 24)
    ..bind(
      TextBlock.textProperty,
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
          content: TextBlock(text: 'Увеличить', fontSize: 16),
          onClick: () => counter.value++,
        ),
      ],
    ),
  );

  final application = Application(host: host);
  await application.run(window);
  final diagnostics = host.diagnosticsFor(window);
  if (diagnostics != null) print(diagnostics);

  try {
    while (host.isOpen(window)) {
      host.pumpEvents();
      host.presentWindow(window);
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
  } finally {
    await application.shutdown(window);
    host.dispose();
  }
}
