import 'package:duix/dui.dart';
import 'package:test/test.dart';

/// An element that wants little space, but cannot work without more.
final class _MinimumElement extends UIElement {
  static const minimum = Size(50, 20);
  static const natural = Size(10, 10);

  @override
  Size measureCore(Size availableSize) => natural;

  @override
  SizeRequest measureRequest(Size availableSize) => SizeRequest(
        minimum: minimum,
        natural: natural,
      );
}

void main() {
  group('the size request of an element', () {
    test('an element without a minimum asks for its natural size', () {
      final label = Label(text: 'Hello');
      final window = Window(width: 400, height: 300, content: label);
      window.updateLayout();

      expect(label.minimumSize, Size.zero);
      expect(label.naturalSize.width, greaterThan(0));
      expect(label.desiredSize.width, label.naturalSize.width);
    });

    test('the minimum wins over a smaller natural size', () {
      final element = _MinimumElement();
      final window = Window(width: 400, height: 300, content: element);
      window.updateLayout();

      expect(element.naturalSize, const Size(10, 10));
      expect(element.minimumSize, const Size(50, 20));
      expect(element.desiredSize, const Size(50, 20));
    });

    test('the element is squeezed when the space is short', () {
      final element = _MinimumElement();
      final window = Window(width: 30, height: 300, content: element);
      window.updateLayout();

      expect(
        element.desiredSize.width,
        30,
        reason: 'an element never asks for more space than it can get',
      );
    });

    test('the parent reserves the minimum space of the child', () {
      final element = _MinimumElement();
      final window = Window(
        width: 400,
        height: 300,
        content: StackPanel(children: [element]),
      );
      window.updateLayout();

      expect(window.content!.desiredSize.width, greaterThanOrEqualTo(50));
    });

    test('the allocated size is the size the parent gave', () {
      final element = _MinimumElement()
        ..horizontalAlignment = HorizontalAlignment.left
        ..verticalAlignment = VerticalAlignment.top;
      final window = Window(width: 400, height: 300, content: element);
      window.updateLayout();

      expect(element.allocatedSize, const Size(50, 20));
      expect(element.bounds.width, 50);
      expect(element.bounds.height, 20);
    });

    test('a stretched element takes the whole slot', () {
      final element = _MinimumElement();
      final window = Window(width: 400, height: 300, content: element);
      window.updateLayout();

      expect(element.allocatedSize, const Size(400, 300));
    });

    test('a text box keeps its minimum size', () {
      final box = TextBox();
      final window = Window(width: 400, height: 300, content: box);
      window.updateLayout();

      expect(box.minimumSize, const Size(80, 30));
      expect(box.desiredSize.width, greaterThanOrEqualTo(80));
      expect(box.desiredSize.height, greaterThanOrEqualTo(30));
    });

    test('a text box in a narrow window is clamped to the window', () {
      final box = TextBox(text: 'Native measurement text');
      final window = Window(width: 60, height: 40, content: box);
      window.updateLayout();

      expect(
        box.desiredSize.width,
        lessThanOrEqualTo(60),
        reason: 'the element does not overflow the space it has',
      );
    });
  });
}
