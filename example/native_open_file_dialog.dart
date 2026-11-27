import 'dart:async';
import 'dart:io';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';

Future<void> main(List<String> args) async {
  final host = await SdlSkiaHost.initialize(
    diagnosticsEnabled: args.contains('--diagnostics'),
  );
  final status = Label(text: 'Файл не выбран', fontSize: 16);
  final fileDialog = FileDialog(host)
    ..title = 'Выберите файл'
    ..initialDirectory = Directory.current.path
    ..filters = const [
      FileDialogFilter(name: 'Текстовые документы', extensions: ['txt', 'md']),
      FileDialogFilter(name: 'Все файлы', extensions: ['*']),
    ];

  Future<void> selectFile(Window? parent) async {
    try {
      final path = await fileDialog.showOpen(parent);
      status.text = path ?? 'Выбор отменён';
    } on Exception catch (err) {
      print(err);
    }
  }

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
          onClick: () => selectFile(window),
        ),
        Button(
          content: Label(text: 'Выбрать без родительского окна…', fontSize: 16),
          onClick: () => selectFile(null),
        ),
        status,
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
