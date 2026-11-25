import 'dart:async';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';

Future<void> main(List<String> args) async {
  SdlSkiaHost? host;
  Application? application;
  Window? window;
  final smoke = args.contains('--smoke');

  try {
    host = await SdlSkiaHost.initialize(
      diagnosticsEnabled: args.contains('--diagnostics'),
    );
    final source = ObservableValue<String>('Retained-mode text editing');
    final editor = TextBox()
      ..bind(
        TextBox.textProperty,
        source.asBinding(),
        mode: BindingMode.twoWay,
      );
    final bindingPreview = TextBlock(fontSize: 18)
      ..bind(
        TextBlock.textProperty,
        source.map((value) => 'Two-way binding: $value').asBinding(),
      );

    application = Application(host: host);
    window = Window(
      title: 'DUI — TextBox editing',
      width: 760,
      height: 590,
      content: StackPanel(
        spacing: 14,
        padding: const EdgeInsets.all(24),
        children: [
          TextBlock(text: 'TextBox keyboard and clipboard', fontSize: 28),
          TextBlock(
            text: 'Click a field to focus it. Type to replace the selection.',
            fontSize: 16,
            color: const Color(0xFF555555),
          ),
          TextBlock(
            text: 'Left/Right · Home/End · Shift+arrows · Ctrl/Cmd+arrows',
            fontSize: 16,
          ),
          TextBlock(
            text: 'Ctrl/Cmd+A · Ctrl/Cmd+C/X/V · Backspace/Delete',
            fontSize: 16,
          ),
          _fieldLabel('Two-way bound field'),
          Border(
            color: const Color(0xFF777777),
            padding: const EdgeInsets.all(4),
            content: editor,
          ),
          bindingPreview,
          _fieldLabel('Unicode field'),
          Border(
            color: const Color(0xFF777777),
            padding: const EdgeInsets.all(4),
            content: TextBox(text: 'Кириллица 😀 中文 العربية'),
          ),
          _fieldLabel('Empty field'),
          Border(
            color: const Color(0xFF777777),
            padding: const EdgeInsets.all(4),
            content: TextBox(),
          ),
          TextBlock(
            text: 'IME composition is underlined. Visual caret, normal '
                'selection and text clipping are not implemented yet.',
            fontSize: 14,
            color: const Color(0xFF555555),
          ),
        ],
      ),
    );

    editor.focus();
    await application.run(window);
    if (smoke) {
      window.dispatchKeyDown('a', controlPressed: true);
      window.dispatchTextEditing(
        'Smoke か😀',
        compositionStart: 7,
        compositionLength: 2,
      );
      if (source.value != 'Retained-mode text editing') {
        throw StateError('Composition changed the two-way binding source.');
      }
      host.presentWindow(window);
      window.dispatchTextInput('Smoke か😀');
      window.dispatchKeyDown('home');
      window.dispatchKeyDown('right', shiftPressed: true);
      if (source.value != 'Smoke か😀' || editor.selectedText != 'S') {
        throw StateError('TextBox smoke composition commit failed.');
      }
      for (var frame = 0; frame < 2 && host.isOpen(window); frame++) {
        host.pumpEvents();
        host.presentWindow(window);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      if (!host.isOpen(window)) {
        throw StateError(
          'The native window closed before the TextBox smoke ended.',
        );
      }
      print('Native TextBox smoke passed: 3 frames rendered.');
    } else {
      while (host.isOpen(window)) {
        host.pumpEvents();
        host.presentWindow(window);
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }
    }
    final diagnostics = host.diagnosticsFor(window);
    if (diagnostics != null) print(diagnostics);
  } finally {
    final activeWindow = window;
    if (application != null && activeWindow != null) {
      await application.shutdown(activeWindow);
    }
    host?.dispose();
  }
}

TextBlock _fieldLabel(String text) => TextBlock(
      text: text,
      fontSize: 14,
      color: const Color(0xFF555555),
    );
