import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  test('measures extent with infinite constraints and reserves scrollbars', () {
    final content = _FixedControl(const Size(400, 300));
    final viewer = ScrollViewer(content: content);
    final window = Window(width: 200, height: 100, content: viewer);

    window.updateLayout();

    expect(content.lastAvailableSize,
        const Size(double.infinity, double.infinity));
    expect(viewer.viewportSize, const Size(188, 88));
    expect(viewer.extentSize, const Size(400, 300));
    expect(viewer.isHorizontalScrollBarVisible, isTrue);
    expect(viewer.isVerticalScrollBarVisible, isTrue);
    expect(content.bounds, const Rect.fromLTWH(0, 0, 400, 300));
  });

  test('does not show automatic scrollbars when content fits', () {
    final viewer = ScrollViewer(content: _FixedControl(const Size(100, 50)));
    final window = Window(width: 200, height: 100, content: viewer);

    window.updateLayout();

    expect(viewer.viewportSize, const Size(200, 100));
    expect(viewer.extentSize, const Size(200, 100));
    expect(viewer.isHorizontalScrollBarVisible, isFalse);
    expect(viewer.isVerticalScrollBarVisible, isFalse);
  });

  test('hidden scrollbars permit scrolling and disabled axes constrain content',
      () {
    final hiddenContent = _FixedControl(const Size(400, 300));
    final hidden = ScrollViewer(
      content: hiddenContent,
      horizontalScrollBarVisibility: ScrollBarVisibility.hidden,
      verticalScrollBarVisibility: ScrollBarVisibility.hidden,
    );
    Window(width: 200, height: 100, content: hidden).updateLayout();
    hidden.scrollTo(horizontal: 50, vertical: 60);
    hidden.arrange(hidden.bounds);

    expect(hidden.viewportSize, const Size(200, 100));
    expect(hidden.horizontalOffset, 50);
    expect(hidden.verticalOffset, 60);
    expect(hidden.isHorizontalScrollBarVisible, isFalse);
    expect(hidden.isVerticalScrollBarVisible, isFalse);

    final disabledContent = _FixedControl(const Size(400, 300));
    final disabled = ScrollViewer(
      content: disabledContent,
      horizontalScrollBarVisibility: ScrollBarVisibility.disabled,
      verticalScrollBarVisibility: ScrollBarVisibility.disabled,
    );
    Window(width: 200, height: 100, content: disabled).updateLayout();

    expect(disabledContent.lastAvailableSize, const Size(200, 100));
    expect(disabled.extentSize, const Size(200, 100));
    expect(disabled.scrollBy(horizontal: 20, vertical: 20), isFalse);
    expect(disabled.horizontalOffset, 0);
    expect(disabled.verticalOffset, 0);
  });

  test('offsets clamp to extent and notify listeners', () {
    final viewer = ScrollViewer(content: _FixedControl(const Size(400, 300)));
    Window(width: 200, height: 100, content: viewer).updateLayout();
    final changes = <String>[];
    viewer.addPropertyListener(
      (event) => changes.add(event.property as String),
    );

    expect(viewer.scrollTo(horizontal: 1000, vertical: 1000), isTrue);
    expect(viewer.horizontalOffset, 212);
    expect(viewer.verticalOffset, 212);
    expect(viewer.scrollTo(horizontal: 1000, vertical: 1000), isFalse);
    expect(viewer.scrollBy(horizontal: -1000, vertical: -1000), isTrue);
    expect(viewer.horizontalOffset, 0);
    expect(viewer.verticalOffset, 0);
    expect(
      changes,
      [
        'horizontalOffset',
        'verticalOffset',
        'horizontalOffset',
        'verticalOffset'
      ],
    );
    expect(() => viewer.scrollTo(horizontal: -1), throwsArgumentError);
    expect(() => viewer.scrollTo(vertical: double.nan), throwsArgumentError);
  });

  test('mouse wheel scrolls both axes and bubbles only when handled', () async {
    final viewer = ScrollViewer(content: _FixedControl(const Size(400, 300)));
    final window = Window(width: 200, height: 100, content: viewer);
    await window.show();

    window.dispatchMouseWheel(const Point(20, 20), deltaY: -1);
    window.dispatchMouseWheel(const Point(20, 20), deltaX: 1);
    window.updateLayout();

    expect(viewer.verticalOffset, 48);
    expect(viewer.horizontalOffset, 48);
    expect(contentLeft(viewer), -48);
    expect(contentTop(viewer), -48);

    window.dispatchMouseWheel(const Point(20, 20), deltaY: 1);
    expect(viewer.verticalOffset, 0);

    final nestedContent = _FixedControl(const Size(400, 300));
    final nestedViewer = ScrollViewer(content: nestedContent);
    final header = Label(text: 'Header');
    DockPanel.setDock(header, Dock.top);
    final nestedWindow = Window(
      width: 200,
      height: 100,
      content: DockPanel(children: [header, nestedViewer]),
    );
    nestedWindow.updateLayout();
    nestedWindow.dispatchMouseWheel(
      Point(nestedViewer.bounds.left + 10, nestedViewer.bounds.top + 10),
      deltaY: -1,
    );
    nestedWindow.updateLayout();

    expect(nestedViewer.verticalOffset, 48);
    expect(nestedContent.bounds.top, nestedViewer.bounds.top - 48);
  });

  test('keyboard scrolling bubbles from a focused descendant', () {
    final content = _FixedControl(const Size(400, 300));
    final viewer = ScrollViewer(content: content);
    final window = Window(width: 200, height: 100, content: viewer);
    window.updateLayout();
    content.focus();

    window.dispatchKeyDown('pagedown');
    expect(viewer.verticalOffset, 88);
    window.dispatchKeyDown('pageup');
    expect(viewer.verticalOffset, 0);
    window.dispatchKeyDown('down');
    expect(viewer.verticalOffset, 40);
    window.dispatchKeyDown('up');
    expect(viewer.verticalOffset, 0);
    window.dispatchKeyDown('right');
    expect(viewer.horizontalOffset, 40);
    window.dispatchKeyDown('left');
    expect(viewer.horizontalOffset, 0);
    window.dispatchKeyDown('end');
    expect(viewer.verticalOffset, 212);
    window.dispatchKeyDown('home');
    expect(viewer.verticalOffset, 0);
    expect(window.focusedElement, same(content));
  });

  test('render clips content and draws proportional scrollbar thumbs',
      () async {
    final viewer = ScrollViewer(content: _FixedControl(const Size(400, 300)));
    final window = Window(width: 200, height: 100, content: viewer);
    await window.show();
    window.updateLayout();
    viewer.scrollTo(horizontal: 48, vertical: 48);
    final renderer = RecordingDrawingContext();

    window.renderFrame(renderer);

    final clip = renderer.commands.whereType<PushClipRectCommand>().single;
    expect(clip.rect, const Rect.fromLTWH(0, 0, 188, 88));
    final contentRect = renderer.commands.whereType<DrawRectCommand>().first;
    expect(contentRect.rect, const Rect.fromLTWH(-48, -48, 400, 300));
    expect(
      renderer.commands
          .whereType<DrawRectCommand>()
          .map((command) => command.rect),
      containsAll([viewer.horizontalTrackRect, viewer.verticalTrackRect]),
    );
    expect(viewer.verticalThumbRect.height, closeTo(25.813, 0.001));
    expect(viewer.horizontalThumbRect.width, closeTo(88.36, 0.001));
  });

  test(
      'hit test excludes content outside viewport and accepts scrollbar tracks',
      () {
    final content = _FixedControl(const Size(400, 300));
    final viewer = ScrollViewer(content: content);
    Window(width: 200, height: 100, content: viewer).updateLayout();

    expect(viewer.hitTest(const Point(10, 10)), same(content));
    expect(
        viewer.hitTest(const Point(194, 10)), same(viewer.verticalScrollBar));
    expect(
        viewer.hitTest(const Point(10, 94)), same(viewer.horizontalScrollBar));
    expect(viewer.hitTest(const Point(201, 10)), isNull);
  });

  test('scroll thumbs support dragging and clamp both boundaries', () {
    final viewer = ScrollViewer(content: _FixedControl(const Size(400, 300)));
    final window = Window(width: 200, height: 100, content: viewer);
    window.updateLayout();
    final thumb = viewer.verticalThumbRect;
    final start = Point(thumb.left + 2, thumb.top + 5);

    window.dispatchPointerDown(start);
    expect(window.hasPointerCapture(viewer.verticalScrollBar), isTrue);
    expect(window.hasPointerCapture(viewer), isFalse);
    window.dispatchPointerMove(Point(start.x, start.y + 31));
    expect(viewer.verticalOffset, closeTo(105.6818, 0.001));
    window.dispatchPointerMove(Point(start.x, start.y - 1000));
    expect(viewer.verticalOffset, 0);
    window.dispatchPointerMove(Point(start.x, start.y + 1000));
    expect(viewer.verticalOffset, 212);
    window.dispatchPointerMove(Point(start.x, start.y - 1000));
    expect(viewer.verticalOffset, 0);
    window.dispatchPointerUp(const Point(300, 200));
    expect(window.hasPointerCapture(viewer.verticalScrollBar), isFalse);

    final horizontalThumb = viewer.horizontalThumbRect;
    final horizontalStart =
        Point(horizontalThumb.left + 5, horizontalThumb.top + 2);
    window.dispatchPointerDown(horizontalStart);
    window.dispatchPointerMove(
        Point(horizontalStart.x - 1000, horizontalStart.y));
    expect(viewer.horizontalOffset, 0);
    window.dispatchPointerMove(
        Point(horizontalStart.x + 1000, horizontalStart.y));
    expect(viewer.horizontalOffset, 212);
    window.dispatchPointerUp(const Point(-300, 200));
    expect(window.hasPointerCapture(viewer.horizontalScrollBar), isFalse);

    window.dispatchPointerMove(const Point(194, 80));
    expect(viewer.verticalOffset, 0);
  });

  test('clicking a scrollbar track scrolls by one viewport', () {
    final viewer = ScrollViewer(content: _FixedControl(const Size(400, 300)));
    final window = Window(width: 200, height: 100, content: viewer);
    window.updateLayout();

    window.dispatchPointerDown(
      Point(viewer.verticalTrackRect.left + 2,
          viewer.verticalThumbRect.bottom + 5),
    );

    expect(viewer.verticalOffset, viewer.viewportHeight);
    // The scroll bar is not focusable, so the focus of the area stays where
    // it was.
    expect(window.focusedElement, isNull);
  });

  test('layout clamps offsets and hides automatic bars after content shrinks',
      () {
    final content = _FixedControl(const Size(400, 300));
    final viewer = ScrollViewer(content: content);
    final window = Window(width: 200, height: 100, content: viewer);
    window.updateLayout();
    viewer.scrollToEnd();

    content.size = const Size(100, 50);
    window.updateLayout();

    expect(viewer.horizontalOffset, 0);
    expect(viewer.verticalOffset, 0);
    expect(viewer.isHorizontalScrollBarVisible, isFalse);
    expect(viewer.isVerticalScrollBarVisible, isFalse);
    expect(viewer.viewportSize, const Size(200, 100));
  });
}

double contentLeft(ScrollViewer viewer) => viewer.content!.bounds.left;
double contentTop(ScrollViewer viewer) => viewer.content!.bounds.top;

final class _FixedControl extends Control {
  _FixedControl(this._size);

  Size _size;
  Size? lastAvailableSize;

  Size get size => _size;
  set size(Size value) {
    if (_size == value) return;
    _size = value;
    invalidateMeasure();
  }

  @override
  Size measureCore(Size availableSize) {
    lastAvailableSize = availableSize;
    return _size;
  }

  @override
  void renderCore(DrawingContext context) {
    context.drawRect(bounds, const Paint(Color(0xFFCCCCCC)));
  }
}
