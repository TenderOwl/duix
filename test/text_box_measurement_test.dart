import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('TextBox measurement', () {
    test('follows the text layout metrics instead of a character count',
        () async {
      const text = 'Native measurement text';
      final box = TextBox(text: text, fontSize: 20);
      final label = Label(text: text, fontSize: 20);
      final window = Window(
        width: 400,
        height: 200,
        content: StackPanel(children: [box, label]),
      );
      await window.show();
      window.updateLayout();

      // The label measures the same layout without the content padding.
      expect(label.desiredSize.width, greaterThan(80));
      expect(
        box.desiredSize.width,
        closeTo(label.desiredSize.width + 16, 0.001),
      );
      expect(
        box.desiredSize.height,
        closeTo(label.desiredSize.height + 8, 0.001),
      );
    });

    test('scales with the font size', () async {
      const text = 'Native measurement text';
      final small = TextBox(text: text, fontSize: 14);
      final large = TextBox(text: text, fontSize: 28);
      final window = Window(
        width: 800,
        height: 200,
        content: StackPanel(children: [small, large]),
      );
      await window.show();
      window.updateLayout();

      // The text metrics scale with the font size, the content padding does not.
      expect(
        large.desiredSize.width,
        closeTo((small.desiredSize.width - 16) * 2 + 16, 0.001),
      );
      expect(large.desiredSize.height, greaterThan(small.desiredSize.height));
    });

    test('clamps to the available width instead of overflowing it', () async {
      final box = TextBox(text: 'Native measurement text');
      final window = Window(width: 60, height: 40, content: box);
      await window.show();
      window.updateLayout();

      expect(box.desiredSize.width, lessThanOrEqualTo(60));
      expect(box.desiredSize.height, greaterThan(0));
    });

    test('re-measures when the text changes', () async {
      final box = TextBox(text: 'short');
      final window = Window(width: 400, height: 200, content: box);
      await window.show();
      window.updateLayout();
      final initial = box.desiredSize.width;

      box.text = 'a much longer text value';
      window.updateLayout();

      expect(box.desiredSize.width, greaterThan(initial));
    });

    test('measures again after the control is remounted', () async {
      final box = TextBox(text: 'Native measurement text', fontSize: 20);
      final window = Window(width: 400, height: 200, content: box);
      await window.show();
      window.updateLayout();
      final initial = box.desiredSize.width;

      window.content = null;
      window.content = box;
      window.updateLayout();

      expect(box.desiredSize.width, closeTo(initial, 0.001));
    });
  });
}
