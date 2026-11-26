import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  test('Window delegates open-file dialog with title and identity', () async {
    final dialogs = _FakeFileDialogs(result: r'C:\Documents\notes.txt');
    final window = Window()..fileDialogHandler = dialogs;

    final result = await window.showOpenFileDialog(title: 'Выберите файл');

    expect(result, r'C:\Documents\notes.txt');
    expect(dialogs.window, same(window));
    expect(dialogs.title, 'Выберите файл');
  });

  test('Window returns null when open-file dialog is cancelled', () async {
    final window = Window()..fileDialogHandler = _FakeFileDialogs();

    expect(await window.showOpenFileDialog(), isNull);
  });

  test('Window open-file dialog is unavailable without a backend', () async {
    expect(await Window().showOpenFileDialog(title: 'Файл'), isNull);
  });

  test('Standalone FileDialog accepts an optional parent window', () async {
    final dialogs = _FakeFileDialogs(result: '/tmp/document.txt');
    final dialog = FileDialog(dialogs)..title = 'Документ';
    final parent = Window();

    final result = await dialog.showOpen(parent);

    expect(result, '/tmp/document.txt');
    expect(dialogs.window, same(parent));
    expect(dialogs.title, 'Документ');
  });

  test('Standalone FileDialog can be opened without a parent', () async {
    final dialogs = _FakeFileDialogs(result: '/tmp/document.txt');
    final dialog = FileDialog(dialogs);

    expect(await dialog.showOpen(), '/tmp/document.txt');
    expect(dialogs.window, isNull);
  });

  test('FileDialog forwards initial directory and typed filters', () async {
    final dialogs = _FakeFileDialogs(result: '/tmp/readme.md');
    final dialog = FileDialog(dialogs);
    const filters = [
      FileDialogFilter(name: 'Документы', extensions: ['txt', 'md']),
      FileDialogFilter(name: 'Изображения', extensions: ['.png', '.jpg']),
    ];
    dialog
      ..initialDirectory = '/tmp'
      ..filters = filters;

    final result = await dialog.showOpen();

    expect(result, '/tmp/readme.md');
    expect(dialogs.initialDirectory, '/tmp');
    expect(dialogs.filters, same(filters));
  });
}

final class _FakeFileDialogs implements FileDialogHandler {
  _FakeFileDialogs({this.result});

  final String? result;
  Window? window;
  String? title;
  String? initialDirectory;
  List<FileDialogFilter> filters = const [];

  @override
  Future<String?> showOpenFileDialog(
    Window? window, {
    String? title,
    String? initialDirectory,
    List<FileDialogFilter> filters = const [],
  }) async {
    this.window = window;
    this.title = title;
    this.initialDirectory = initialDirectory;
    this.filters = filters;
    return result;
  }
}
