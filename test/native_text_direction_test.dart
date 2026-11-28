@Tags(['native'])
library;

import 'package:duix/dui.dart';
import 'package:duix/native.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

/// The direction of a paragraph is a part of the native ABI.
///
/// The direction of the paragraph is the base direction of the text: it
/// decides where the runs of a line stand. The runs themselves keep their own
/// direction, so a Hebrew run inside a left to right paragraph is still read
/// from right to left.
void main() {
  late NativeBindings bindings;

  setUpAll(() {
    bindings = NativeBindings.open();
  });

  const mixed = 'abc שלום';
  const hebrew = 'שלום';

  test('a right to left paragraph puts the first run at the right', () {
    final arena = Arena();
    try {
      final rightToLeft = bindings.textLayoutCreate(
        text: mixed,
        fontSize: 16,
        maxWidth: 1000,
        scale: 1,
        direction: 1,
        arena: arena,
      );
      final leftToRight = bindings.textLayoutCreate(
        text: mixed,
        fontSize: 16,
        maxWidth: 1000,
        scale: 1,
        direction: 0,
        arena: arena,
      );
      final rightStart = bindings.textLayoutCaretRect(rightToLeft, 0, arena);
      final leftStart = bindings.textLayoutCaretRect(leftToRight, 0, arena);
      bindings.textLayoutDestroy(rightToLeft);
      bindings.textLayoutDestroy(leftToRight);

      expect(
        leftStart.left,
        closeTo(0, 0.001),
        reason: 'the first run of a left to right line stands at the left',
      );
      expect(
        rightStart.left,
        greaterThan(leftStart.left),
        reason: 'the first run of a right to left line stands at the right',
      );
    } finally {
      arena.releaseAll();
    }
  });

  test(
      'the caret of the first character of a right to left text is at the '
      'right', () {
    final arena = Arena();
    try {
      final layout = bindings.textLayoutCreate(
        text: hebrew,
        fontSize: 16,
        maxWidth: 1000,
        scale: 1,
        direction: 1,
        arena: arena,
      );
      final metrics = bindings.textLayoutMeasure(layout, arena);
      final start = bindings.textLayoutCaretRect(layout, 0, arena);
      final end = bindings.textLayoutCaretRect(layout, hebrew.length, arena);
      bindings.textLayoutDestroy(layout);

      expect(metrics.width, greaterThan(0));
      expect(start.left, greaterThan(end.left));
      expect(
        start.left,
        closeTo(metrics.width, 0.01),
        reason: 'the caret of the first character is the right edge of the '
            'text',
      );
    } finally {
      arena.releaseAll();
    }
  });

  test('the text of a right to left field starts at the right edge', () async {
    final host = await SdlSkiaHost.initialize();
    final box = TextBox(text: hebrew, fontSize: 16);
    final window = Window(width: 320, height: 120, content: box)
      ..flowDirection = FlowDirection.rightToLeft;
    try {
      await host.showWindow(window);
      window.updateLayout();
      final part = box.textPart;
      final position = Point(part.bounds.right - 1, part.bounds.top + 8);

      window.dispatchPointerDown(position);
      window.dispatchPointerUp(position);

      expect(
        box.caretOffset,
        lessThan(2),
        reason: 'the click at the right edge of the field has to reach the '
            'first character of the text',
      );
    } finally {
      await host.closeWindow(window);
      host.dispose();
    }
  });

  test('the text of a left to right field starts at the left edge', () async {
    final host = await SdlSkiaHost.initialize();
    final box = TextBox(text: hebrew, fontSize: 16);
    final window = Window(width: 320, height: 120, content: box);
    try {
      await host.showWindow(window);
      window.updateLayout();
      final part = box.textPart;
      final position = Point(part.bounds.left + 1, part.bounds.top + 8);

      window.dispatchPointerDown(position);
      window.dispatchPointerUp(position);

      expect(
        box.caretOffset,
        greaterThan(2),
        reason: 'the click at the left edge of the field has to reach the '
            'last character of the text, because the text of a Hebrew run is '
            'read from right to left',
      );
    } finally {
      await host.closeWindow(window);
      host.dispose();
    }
  });
}
