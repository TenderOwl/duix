@Tags(['native'])
library;

import 'package:duix/dui.dart';
import 'package:duix/src/native/sdl_skia_host.dart';
import 'package:test/test.dart';

/// Builds a content that is taller than the viewport of the test window.
UIElement _buildContent() {
  return StackPanel(
    children: [
      for (var index = 0; index < 40; index++) Label(text: 'Строка $index'),
    ],
  );
}

void main() {
  test('native ScrollViewer drags its thumb and scrolls with the keyboard',
      () async {
    final host = await SdlSkiaHost.initialize();
    final viewer = ScrollViewer(content: _buildContent());
    final window = Window(width: 320, height: 200, content: viewer);
    try {
      await host.showWindow(window);
      window.updateLayout();

      expect(
        viewer.isVerticalScrollBarVisible,
        isTrue,
        reason: 'the content must overflow the viewport',
      );
      final maximumOffset = viewer.extentHeight - viewer.viewportHeight;
      expect(maximumOffset, greaterThan(0));

      final thumb = viewer.verticalThumbRect;
      final track = viewer.verticalTrackRect;
      final travel = track.height - thumb.height;
      expect(travel, greaterThan(0));
      final start = Point(
        thumb.left + thumb.width / 2,
        thumb.top + thumb.height / 2,
      );

      // Dragging the thumb over the whole free track length scrolls to the end.
      window.dispatchPointerDown(start);
      expect(window.hasPointerCapture(viewer), isTrue);
      window.dispatchPointerMove(Point(start.x, start.y + travel));
      expect(viewer.verticalOffset, closeTo(maximumOffset, 0.001));

      window.updateLayout();
      expect(viewer.verticalThumbRect.bottom, closeTo(track.bottom, 0.001));

      // The offset stays inside the boundaries while the drag continues.
      window.dispatchPointerMove(Point(start.x, start.y + travel * 2));
      expect(viewer.verticalOffset, closeTo(maximumOffset, 0.001));
      window.dispatchPointerMove(Point(start.x, start.y - travel * 2));
      expect(viewer.verticalOffset, 0);

      window.dispatchPointerUp(start);
      expect(window.hasPointerCapture(viewer), isFalse);

      // A click on the track below the thumb scrolls by one viewport.
      window.dispatchPointerDown(
          Point(track.left + track.width / 2, track.bottom - 3));
      window.dispatchPointerUp(
          Point(track.left + track.width / 2, track.bottom - 3));
      expect(viewer.verticalOffset, closeTo(viewer.viewportHeight, 0.001));

      // The keyboard scrolls the viewer when it owns the focus.
      expect(viewer.focus(), isTrue);
      window.dispatchKeyDown('down');
      expect(
        viewer.verticalOffset,
        closeTo(viewer.viewportHeight + ScrollViewer.lineScrollDistance, 0.001),
      );
      window.dispatchKeyDown('pageup');
      expect(viewer.verticalOffset,
          closeTo(ScrollViewer.lineScrollDistance, 0.001));
      window.dispatchKeyDown('end');
      expect(viewer.verticalOffset, closeTo(maximumOffset, 0.001));
      window.dispatchKeyDown('home');
      expect(viewer.verticalOffset, 0);

      // The content follows the offset after the layout pass.
      window.dispatchKeyDown('pagedown');
      window.updateLayout();
      expect(
        viewer.content!.bounds.top,
        closeTo(viewer.viewportRect.top - viewer.verticalOffset, 0.001),
      );
    } finally {
      await host.closeWindow(window);
      host.dispose();
    }
  });
}
