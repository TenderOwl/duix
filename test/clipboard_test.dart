import 'dart:convert';
import 'dart:typed_data';

import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  test('WindowHost delegates formatted clipboard without native types', () {
    final clipboard = _MemoryClipboard();
    final WindowHost window = Window()..clipboardHandler = clipboard;
    final formats = <String, List<int>>{
      ClipboardMimeTypes.plainText: utf8.encode('Текст 😀'),
      ClipboardMimeTypes.html: utf8.encode('<strong>Текст 😀</strong>'),
      'application/x-duix-binary': const <int>[0, 1, 0, 255],
      'application/x-duix-empty': const <int>[],
    };

    expect(window.writeClipboardData(formats), isTrue);
    expect(window.hasClipboardData(ClipboardMimeTypes.html), isTrue);
    expect(window.hasClipboardData('image/png'), isFalse);
    expect(
      utf8.decode(window.readClipboardData(ClipboardMimeTypes.html)!),
      '<strong>Текст 😀</strong>',
    );
    expect(
      window.readClipboardData('application/x-duix-binary'),
      const <int>[0, 1, 0, 255],
    );
    expect(window.readClipboardData('application/x-duix-empty'), isEmpty);
    expect(window.readClipboardData('image/png'), isNull);
  });

  test('Window formatted clipboard is unavailable without a backend', () {
    final window = Window();

    expect(window.hasClipboardData(ClipboardMimeTypes.html), isFalse);
    expect(window.readClipboardData(ClipboardMimeTypes.html), isNull);
    expect(window.readClipboardMimeTypes(), isEmpty);
    expect(window.clearClipboard(), isFalse);
    expect(
      window.writeClipboardData(<String, List<int>>{
        ClipboardMimeTypes.plainText: utf8.encode('text'),
      }),
      isFalse,
    );
  });
}

final class _MemoryClipboard implements ClipboardHandler {
  final _formats = <String, Uint8List>{};

  @override
  String? readClipboardText() {
    final data = _formats[ClipboardMimeTypes.plainText];
    return data == null ? null : utf8.decode(data);
  }

  @override
  bool writeClipboardText(String text) {
    _formats
      ..clear()
      ..[ClipboardMimeTypes.plainText] = utf8.encode(text);
    return true;
  }

  @override
  bool hasClipboardData(String mimeType) => _formats.containsKey(mimeType);

  @override
  Uint8List? readClipboardData(String mimeType) {
    final data = _formats[mimeType];
    return data == null ? null : Uint8List.fromList(data);
  }

  @override
  bool writeClipboardData(Map<String, List<int>> formats) {
    _formats
      ..clear()
      ..addAll(formats.map(
        (mimeType, data) => MapEntry(mimeType, Uint8List.fromList(data)),
      ));
    return true;
  }

  @override
  List<String> readClipboardMimeTypes() =>
      List<String>.unmodifiable(_formats.keys);

  @override
  bool clearClipboard() {
    _formats.clear();
    return true;
  }
}
