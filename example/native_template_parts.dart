import 'dart:async';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';

const _field = Color(0xFFEFEFEF);
const _frame = Color(0xFFB0B0B0);

Future<void> main(List<String> args) async {
  final host = await SdlSkiaHost.initialize(
    diagnosticsEnabled: args.contains('--diagnostics'),
  );

  // A template of a text box places the part with the text: the frame around
  // the field belongs to the template, the text stays with the control.
  final fieldTemplate = ControlTemplate<TextBox>((control) {
    return Border(
      color: _field,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      content: Border(
        color: _frame,
        padding: const EdgeInsets.all(1),
        content: control.part('text'),
      ),
    );
  });

  final box = TextBox(text: 'Шаблон не заменяет текст', fontSize: 16)
    ..style = Style<TextBox>(
      name: 'Field',
      setters: [DuiSetter(TextBox.templateProperty, fieldTemplate)],
    )
    ..horizontalAlignment = HorizontalAlignment.stretch;

  // A template of a scrollable area places the content and the two scroll
  // bars: the area decides where they sit, the viewer keeps them alive.
  final viewerTemplate = ControlTemplate<ScrollViewer>((control) {
    final content = control.part('content')!;
    final horizontal = control.part('horizontalScrollBar')!;
    final vertical = control.part('verticalScrollBar')!;
    Grid.setRow(content, 0);
    Grid.setColumn(content, 0);
    Grid.setRow(horizontal, 1);
    Grid.setColumn(horizontal, 0);
    Grid.setRow(vertical, 0);
    Grid.setColumn(vertical, 1);
    return Grid(
      columns: [
        ColumnDefinition(width: GridLength.star()),
        ColumnDefinition(
            width: GridLength.pixel(ScrollViewer.scrollBarThickness)),
      ],
      rows: [
        RowDefinition(height: GridLength.star()),
        RowDefinition(
            height: GridLength.pixel(ScrollViewer.scrollBarThickness)),
      ],
      children: [content, horizontal, vertical],
    );
  });

  final viewer = ScrollViewer(
    content: StackPanel(
      spacing: 10,
      padding: const EdgeInsets.all(12),
      children: [
        for (var index = 0; index < 24; index++)
          Label(text: 'Строка $index', fontSize: 15),
      ],
    ),
  )..style = Style<ScrollViewer>(
      name: 'Viewer',
      setters: [DuiSetter(ScrollViewer.templateProperty, viewerTemplate)],
    );

  final window = Window(
    title: 'DUI — Template Parts',
    width: 520,
    height: 360,
    background: const Color(0xFFF5F5F7),
    content: StackPanel(
      spacing: 18,
      padding: const EdgeInsets.all(28),
      children: [
        Label(text: 'Template Parts', fontSize: 28),
        Label(
          text: 'Шаблон размещает части, а содержимое остаётся у контрола.',
        ),
        box,
        Grid(
          rows: [RowDefinition(height: GridLength.pixel(220))],
          children: [viewer],
        ),
      ],
    ),
  );

  final application = Application(host: host);
  try {
    if (args.contains('--smoke')) {
      await host.showWindow(window);
      window.updateLayout();

      final textPart = box.part('text');
      if (textPart == null || textPart.logicalParent == null) {
        throw StateError('The template did not place the part with the text.');
      }
      if (box.text.isEmpty) {
        throw StateError('The text of the field was lost.');
      }
      final contentPart = viewer.part('content');
      if (contentPart == null || contentPart.logicalParent == null) {
        throw StateError('The template did not place the content.');
      }
      if (viewer.verticalScrollBar.logicalParent == null) {
        throw StateError('The template did not place the scroll bars.');
      }
      if (!viewer.isVerticalScrollBarVisible) {
        throw StateError('The scroll bar of the template is not shown.');
      }

      for (var frame = 0; frame < 3 && host.isOpen(window); frame++) {
        host.pumpEvents();
        host.presentWindow(window);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      final diagnostics = host.diagnosticsFor(window);
      if (diagnostics != null) print(diagnostics);
      print('Native template parts smoke passed: 3 frames rendered.');
    } else {
      await application.run(window);
    }
  } finally {
    host.dispose();
  }
}
