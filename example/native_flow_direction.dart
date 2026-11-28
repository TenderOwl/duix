import 'dart:async';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';

/// A window whose layout runs from right to left.
///
/// The direction of the window reaches the whole tree: the text of the labels
/// and of the field starts at the right edge, the first child of a horizontal
/// panel stands at the right, the vertical scroll bar of the viewer stands on
/// the left and the content of the viewer starts at the right edge.
Future<void> main(List<String> args) async {
  final host = await SdlSkiaHost.initialize(
    diagnosticsEnabled: args.contains('--diagnostics'),
  );

  final title = Label(text: 'Направление раскладки', fontSize: 26)
    ..horizontalAlignment = HorizontalAlignment.stretch;

  final field = TextBox(text: 'Поле ввода', fontSize: 16)
    ..horizontalAlignment = HorizontalAlignment.stretch;

  // A text of a right to left paragraph keeps the order of its runs: the
  // native backend shapes it with the direction of the paragraph.
  final hebrew = TextBox(text: 'שלום עולם', fontSize: 18)
    ..horizontalAlignment = HorizontalAlignment.stretch;

  final buttons = StackPanel(
    orientation: Orientation.horizontal,
    spacing: 12,
    children: [
      for (final caption in const ['Первый', 'Второй', 'Третий'])
        Button(content: Label(text: caption, fontSize: 16)),
    ],
  );

  final cells = <Label>[];
  for (var index = 0; index < 24; index++) {
    final cell = Label(text: 'Ячейка $index', fontSize: 15);
    Grid.setRow(cell, index ~/ 2);
    Grid.setColumn(cell, index % 2);
    cells.add(cell);
  }

  final viewer = ScrollViewer(
    content: Grid(
      columns: [
        ColumnDefinition(width: GridLength.pixel(300)),
        ColumnDefinition(width: GridLength.pixel(300)),
      ],
      rows: [
        for (var index = 0; index < 12; index++)
          RowDefinition(height: GridLength.pixel(44)),
      ],
      children: cells,
    ),
  )..maxHeight = 200;

  final window = Window(
    title: 'DUI — Flow Direction',
    width: 520,
    height: 420,
    background: const Color(0xFFF5F5F7),
    content: StackPanel(
      spacing: 18,
      padding: const EdgeInsets.all(28),
      children: [title, field, hebrew, buttons, viewer],
    ),
  )..flowDirection = FlowDirection.rightToLeft;

  final application = Application(host: host);
  try {
    if (args.contains('--smoke')) {
      await host.showWindow(window);
      window.updateLayout();

      if (window.flowDirection != FlowDirection.rightToLeft) {
        throw StateError('The window does not follow the right to left '
            'direction.');
      }
      final first = buttons.children.first;
      if ((first.bounds.right - buttons.bounds.right).abs() > 0.0001) {
        throw StateError('The first child of the panel is not at the right '
            'edge: ${first.bounds} of ${buttons.bounds}.');
      }
      if (viewer.verticalScrollBar.bounds.left != viewer.bounds.left) {
        throw StateError('The vertical scroll bar is not on the left: '
            '${viewer.verticalScrollBar.bounds}.');
      }
      final content = viewer.content;
      if (content != null &&
          (content.bounds.right - viewer.viewportRect.right).abs() > 0.0001) {
        throw StateError('The content does not start at the right edge: '
            '${content.bounds} of ${viewer.viewportRect}.');
      }
      if (field.text.isEmpty) {
        throw StateError('The text of the field was lost.');
      }

      for (var frame = 0; frame < 3 && host.isOpen(window); frame++) {
        host.pumpEvents();
        host.presentWindow(window);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      final diagnostics = host.diagnosticsFor(window);
      if (diagnostics != null) print(diagnostics);
      print('Native flow direction smoke passed: 3 frames rendered.');
    } else {
      await application.run(window);
    }
  } finally {
    host.dispose();
  }
}
