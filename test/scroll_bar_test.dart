import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('scroll bar', () {
    test('the thumb shows the part of the range that is visible', () async {
      final bar = ScrollBar(minimum: 0, maximum: 50, viewportSize: 50);
      final window = Window(width: 200, height: 100, content: bar);
      await window.show();
      window.updateLayout();

      expect(bar.isScrollable, isTrue);
      expect(bar.trackLength, 100);
      expect(bar.extent, 100);
      expect(bar.thumbRect.height, closeTo(50, 0.001));
      expect(bar.thumbRect.top, closeTo(0, 0.001));

      bar.value = 25;
      expect(bar.thumbRect.top, closeTo(25, 0.001));

      bar.value = 50;
      expect(bar.thumbRect.top, closeTo(50, 0.001));
    });

    test('a bar without a range has no thumb', () async {
      final bar = ScrollBar();
      final window = Window(width: 200, height: 100, content: bar);
      await window.show();
      window.updateLayout();

      expect(bar.isScrollable, isFalse);
      expect(bar.thumbRect, Rect.zero);
    });

    test('the thumb can be dragged and the value follows the pointer',
        () async {
      final bar = ScrollBar(minimum: 0, maximum: 50, viewportSize: 50);
      final window = Window(width: 200, height: 100, content: bar);
      await window.show();
      window.updateLayout();
      final thumb = bar.thumbRect;
      final start = Point(thumb.left + 5, thumb.top + 10);

      window.dispatchPointerDown(start);
      expect(window.hasPointerCapture(bar), isTrue);
      window.dispatchPointerMove(Point(start.x, start.y + 25));
      expect(bar.value, closeTo(25, 0.001));
      window.dispatchPointerMove(Point(start.x, start.y + 1000));
      expect(bar.value, 50);
      window.dispatchPointerMove(Point(start.x, start.y - 1000));
      expect(bar.value, 0);
      window.dispatchPointerUp(const Point(0, 0));
      expect(window.hasPointerCapture(bar), isFalse);
    });

    test('a click on the track scrolls by one page', () async {
      final bar = ScrollBar(minimum: 0, maximum: 50, viewportSize: 50);
      final window = Window(width: 200, height: 100, content: bar);
      await window.show();
      window.updateLayout();

      window.dispatchPointerDown(const Point(100, 80));
      expect(bar.value, 50);

      bar.value = 25;
      window.dispatchPointerDown(const Point(100, 10));
      expect(bar.value, 0);
    });

    test('the value stays inside the range', () async {
      final bar = ScrollBar(minimum: 10, maximum: 50, viewportSize: 50);
      final window = Window(width: 200, height: 100, content: bar);
      await window.show();
      window.updateLayout();

      bar.value = -100;
      expect(bar.value, 10);
      bar.value = 100;
      expect(bar.value, 50);
    });

    test('the bar draws the track and the thumb', () async {
      final bar = ScrollBar(minimum: 0, maximum: 50, viewportSize: 50);
      final window = Window(width: 200, height: 100, content: bar);
      await window.show();
      window.updateLayout();
      final renderer = RecordingDrawingContext();

      window.renderFrame(renderer);

      final rectangles =
          renderer.commands.whereType<DrawRectCommand>().toList();
      expect(rectangles.length, 2);
      expect(rectangles.first.paint.color.value, 0xFFF0F0F0);
      expect(rectangles.last.paint.color.value, 0xFFA0A0A0);
      expect(rectangles.last.rect, bar.thumbRect);
    });

    test('a horizontal bar measures the other way', () async {
      final bar = ScrollBar(
        orientation: Orientation.horizontal,
        minimum: 0,
        maximum: 50,
        viewportSize: 50,
      )
        ..horizontalAlignment = HorizontalAlignment.left
        ..verticalAlignment = VerticalAlignment.top;
      final window = Window(width: 200, height: 100, content: bar);
      await window.show();
      window.updateLayout();

      expect(bar.trackLength, 200);
      expect(bar.thumbRect.width, closeTo(100, 0.001));
      expect(bar.thumbRect.height, closeTo(8, 0.001));
    });
  });
}
