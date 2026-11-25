import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  test('headless text layout provides deterministic editing geometry', () {
    const factory = HeadlessTextLayoutFactory();
    final layout = factory.create(const TextLayoutOptions(
      text: 'ab\ncd',
      fontSize: 10,
      maxWidth: 200,
      scale: 1,
    ));

    expect(layout.width, 12);
    expect(layout.height, 26);
    expect(layout.baseline, 10);
    expect(layout.hitTest(const Point(6, 13)), const TextPosition(4));
    final caret = layout.caretRect(4);
    expect((caret.left, caret.top, caret.width, caret.height),
        (6.0, 13.0, 0.0, 13.0));
    final selection = layout.selectionRects(1, 4);
    expect(selection, hasLength(2));
    expect(
      selection
          .map((rect) => (rect.left, rect.top, rect.width, rect.height))
          .toList(),
      [(6.0, 0.0, 6.0, 13.0), (0.0, 13.0, 6.0, 13.0)],
    );

    layout.dispose();
    layout.dispose();
    expect(layout.isDisposed, isTrue);
    expect(() => layout.width, throwsStateError);
    expect(() => layout.hitTest(const Point(0, 0)), throwsStateError);
  });

  test('TextBlock reuses layout and invalidates every cache input', () async {
    final factory = _CountingTextLayoutFactory();
    final text = TextBlock(text: 'first');
    final window = Window(
      width: 200,
      height: 100,
      textLayoutFactory: factory,
      content: text,
    );
    await window.show();
    final renderer = RecordingDrawingContext();

    window.renderFrame(renderer);
    expect(factory.created, hasLength(1));
    final initial = factory.created.single;

    window.renderFrame(renderer);
    expect(factory.created, hasLength(1));
    expect(initial.isDisposed, isFalse);

    text.color = const Color(0xFF123456);
    window.renderFrame(renderer);
    expect(factory.created, hasLength(1), reason: 'Color is paint-only.');

    text.text = 'changed';
    window.renderFrame(renderer);
    expect(factory.created, hasLength(2));
    expect(initial.isDisposed, isTrue);

    text.fontSize = 18;
    window.renderFrame(renderer);
    expect(factory.created, hasLength(3));

    text.alignment = TextAlignment.center;
    window.renderFrame(renderer);
    expect(factory.created, hasLength(4));

    window.updateDevicePixelRatio(2);
    window.renderFrame(renderer);
    expect(factory.created, hasLength(5));

    window.resize(120, 100);
    window.renderFrame(renderer);
    expect(factory.created, hasLength(6));

    final last = factory.created.last;
    window.close();
    expect(last.isDisposed, isTrue);
  });

  test('TextBlock measurement respects available width', () {
    final text = TextBlock(text: 'aaaa', fontSize: 10);

    final size = text.measure(const Size(12, 100));

    expect(size.width, 12);
    expect(size.height, 13);
  });
}

final class _CountingTextLayoutFactory implements TextLayoutFactory {
  static const _headless = HeadlessTextLayoutFactory();

  final created = <TextLayout>[];

  @override
  TextLayout create(TextLayoutOptions options) {
    final layout = _headless.create(options);
    created.add(layout);
    return layout;
  }
}
