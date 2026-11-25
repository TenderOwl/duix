import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  test('margin is included in desired size but excluded from actual bounds',
      () {
    final label = Label(text: 'aaaa', fontSize: 10)
      ..margin = const EdgeInsets.symmetric(horizontal: 5, vertical: 3);

    final desired = label.measure(const Size(100, 80));
    label.arrange(const Rect.fromLTWH(10, 20, 100, 80));

    expect(desired, const Size(34, 19));
    expect(label.desiredSize, const Size(34, 19));
    expect(label.arrangedSize, const Size(100, 80));
    expect(label.bounds, const Rect.fromLTWH(15, 23, 90, 74));
  });

  test('stretch fills the slot after subtracting margin', () {
    final label = Label(text: 'a', fontSize: 10)
      ..margin = const EdgeInsets.symmetric(horizontal: 5, vertical: 3);

    label.measure(const Size(100, 80));
    label.arrange(const Rect.fromLTWH(0, 0, 100, 80));

    expect(label.bounds, const Rect.fromLTWH(5, 3, 90, 74));
  });

  test('end alignment uses desired content size inside the margin', () {
    final label = Label(text: 'aaaa', fontSize: 10)
      ..margin = const EdgeInsets.symmetric(horizontal: 5, vertical: 3)
      ..horizontalAlignment = HorizontalAlignment.right
      ..verticalAlignment = VerticalAlignment.bottom;

    label.measure(const Size(100, 80));
    label.arrange(const Rect.fromLTWH(0, 0, 100, 80));

    expect(label.bounds, const Rect.fromLTWH(71, 64, 24, 13));
    expect(label.arrangedSize, const Size(100, 80));
  });

  test('center alignment centers the actual control bounds', () {
    final label = Label(text: 'aaaa', fontSize: 10)
      ..horizontalAlignment = HorizontalAlignment.center
      ..verticalAlignment = VerticalAlignment.center;

    label.measure(const Size(100, 50));
    label.arrange(const Rect.fromLTWH(0, 0, 100, 50));

    expect(label.bounds, const Rect.fromLTWH(38, 18.5, 24, 13));
  });

  test('start alignment is explicit and preserves natural size', () {
    final label = Label(text: 'aaaa', fontSize: 10)
      ..horizontalAlignment = HorizontalAlignment.left
      ..verticalAlignment = VerticalAlignment.top;

    label.measure(const Size(100, 50));
    label.arrange(const Rect.fromLTWH(10, 20, 100, 50));

    expect(label.bounds, const Rect.fromLTWH(10, 20, 24, 13));
  });

  test('minimum and maximum constraints clamp measured content', () {
    final label = Label(text: 'aaaa', fontSize: 10)
      ..minWidth = 30
      ..maxWidth = 36
      ..minHeight = 16
      ..maxHeight = 20;

    expect(label.measure(const Size(100, 100)), const Size(30, 16));

    label.text = 'aaaaaaaaaaaa';
    label.fontSize = 20;
    expect(label.measure(const Size(100, 100)), const Size(36, 20));
  });

  test('minimum size can exceed the available slot', () {
    final label = Label(text: 'a')..minWidth = 30;

    expect(label.measure(const Size(10, 100)).width, 30);

    label.arrange(const Rect.fromLTWH(0, 0, 10, 30));
    expect(label.bounds.width, 10,
        reason: 'Actual bounds stay inside the slot.');
  });

  test('measure cache is invalidated by changed available size', () {
    final label = Label(text: 'aaaa', fontSize: 10);

    expect(label.measure(const Size(12, 100)).width, 12);
    expect(label.measure(const Size(100, 100)).width, 24);
    expect(label.measure(const Size(12, 100)).width, 12);
  });

  test('horizontal StackPanel measures text with infinite width', () {
    final factory = _RecordingTextLayoutFactory();
    final label = Label(text: 'one two three', fontSize: 10);
    Window(
      width: 100,
      height: 50,
      textLayoutFactory: factory,
      content: StackPanel(
        orientation: Orientation.horizontal,
        children: [label],
      ),
    ).updateLayout();

    expect(factory.options.single.maxWidth, double.infinity);
    expect(label.desiredSize.width, 78);
    expect(label.bounds.width, 78);
    expect(label.bounds.width.isFinite, isTrue);
  });

  test('headless text layout accepts infinite width without wrapping', () {
    final layout = const HeadlessTextLayoutFactory().create(
      const TextLayoutOptions(
        text: 'one two three',
        fontSize: 10,
        maxWidth: double.infinity,
        scale: 1,
      ),
    );

    expect(layout.width, 78);
    expect(layout.height, 13);
    expect(layout.width.isFinite, isTrue);
    layout.dispose();
  });

  test('invalid constraints and non-finite arrange rects are rejected', () {
    final label = Label();

    expect(() => label.minWidth = -1, throwsArgumentError);
    expect(() => label.minWidth = double.infinity, throwsArgumentError);
    expect(() => label.maxWidth = double.nan, throwsArgumentError);
    expect(
      () => label.margin = const EdgeInsets.all(-1),
      throwsArgumentError,
    );
    expect(
      () => label.measure(const Size(double.nan, 10)),
      throwsArgumentError,
    );
    expect(
      () => label.arrange(
        const Rect.fromLTWH(0, 0, double.infinity, 10),
      ),
      throwsArgumentError,
    );
  });
}

final class _RecordingTextLayoutFactory implements TextLayoutFactory {
  static const _headless = HeadlessTextLayoutFactory();

  final options = <TextLayoutOptions>[];

  @override
  TextLayout create(TextLayoutOptions value) {
    options.add(value);
    return _headless.create(value);
  }
}
