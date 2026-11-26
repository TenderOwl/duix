import 'dart:async';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';

Future<void> main(List<String> args) async {
  final host = await SdlSkiaHost.initialize(
    diagnosticsEnabled: args.contains('--diagnostics'),
  );
  final status = Label(text: 'Файл не выбран', fontSize: 16);
  final fileDialog = FileDialog(host);
  late final Window window;

  window = Window(
    title: 'DUI — системный диалог открытия файла',
    width: 640,
    height: 240,
    content: StackPanel(
      spacing: 16,
      padding: const EdgeInsets.all(20),
      children: [
        Label(text: 'Системный диалог Windows', fontSize: 24),
        Button(
          content: Label(text: 'Выбрать файл…', fontSize: 16),
          onClick: () async {
            final path = await fileDialog.showOpen(
              parent: window,
              title: 'Выберите файл',
            );
            status.text = path ?? 'Выбор отменён';
          },
        ),
        Button(
          content: Label(text: 'Выбрать без родительского окна…', fontSize: 16),
          onClick: () async {
            final path = await fileDialog.showOpen(title: 'Выберите файл');
            status.text = path ?? 'Выбор отменён';
          },
        ),
        status,
      ],
    ),
  );

  final application = Application(host: host);
  await application.run(window);
  final diagnostics = host.diagnosticsFor(window);
  if (diagnostics != null) print(diagnostics);

  try {
    while (host.isOpen(window)) {
      host.waitForEvent(window);
      host.presentWindow(window);
      await Future<void>.delayed(Duration.zero);
    }
  } finally {
    await application.shutdown(window);
    host.dispose();
  }
}
