import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('flow direction', () {
    test('the direction is inherited by the descendants', () {
      final label = Label(text: 'Hello');
      final panel = StackPanel(children: [label]);

      expect(panel.flowDirection, FlowDirection.leftToRight);
      expect(label.flowDirection, FlowDirection.leftToRight);
      expect(panel.isRightToLeft, isFalse);

      panel.flowDirection = FlowDirection.rightToLeft;

      expect(panel.flowDirection, FlowDirection.rightToLeft);
      expect(label.flowDirection, FlowDirection.rightToLeft);
      expect(label.isRightToLeft, isTrue);
    });

    test('an own direction wins over the inherited one', () {
      final label = Label(text: 'Hello')
        ..flowDirection = FlowDirection.leftToRight;
      final panel = StackPanel(children: [label]);

      panel.flowDirection = FlowDirection.rightToLeft;

      expect(panel.flowDirection, FlowDirection.rightToLeft);
      expect(label.flowDirection, FlowDirection.leftToRight);
    });

    test('a detached element follows the default direction again', () {
      final label = Label(text: 'Hello');
      final panel = StackPanel(children: [label]);
      panel.flowDirection = FlowDirection.rightToLeft;

      label.attachToParent(null);

      expect(label.flowDirection, FlowDirection.leftToRight);
    });

    test('the window lays its content out in its direction', () {
      final label = Label(text: 'Hello');
      final window = Window(width: 200, height: 100, content: label);

      expect(label.flowDirection, FlowDirection.leftToRight);

      window.flowDirection = FlowDirection.rightToLeft;

      expect(label.flowDirection, FlowDirection.rightToLeft);
    });

    test('the content of the window follows the direction of the window', () {
      final label = Label(text: 'Hello');
      final window = Window(width: 200, height: 100)
        ..flowDirection = FlowDirection.rightToLeft;

      window.content = label;

      expect(label.flowDirection, FlowDirection.rightToLeft);
    });

    test('the logical alignment follows the direction', () {
      final label = Label(text: 'Hello')
        ..horizontalAlignment = HorizontalAlignment.start;
      final window = Window(width: 200, height: 100, content: label);
      window.updateLayout();

      expect(label.bounds.left, 0);

      label.flowDirection = FlowDirection.rightToLeft;
      window.updateLayout();

      expect(label.bounds.right, 200);
    });

    test('the end alignment is the mirror of the start alignment', () {
      final label = Label(text: 'Hello')
        ..horizontalAlignment = HorizontalAlignment.end;
      final window = Window(width: 200, height: 100, content: label);
      window.updateLayout();

      expect(label.bounds.right, 200);

      label.flowDirection = FlowDirection.rightToLeft;
      window.updateLayout();

      expect(label.bounds.left, 0);
    });

    test('the absolute alignment ignores the direction', () {
      final label = Label(text: 'Hello')
        ..horizontalAlignment = HorizontalAlignment.left;
      final window = Window(width: 200, height: 100, content: label);
      window.updateLayout();

      label.flowDirection = FlowDirection.rightToLeft;
      window.updateLayout();

      expect(label.bounds.left, 0);
    });

    test('a horizontal panel runs from right to left', () {
      final first = _FixedControl(const Size(20, 20));
      final second = _FixedControl(const Size(20, 20));
      final panel = StackPanel(
        orientation: Orientation.horizontal,
        children: [first, second],
      );
      final window = Window(width: 200, height: 100, content: panel);
      window.updateLayout();

      expect(first.bounds.left, 0);
      expect(second.bounds.left, 20);

      panel.flowDirection = FlowDirection.rightToLeft;
      window.updateLayout();

      expect(first.bounds.right, 200);
      expect(second.bounds.right, 180);
    });

    test('a vertical panel keeps the order of the children', () {
      final first = _FixedControl(const Size(20, 20));
      final second = _FixedControl(const Size(20, 20));
      final panel = StackPanel(children: [first, second]);
      final window = Window(width: 200, height: 100, content: panel);
      window.updateLayout();

      panel.flowDirection = FlowDirection.rightToLeft;
      window.updateLayout();

      expect(first.bounds.top, 0);
      expect(second.bounds.top, 20);
    });

    test('the dock of a child follows the direction', () {
      final side = _FixedControl(const Size(40, 40));
      final fill = _FixedControl(const Size(40, 40));
      final panel = DockPanel(children: [side, fill]);
      DockPanel.setDock(side, Dock.left);
      DockPanel.setDock(fill, Dock.bottom);
      final window = Window(width: 200, height: 100, content: panel);
      window.updateLayout();

      expect(side.bounds.left, 0);
      expect(side.bounds.right, 40);

      panel.flowDirection = FlowDirection.rightToLeft;
      window.updateLayout();

      expect(side.bounds.right, 200);
      expect(side.bounds.left, 160);
    });

    test('the text alignment is resolved for the direction', () {
      expect(
        resolveTextAlignment(TextAlignment.start, FlowDirection.leftToRight),
        0,
      );
      expect(
        resolveTextAlignment(TextAlignment.start, FlowDirection.rightToLeft),
        2,
      );
      expect(
        resolveTextAlignment(TextAlignment.end, FlowDirection.leftToRight),
        2,
      );
      expect(
        resolveTextAlignment(TextAlignment.end, FlowDirection.rightToLeft),
        0,
      );
      expect(
        resolveTextAlignment(TextAlignment.center, FlowDirection.rightToLeft),
        1,
      );
    });

    test('the direction is a part of the text layout options', () {
      const leftToRight = TextLayoutOptions(
        text: 'Hello',
        fontSize: 14,
        maxWidth: 100,
        scale: 1,
      );
      const rightToLeft = TextLayoutOptions(
        text: 'Hello',
        fontSize: 14,
        maxWidth: 100,
        scale: 1,
        direction: FlowDirection.rightToLeft,
      );

      expect(leftToRight, isNot(rightToLeft));
      expect(leftToRight.hashCode, isNot(rightToLeft.hashCode));
      expect(leftToRight.direction, FlowDirection.leftToRight);
    });

    test('the text of a label follows the direction of the tree', () {
      final label = Label(text: 'Hello');
      final window = Window(width: 200, height: 100, content: label);
      window.updateLayout();

      label.flowDirection = FlowDirection.rightToLeft;
      window.updateLayout();

      expect(label.flowDirection, FlowDirection.rightToLeft);
      expect(label.text, 'Hello');
    });
  });

  group('right to left layout', () {
    test('the text of a text box starts at the right edge', () async {
      final box = TextBox(text: 'Hello');
      final window = Window(width: 200, height: 40, content: box);
      await window.show();

      var renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      var text = renderer.commands.whereType<DrawTextCommand>().single;
      expect(text.position.x, closeTo(8, 0.0001));

      box.flowDirection = FlowDirection.rightToLeft;
      window.updateLayout();
      renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      text = renderer.commands.whereType<DrawTextCommand>().single;
      expect(text.position.x, closeTo(150, 0.0001));
    });

    test('a click in a right to left text box hits the text of the field', () {
      final box = TextBox(text: 'Hello')
        ..flowDirection = FlowDirection.rightToLeft;
      final window = Window(width: 200, height: 40, content: box);

      window.dispatchPointerDown(const Point(160, 12));
      window.dispatchPointerUp(const Point(160, 12));

      expect(box.caretOffset, 1);
    });

    test('the text of a label is aligned to the right', () async {
      final label = Label(text: 'Hello');
      final window = Window(width: 200, height: 40, content: label);
      await window.show();

      var renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      var text = renderer.commands.whereType<DrawTextCommand>().single;
      expect(text.position.x, closeTo(0, 0.0001));

      label.flowDirection = FlowDirection.rightToLeft;
      window.updateLayout();
      renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      text = renderer.commands.whereType<DrawTextCommand>().single;
      expect(text.position.x, closeTo(158, 0.0001));
    });

    test('the thumb of a horizontal bar starts at the right edge', () {
      final bar = ScrollBar(
        orientation: Orientation.horizontal,
        maximum: 100,
        viewportSize: 50,
      )..flowDirection = FlowDirection.rightToLeft;
      final window = Window(width: 200, height: 40, content: bar);
      window.updateLayout();

      expect(bar.thumbRect.right, closeTo(200, 0.0001));
      expect(bar.thumbRect.left, closeTo(133.3333, 0.0001));

      bar.value = 100;
      window.updateLayout();

      expect(bar.thumbRect.left, closeTo(0, 0.0001));
    });

    test('a click before the thumb of a right to left bar lowers the value',
        () {
      final bar = ScrollBar(
        orientation: Orientation.horizontal,
        maximum: 100,
        value: 50,
        viewportSize: 50,
      )..flowDirection = FlowDirection.rightToLeft;
      final window = Window(width: 200, height: 40, content: bar);
      window.updateLayout();

      window.dispatchPointerDown(const Point(180, 20));

      expect(bar.value, 0);
    });

    test('the vertical bar of a right to left viewer stands on the left', () {
      final content = _FixedControl(const Size(100, 400));
      final viewer = ScrollViewer(content: content)
        ..flowDirection = FlowDirection.rightToLeft;
      final window = Window(width: 200, height: 100, content: viewer);
      window.updateLayout();

      expect(viewer.isVerticalScrollBarVisible, isTrue);
      expect(viewer.verticalScrollBar.bounds.left, 0);
      expect(viewer.verticalScrollBar.bounds.right, 12);
    });

    test('the content of a right to left viewer starts at the right edge', () {
      final content = _FixedControl(const Size(400, 50));
      final viewer = ScrollViewer(content: content)
        ..flowDirection = FlowDirection.rightToLeft;
      final window = Window(width: 200, height: 100, content: viewer);
      window.updateLayout();

      expect(content.bounds.right, closeTo(200, 0.0001));

      viewer.scrollTo(horizontal: 50);
      window.updateLayout();

      expect(content.bounds.left, closeTo(-150, 0.0001));
    });
  });
}

final class _FixedControl extends Control {
  _FixedControl(this.size);

  final Size size;

  @override
  Size measureCore(Size availableSize) => size;
}
