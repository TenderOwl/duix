import 'dart:async';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';

/// The text of the field of the example.
///
/// The text is longer than the field, so the field scrolls it.
const _areaText = 'Retained-mode text editing.\n'
    'Shift+Enter starts a new line,\n'
    'the arrows walk over the lines.\n'
    'A long text is wrapped into the width of the area, so the text never '
    'leaves the field.\n'
    'The area scrolls the text vertically: the wheel moves the text, and the '
    'scroll follows the caret as soon as the caret moves.\n'
    'A field of this size shows a few lines only, so the text of the field is '
    'longer than the field itself.\n'
    'Every line of this text belongs to the same buffer, and the selection '
    'covers the lines that the shift holds down.\n'
    'The field keeps its own scroll, so a long text can be read without '
    'moving the caret, and the scroll follows the caret as soon as the caret '
    'moves again.';

Future<void> main(List<String> args) async {
  SdlSkiaHost? host;
  Application? application;
  Window? window;
  final smoke = args.contains('--smoke');

  try {
    host = await SdlSkiaHost.initialize(
      diagnosticsEnabled: args.contains('--diagnostics'),
    );
    final area = TextArea(text: _areaText, fontSize: 16)
      ..minHeight = 220
      ..maxHeight = 220;

    application = Application(host: host);
    window = Window(
      title: 'DUI — TextArea editing',
      width: 720,
      height: 520,
      content: StackPanel(
        spacing: 14,
        padding: const EdgeInsets.all(24),
        children: [
          Label(text: 'TextArea editing', fontSize: 28),
          Label(
            text: 'Click to place the caret. Drag to select, including '
                'outside the field.',
            fontSize: 16,
            color: const Color(0xFF555555),
          ),
          Label(
            text: 'Shift+Enter · Up/Down · Home/End · the wheel scrolls '
                'the text.',
            fontSize: 16,
          ),
          _fieldLabel('Multiline field'),
          Border(
            color: const Color(0xFF777777),
            padding: const EdgeInsets.all(4),
            content: area,
          ),
          _fieldLabel('Empty field'),
          Border(
            color: const Color(0xFF777777),
            padding: const EdgeInsets.all(4),
            content: TextArea(fontSize: 16)
              ..minHeight = 90
              ..maxHeight = 90,
          ),
          Label(
            text: 'The text is wrapped into the width of the field, and the '
                'field scrolls the text vertically.',
            fontSize: 14,
            color: const Color(0xFF555555),
          ),
        ],
      ),
    );

    area.focus();
    if (smoke) {
      await host.showWindow(window);
      window.updateLayout();

      final before = area.text;
      window.dispatchKeyDown('enter', shiftPressed: true);
      if (area.text != '$before\n') {
        throw StateError('TextArea smoke Shift+Enter failed.');
      }
      window.dispatchKeyDown('enter');
      if (area.text != '$before\n') {
        throw StateError('TextArea smoke Enter started a new line.');
      }
      window.dispatchTextInput('A new line');
      if (!area.text.startsWith('$before\nA new line')) {
        throw StateError('TextArea smoke text input failed.');
      }

      // The caret walks over the lines.
      area.moveCaret(0);
      window.updateLayout();
      window.dispatchKeyDown('down');
      if (area.caretOffset <= 0) {
        throw StateError('TextArea smoke did not move the caret down.');
      }
      window.dispatchKeyDown('up');
      if (area.caretOffset != 0) {
        throw StateError('TextArea smoke did not move the caret up.');
      }
      area.moveCaret(5);
      window.dispatchKeyDown('home');
      if (area.caretOffset != 0) {
        throw StateError('TextArea smoke Home did not reach the line start.');
      }
      window.dispatchKeyDown('end');
      if (area.caretOffset != _firstLine.length) {
        throw StateError('TextArea smoke End did not reach the line end.');
      }

      // The wheel scrolls the text of the area.
      final offset = area.verticalOffset;
      window.dispatchMouseWheel(
        Point(area.bounds.left + 20, area.bounds.top + 20),
        deltaY: 1,
      );
      if (area.verticalOffset == offset) {
        throw StateError('TextArea smoke did not scroll the text.');
      }

      for (var frame = 0; frame < 1 && host.isOpen(window); frame++) {
        host.pumpEvents();
        host.presentWindow(window);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      if (!host.isOpen(window)) {
        throw StateError(
          'The native window closed before the TextArea smoke ended.',
        );
      }
      print('Native TextArea smoke passed: 1 frame rendered.');
    } else {
      await application.run(window);
    }
    final diagnostics = host.diagnosticsFor(window);
    if (diagnostics != null) print(diagnostics);
  } finally {
    host?.dispose();
  }
}

/// The first line of the text of the field.
final _firstLine = _areaText.split('\n').first;

Label _fieldLabel(String text) => Label(
      text: text,
      fontSize: 14,
      color: const Color(0xFF555555),
    );
