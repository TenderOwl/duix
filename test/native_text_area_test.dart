@Tags(['native'])
library;

import 'package:duix/dui.dart';
import 'package:duix/native.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

/// The wrapping of the native backend.
///
/// The native paragraph wraps the text into the width of the layout, so the
/// lines of a text area are the lines of the paragraph and the caret of the
/// area walks over them.
void main() {
  late NativeBindings bindings;

  setUpAll(() {
    bindings = NativeBindings.open();
  });

  const longText =
      'one two three four five six seven eight nine ten eleven twelve';

  /// A text that takes more lines than the area of the test can show.
  const veryLongText = 'one two three four five six seven eight '
      'one two three four five six seven eight '
      'one two three four five six seven eight '
      'one two three four five six seven eight '
      'one two three four five six seven eight '
      'one two three four five six seven eight';

  test('the native paragraph wraps the text into the width', () {
    final arena = Arena();
    try {
      final layout = bindings.textLayoutCreate(
        text: longText,
        fontSize: 16,
        maxWidth: 120,
        scale: 1,
        arena: arena,
      );
      final metrics = bindings.textLayoutMeasure(layout, arena);
      bindings.textLayoutDestroy(layout);

      expect(metrics.width, lessThanOrEqualTo(120));
      expect(
        metrics.height,
        greaterThan(16),
        reason: 'the text of a narrow layout takes more than one line',
      );
    } finally {
      arena.releaseAll();
    }
  });

  test('the caret of the wrapped text stands on its own line', () {
    final arena = Arena();
    try {
      final layout = bindings.textLayoutCreate(
        text: longText,
        fontSize: 16,
        maxWidth: 100,
        scale: 1,
        arena: arena,
      );
      final first = bindings.textLayoutCaretRect(layout, 0, arena);
      final last =
          bindings.textLayoutCaretRect(layout, longText.length - 1, arena);
      final hit = bindings.textLayoutHitTest(layout, 10, 40, arena);
      bindings.textLayoutDestroy(layout);

      expect(
        last.top,
        greaterThan(first.top + 10),
        reason: 'the last character stands on a line below the first one',
      );
      expect(
        hit,
        greaterThan(0),
        reason: 'a point under the first line belongs to the text below it',
      );
    } finally {
      arena.releaseAll();
    }
  });

  test('the text area of the native window wraps the text', () async {
    final host = await SdlSkiaHost.initialize();
    final area = TextArea(text: longText, fontSize: 16);
    final window = Window(width: 320, height: 200, content: area);
    try {
      await host.showWindow(window);
      window.updateLayout();

      final layout = area.layoutForRender(area.text);
      expect(
        layout.height,
        greaterThan(16),
        reason: 'the text of the area takes more than one line',
      );
      expect(
        layout.width,
        lessThanOrEqualTo(area.textPart.bounds.width),
        reason: 'the text fits into the width that the area shows',
      );
    } finally {
      await host.closeWindow(window);
      host.dispose();
    }
  });

  test('the text area of the native window edits several lines', () async {
    final host = await SdlSkiaHost.initialize();
    final area = TextArea(text: 'one', fontSize: 16);
    final window = Window(width: 320, height: 200, content: area);
    try {
      await host.showWindow(window);
      window.updateLayout();
      area.focus();

      window.dispatchKeyDown('enter', shiftPressed: true);
      if (area.text != 'one\n') {
        throw StateError('Shift+Enter did not start a new line.');
      }
      window.dispatchTextInput('a');
      if (area.text != 'one\na') {
        throw StateError('The text after the new line was not typed.');
      }

      // The text is longer than the area, so the area scrolls it.
      final long = TextArea(text: veryLongText, fontSize: 16);
      final longWindow = Window(width: 320, height: 100, content: long);
      await host.showWindow(longWindow);
      longWindow.updateLayout();
      if (!long.isScrollBarVisible) {
        throw StateError('The text area did not show the vertical scroll bar.');
      }
      // The caret starts at the end of the text, so the area shows the end.
      long.moveCaret(0);
      longWindow.updateLayout();
      if (long.verticalOffset >= 1) {
        throw StateError('The text area did not scroll back to the top.');
      }
      long.moveCaret(long.text.length);
      longWindow.updateLayout();
      if (long.verticalOffset <= 0) {
        throw StateError('The text area did not scroll to the caret.');
      }
      await host.closeWindow(longWindow);
    } finally {
      await host.closeWindow(window);
      host.dispose();
    }
  });
}
