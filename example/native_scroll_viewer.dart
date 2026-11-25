import 'dart:async';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';

Future<void> main(List<String> args) async {
  final host = await SdlSkiaHost.initialize(
    diagnosticsEnabled: args.contains('--diagnostics'),
  );

  final settings = StackPanel(
    spacing: 12,
    padding: const EdgeInsets.all(20),
    children: [
      Label(text: 'Настройки', fontSize: 24),
      Label(
        text: 'Колесо мыши, PageUp/PageDown, стрелки, Home/End; '
            'ползунки можно перетаскивать.',
      ),
      for (var section = 1; section <= 4; section++)
        Border(
          color: const Color(0xFFF4F4F4),
          padding: const EdgeInsets.all(16),
          content: StackPanel(
            spacing: 10,
            children: [
              Label(text: 'Раздел $section', fontSize: 18),
              Label(text: 'Параметр $section.1'),
              TextBox(text: 'Значение параметра $section.1'),
              Label(text: 'Параметр $section.2'),
              TextBox(text: 'Значение параметра $section.2'),
              Button(content: Label(text: 'Применить раздел $section')),
            ],
          ),
        ),
      Label(
        text: 'Широкая строка демонстрирует горизонтальную прокрутку '
            'с помощью нижней полосы или клавиш Left/Right.',
      ),
    ],
  );

  final scrollViewer = ScrollViewer(content: settings);
  final window = Window(
    title: 'DUI — ScrollViewer',
    width: 520,
    height: 360,
    content: scrollViewer,
  );

  final application = Application(host: host);
  await application.run(window);
  final diagnostics = host.diagnosticsFor(window);
  if (diagnostics != null) print(diagnostics);

  try {
    if (args.contains('--smoke')) {
      window.updateLayout();
      if (!scrollViewer.canScrollHorizontally ||
          !scrollViewer.canScrollVertically) {
        throw StateError('ScrollViewer smoke requires overflow on both axes.');
      }
      window.dispatchMouseWheel(const Point(30, 30), deltaY: -1);
      window.dispatchMouseWheel(const Point(30, 30), deltaX: 1);
      if (scrollViewer.verticalOffset != 48 ||
          scrollViewer.horizontalOffset != 48) {
        throw StateError('ScrollViewer smoke wheel scrolling failed.');
      }
      for (var frame = 0; frame < 3 && host.isOpen(window); frame++) {
        host.pumpEvents();
        host.presentWindow(window);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      print('Native ScrollViewer smoke passed: 3 frames rendered.');
    } else {
      while (host.isOpen(window)) {
        host.waitForEvent(window);
        host.presentWindow(window);
        await Future<void>.delayed(Duration.zero);
      }
    }
  } finally {
    await application.shutdown(window);
    host.dispose();
  }
}
