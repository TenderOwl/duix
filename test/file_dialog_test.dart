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
    final dialog = FileDialog(dialogs);
    final parent = Window();

    final result = await dialog.showOpen(
      parent: parent,
      title: 'Документ',
    );

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
}

final class _FakeFileDialogs implements FileDialogHandler {
  _FakeFileDialogs({this.result});

  final String? result;
  Window? window;
  String? title;

  @override
  Future<String?> showOpenFileDialog(Window? window, {String? title}) async {
    this.window = window;
    this.title = title;
    return result;
  }
}
