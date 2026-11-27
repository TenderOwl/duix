import 'dart:async';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';

Future<void> main(List<String> args) async {
  final host = await SdlSkiaHost.initialize(
    diagnosticsEnabled: args.contains('--diagnostics'),
  );
  final status = ObservableValue<String>('Изменения не применены');

  final header = Border(
    color: const Color(0xFFF4F4F4),
    padding: const EdgeInsets.all(16),
    content: StackPanel(
      spacing: 4,
      children: [
        Label(text: 'Настройки приложения', fontSize: 24),
        Label(text: 'Типовое окно на контейнерах этапа 5'),
      ],
    ),
  );
  DockPanel.setDock(header, Dock.top);

  final applyButton = Button(
    content: Label(text: 'Применить все'),
    onClick: () => status.value = 'Все настройки применены',
  );
  DockPanel.setDock(applyButton, Dock.right);
  final statusLabel = Label()
    ..bind(
      Label.textProperty,
      status.map((value) => value).asBinding(),
    );
  final footer = Border(
    color: const Color(0xFFF4F4F4),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    content: DockPanel(children: [applyButton, statusLabel]),
  );
  DockPanel.setDock(footer, Dock.bottom);

  final firstEditor = TextBox(text: 'Моя конфигурация');
  final sections = StackPanel(
    spacing: 12,
    padding: const EdgeInsets.all(16),
    children: [
      _settingsSection(
        title: 'Общие',
        status: status,
        fields: [
          ('Название профиля', firstEditor),
          ('Рабочая папка', TextBox(text: 'C:\\Projects')),
        ],
      ),
      _settingsSection(
        title: 'Внешний вид',
        status: status,
        fields: [
          ('Тема', TextBox(text: 'Системная')),
          ('Масштаб', TextBox(text: '100%')),
          ('Семейство шрифта', TextBox(text: 'Segoe UI')),
        ],
      ),
      _settingsSection(
        title: 'Редактор',
        status: status,
        fields: [
          ('Размер табуляции', TextBox(text: '4')),
          ('Перенос строк', TextBox(text: 'По ширине viewport')),
          ('Горячая клавиша', TextBox(text: 'Ctrl+S')),
        ],
      ),
      _settingsSection(
        title: 'Синхронизация',
        status: status,
        fields: [
          ('Сервер', TextBox(text: 'https://settings.example.local')),
          ('Интервал', TextBox(text: '15 минут')),
        ],
      ),
      Label(
        text: 'Длинное пояснение демонстрирует горизонтальный extent: '
            'все элементы окна получают размеры от constraints и layout '
            'контейнеров, без задания абсолютных координат.',
      ),
    ],
  );

  final scrollViewer = ScrollViewer(content: sections);
  final window = Window(
    title: 'DUI — окно настроек',
    width: 640,
    height: 420,
    content: DockPanel(children: [header, footer, scrollViewer]),
  );

  final application = Application(host: host);
  try {
    if (args.contains('--smoke')) {
      await host.showWindow(window);
      window.updateLayout();
      if (!scrollViewer.canScrollHorizontally ||
          !scrollViewer.canScrollVertically ||
          header.bounds.bottom > scrollViewer.bounds.top ||
          footer.bounds.top < scrollViewer.bounds.bottom) {
        throw StateError('The settings layout did not resolve its regions.');
      }

      final wheelPosition = Point(
        scrollViewer.viewportRect.left + 30,
        scrollViewer.viewportRect.top + 30,
      );
      window.dispatchMouseWheel(wheelPosition, deltaY: -1);
      window.dispatchMouseWheel(wheelPosition, deltaX: 1);
      if (scrollViewer.verticalOffset != 48 ||
          scrollViewer.horizontalOffset != 48) {
        throw StateError('Settings smoke wheel scrolling failed.');
      }
      window.updateLayout();
      if (sections.bounds.left != scrollViewer.bounds.left - 48 ||
          sections.bounds.top != scrollViewer.bounds.top - 48) {
        throw StateError('Nested ScrollViewer did not arrange its content.');
      }

      firstEditor.focus();
      final previousOffset = scrollViewer.verticalOffset;
      window.dispatchKeyDown('pagedown');
      if (scrollViewer.verticalOffset <= previousOffset) {
        throw StateError('Keyboard scrolling did not bubble from TextBox.');
      }
      window.updateLayout();
      if (sections.bounds.top !=
          scrollViewer.bounds.top - scrollViewer.verticalOffset) {
        throw StateError('Keyboard offset was not applied to content bounds.');
      }

      final buttonPosition = Point(
        applyButton.bounds.left + applyButton.bounds.width / 2,
        applyButton.bounds.top + applyButton.bounds.height / 2,
      );
      window.dispatchPointerDown(buttonPosition);
      window.dispatchPointerUp(buttonPosition);
      if (status.value != 'Все настройки применены') {
        throw StateError('The settings footer button did not activate.');
      }

      scrollViewer.scrollToStart();
      window.updateLayout();
      final thumb = scrollViewer.verticalThumbRect;
      final track = scrollViewer.verticalTrackRect;
      final travel = track.height - thumb.height;
      final thumbStart = Point(
        thumb.left + thumb.width / 2,
        thumb.top + thumb.height / 2,
      );
      final maximumOffset =
          scrollViewer.extentHeight - scrollViewer.viewportHeight;
      window.dispatchPointerDown(thumbStart);
      window.dispatchPointerMove(Point(thumbStart.x, thumbStart.y + travel));
      if (scrollViewer.verticalOffset != maximumOffset) {
        throw StateError('Settings smoke thumb dragging failed.');
      }
      window
          .dispatchPointerMove(Point(thumbStart.x, thumbStart.y - travel * 2));
      if (scrollViewer.verticalOffset != 0) {
        throw StateError('Settings smoke thumb dragging did not clamp.');
      }
      window.dispatchPointerUp(thumbStart);

      final trackPosition =
          Point(track.left + track.width / 2, track.bottom - 3);
      window.dispatchPointerDown(trackPosition);
      window.dispatchPointerUp(trackPosition);
      if (scrollViewer.verticalOffset != scrollViewer.viewportHeight) {
        throw StateError('Settings smoke track click failed.');
      }

      scrollViewer.focus();
      window.dispatchKeyDown('down');
      if (scrollViewer.verticalOffset !=
          scrollViewer.viewportHeight + ScrollViewer.lineScrollDistance) {
        throw StateError('Settings smoke keyboard scrolling failed.');
      }
      window.dispatchKeyDown('end');
      if (scrollViewer.verticalOffset != maximumOffset) {
        throw StateError(
            'Settings smoke keyboard scrolling did not reach the end.');
      }
      window.dispatchKeyDown('home');
      if (scrollViewer.verticalOffset != 0) {
        throw StateError(
            'Settings smoke keyboard scrolling did not reach the start.');
      }

      for (var frame = 0; frame < 3 && host.isOpen(window); frame++) {
        host.pumpEvents();
        host.presentWindow(window);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      print('Native settings smoke passed: 3 frames rendered.');
    } else {
      await application.run(window);
    }
  } finally {
    host.dispose();
  }
}

UIElement _settingsSection({
  required String title,
  required ObservableValue<String> status,
  required List<(String, UIElement)> fields,
}) {
  final heading = Label(text: title, fontSize: 18)
    ..margin = const EdgeInsets.only(bottom: 12);
  DockPanel.setDock(heading, Dock.top);

  final applyButton = Button(
    content: Label(text: 'Применить раздел'),
    onClick: () => status.value = 'Раздел «$title» применён',
  )
    ..horizontalAlignment = HorizontalAlignment.right
    ..margin = const EdgeInsets.only(top: 12);
  DockPanel.setDock(applyButton, Dock.bottom);

  final grid = Grid(
    columns: [ColumnDefinition(), ColumnDefinition(width: GridLength.star())],
    rows: [for (final _ in fields) RowDefinition()],
    columnSpacing: 12,
    rowSpacing: 10,
  );
  for (var index = 0; index < fields.length; index++) {
    final (label, editor) = fields[index];
    final labelElement = Label(text: label)
      ..verticalAlignment = VerticalAlignment.center;
    Grid.setRow(labelElement, index);
    Grid.setColumn(labelElement, 0);
    grid.children.add(labelElement);
    Grid.setRow(editor, index);
    Grid.setColumn(editor, 1);
    grid.children.add(editor);
  }

  return Border(
    color: const Color(0xFFF7F7F7),
    padding: const EdgeInsets.all(16),
    content: DockPanel(children: [heading, applyButton, grid]),
  );
}
