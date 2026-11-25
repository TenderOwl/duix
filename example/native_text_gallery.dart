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
    application = Application(host: host);
    window = Window(
      title: 'DUI — Unicode text gallery',
      width: 960,
      height: 800,
      content: StackPanel(
        spacing: 9,
        padding: const EdgeInsets.all(24),
        children: [
          Label(
            text: 'SkParagraph Unicode and HiDPI gallery',
            fontSize: 28,
          ),
          Label(
            text:
                'Every sample uses the same layout for measurement and drawing.',
            fontSize: 14,
            color: Color(0xFF555555),
          ),
          _sample('ASCII', 'The quick brown fox jumps over the lazy dog.'),
          _sample('Кириллица', 'Съешь же ещё этих мягких французских булок.'),
          _sample('Emoji', '😀 🚀 🌍 👨‍👩‍👧‍👦 ❤️'),
          _sample('CJK', '中文测试　日本語のテスト　한국어 테스트'),
          _sample('Arabic', 'النص العربي للاختبار — ١٢٣٤٥'),
          _sample('Hebrew', 'טקסט בעברית לבדיקה — 12345'),
          _sample(
            'Multiline',
            'First line\nВторая строка\n第三行',
          ),
          _sample(
            'Empty string',
            '',
            note:
                'An empty layout is placed between this label and the next section.',
          ),
          _sample(
            'Very long wrapping text',
            List<String>.filled(
              5,
              'Long строка 🚀 中文 with mixed scripts',
            ).join(' '),
          ),
          Label(
            text: 'Centered alignment — выравнивание по центру',
            fontSize: 20,
            alignment: TextAlignment.center,
          ),
          Label(
            text: 'End alignment — выравнивание по концу',
            fontSize: 20,
            alignment: TextAlignment.end,
          ),
        ],
      ),
    );

    await application.run(window);
    if (smoke) {
      for (var frame = 0; frame < 3 && host.isOpen(window); frame++) {
        host.pumpEvents();
        host.presentWindow(window);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      if (!host.isOpen(window)) {
        throw StateError(
            'The native window closed before the gallery smoke ended.');
      }
      final diagnostics = host.diagnosticsFor(window);
      final renderedFrames = diagnostics?.renderFrameCount;
      print(
        'Native text gallery smoke passed: 3 event iterations'
        '${renderedFrames == null ? '' : ', $renderedFrames frames rendered'}.',
      );
    } else {
      while (host.isOpen(window)) {
        host.waitForEvent(window);
        host.presentWindow(window);
        await Future<void>.delayed(Duration.zero);
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

UIElement _sample(String label, String text, {String? note}) => StackPanel(
      spacing: 2,
      children: [
        Label(
          text: note == null ? label : '$label — $note',
          fontSize: 12,
          color: const Color(0xFF555555),
        ),
        Label(text: text, fontSize: 20),
      ],
    );
