@Tags(['native'])
library;

import 'package:duix/dui.dart';
import 'package:duix/native.dart';
import 'package:test/test.dart';

void main() {
  late NativeTextLayoutFactory factory;

  setUpAll(() {
    factory = NativeTextLayoutFactory(NativeBindings.open());
  });

  const samples = <String, String>{
    'ASCII': 'The quick brown fox jumps over the lazy dog.',
    'Cyrillic': 'Съешь же ещё этих мягких французских булок.',
    'Emoji': 'Emoji: 😀 🚀 🌍 👨‍👩‍👧‍👦',
    'CJK': '中文测试 日本語のテスト 한국어 테스트',
    'Arabic': 'النص العربي للاختبار',
    'Hebrew': 'טקסט בעברית לבדיקה',
  };

  samples.forEach((name, text) {
    test('$name has valid metrics and editing geometry', () {
      final layout = factory.create(TextLayoutOptions(
        text: text,
        fontSize: 18,
        maxWidth: 420,
        scale: 1.25,
      ));
      try {
        _expectValidLayout(layout, text, maxWidth: 420);
      } finally {
        layout.dispose();
      }
    });
  });

  test('a text that is exactly as wide as its box stays on one line', () {
    const text = 'Badge';
    final wide = factory.create(const TextLayoutOptions(
      text: text,
      fontSize: 14,
      maxWidth: 1000,
      scale: 2,
    ));
    final tight = factory.create(TextLayoutOptions(
      text: text,
      fontSize: 14,
      maxWidth: wide.width,
      scale: 2,
    ));
    try {
      // The width of a line and the width of the box are the same number, so
      // the text must not push its last word onto the next line.
      expect(tight.height, wide.height);
      expect(tight.width, closeTo(wide.width, 0.01));
    } finally {
      wide.dispose();
      tight.dispose();
    }
  });

  test('multiline text increases height and selection stays in bounds', () {
    const text = 'First line\nВторая строка\n第三行';
    final single = factory.create(const TextLayoutOptions(
      text: 'First line',
      fontSize: 18,
      maxWidth: 180,
      scale: 1,
    ));
    final multiline = factory.create(const TextLayoutOptions(
      text: text,
      fontSize: 18,
      maxWidth: 180,
      scale: 1,
    ));
    try {
      expect(multiline.height, greaterThan(single.height));
      _expectValidLayout(multiline, text, maxWidth: 180);
      expect(multiline.selectionRects(0, text.length).length, greaterThan(1));
    } finally {
      single.dispose();
      multiline.dispose();
    }
  });

  test('caret advances and UTF-16 selection ranges match glyphs', () {
    const text = 'A😀B';
    final layout = factory.create(const TextLayoutOptions(
      text: text,
      fontSize: 24,
      maxWidth: 240,
      scale: 2,
    ));
    try {
      final carets = [0, 1, 3, 4].map(layout.caretRect).toList();
      for (var index = 1; index < carets.length; index++) {
        expect(
          carets[index].left,
          greaterThan(carets[index - 1].left),
          reason: 'Caret must advance at UTF-16 offset ${[0, 1, 3, 4][index]}',
        );
      }

      final first = layout.selectionRects(0, 1).single;
      final emoji = layout.selectionRects(1, 3).single;
      final full = layout.selectionRects(0, text.length);
      final fullRight = full
          .map((rect) => rect.right)
          .reduce((left, right) => left > right ? left : right);
      expect(emoji.left, greaterThanOrEqualTo(first.right - 0.5));
      expect(emoji.right, lessThan(fullRight - 0.5));
    } finally {
      layout.dispose();
    }
  });

  test('empty string has stable metrics and caret', () {
    final layout = factory.create(const TextLayoutOptions(
      text: '',
      fontSize: 18,
      maxWidth: 240,
      scale: 1.5,
    ));
    try {
      expect(layout.width, 0);
      expect(layout.height, greaterThanOrEqualTo(0));
      expect(layout.height.isFinite, isTrue);
      expect(layout.hitTest(const Point(0, 0)), const TextPosition(0));
      expect(layout.caretRect(0).height, greaterThanOrEqualTo(0));
      expect(layout.selectionRects(0, 0), isEmpty);
    } finally {
      layout.dispose();
    }
  });

  test('unbounded width keeps a single line without wrapping', () {
    const text = 'one two three four five';
    final unbounded = factory.create(const TextLayoutOptions(
      text: text,
      fontSize: 18,
      maxWidth: double.infinity,
      scale: 1.5,
    ));
    final constrained = factory.create(const TextLayoutOptions(
      text: text,
      fontSize: 18,
      maxWidth: 40,
      scale: 1.5,
    ));
    try {
      expect(unbounded.width, greaterThan(40));
      expect(unbounded.height, lessThan(constrained.height));
      expect(unbounded.caretRect(text.length).left, greaterThan(40));
    } finally {
      unbounded.dispose();
      constrained.dispose();
    }
  });

  test('very long string wraps without exceeding available width', () {
    final text = List<String>.filled(
      24,
      'Long строка 🚀 中文 with mixed scripts',
    ).join(' ');
    final layout = factory.create(TextLayoutOptions(
      text: text,
      fontSize: 18,
      maxWidth: 160,
      scale: 2,
    ));
    try {
      _expectValidLayout(layout, text, maxWidth: 160);
      expect(layout.height, greaterThan(100));
    } finally {
      layout.dispose();
    }
  });

  test('display scales preserve logical metrics and geometry', () {
    const text = 'Scale: ASCII кириллица 😀 中文';
    final layouts = <double, TextLayout>{};
    try {
      for (final scale in [1.0, 1.25, 1.5, 2.0]) {
        final layout = factory.create(TextLayoutOptions(
          text: text,
          fontSize: 18,
          maxWidth: 300,
          scale: scale,
        ));
        layouts[scale] = layout;
        _expectValidLayout(layout, text, maxWidth: 300);

        final reference = layouts[1.0]!;
        expect(layout.width, closeTo(reference.width, 0.51));
        expect(layout.height, closeTo(reference.height, 0.51));
        expect(layout.baseline, closeTo(reference.baseline, 0.51));
      }
    } finally {
      for (final layout in layouts.values) {
        layout.dispose();
      }
    }
  });
}

void _expectValidLayout(
  TextLayout layout,
  String text, {
  required double maxWidth,
}) {
  expect(layout.width.isFinite, isTrue);
  expect(layout.height.isFinite, isTrue);
  expect(layout.baseline.isFinite, isTrue);
  expect(layout.width, greaterThan(0));
  expect(layout.width, lessThanOrEqualTo(maxWidth + 1.0));
  expect(layout.height, greaterThan(0));
  expect(layout.baseline, greaterThan(0));

  final hit = layout.hitTest(Point(layout.width / 2, layout.height / 2));
  expect(hit.offset, inInclusiveRange(0, text.length));
  for (final offset in [0, text.length]) {
    final caret = layout.caretRect(offset);
    expect(caret.left.isFinite, isTrue);
    expect(caret.top.isFinite, isTrue);
    expect(caret.height, greaterThan(0));
    expect(caret.top, greaterThanOrEqualTo(-1.0));
    expect(caret.bottom, lessThanOrEqualTo(layout.height + 1.0));
  }

  final selection = layout.selectionRects(0, text.length);
  expect(selection, isNotEmpty);
  for (final rect in selection) {
    // Tight glyph boxes may overhang the layout's advance width slightly.
    expect(rect.left, greaterThanOrEqualTo(-4.0));
    expect(rect.right, lessThanOrEqualTo(maxWidth + 4.0));
    expect(rect.top, greaterThanOrEqualTo(-1.0));
    expect(rect.bottom, lessThanOrEqualTo(layout.height + 1.0));
  }
}
