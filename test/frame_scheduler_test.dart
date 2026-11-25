import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  test('scheduler coalesces invalidations and separates layout from paint',
      () async {
    final text = TextBlock(text: 'Initial');
    final window = Window(width: 200, height: 100, content: text);
    var wakeUps = 0;
    window.setFrameRequestHandler(() => wakeUps++);
    await window.show();
    final renderer = RecordingDrawingContext();

    window.renderFrame(renderer);
    expect(
      (
        window.scheduledFrameCount,
        window.layoutPassCount,
        window.paintPassCount,
        wakeUps
      ),
      (1, 1, 1, 1),
    );

    text.text = 'First';
    text.text = 'Second';
    text.color = const Color(0xFF123456);
    window.requestFrame();
    expect(window.frameScheduled, isTrue);
    expect(window.scheduledFrameCount, 2);
    expect(wakeUps, 2);

    window.renderFrame(renderer);
    expect(
      (
        window.scheduledFrameCount,
        window.layoutPassCount,
        window.paintPassCount
      ),
      (2, 2, 2),
    );
    expect(text.text, 'Second');
    expect(window.frameScheduled, isFalse);

    renderer.commands.clear();
    window.renderFrame(renderer);
    expect(renderer.commands, isEmpty);
    expect(window.layoutPassCount, 2);
    expect(window.paintPassCount, 2);
  });

  test('invalidate during paint preserves the next scheduled frame', () async {
    final text = TextBlock(text: 'Initial');
    final window = Window(content: text);
    await window.show();
    window.renderFrame(RecordingDrawingContext());

    var invalidateDuringPaint = true;
    final paint = _PaintCallbackElement(() {
      if (!invalidateDuringPaint) return;
      invalidateDuringPaint = false;
      window.requestFrame();
    });
    window.content = paint;
    window.renderFrame(RecordingDrawingContext());

    expect(window.frameScheduled, isTrue);
    expect(window.scheduledFrameCount, 3);
    window.renderFrame(RecordingDrawingContext());
    expect(window.frameScheduled, isFalse);
  });

  test('recursive layout is rejected and the scheduler recovers', () async {
    late Window window;
    final element = _RecursiveLayoutElement(() => window.updateLayout());
    window = Window(content: element);
    await window.show();

    expect(
      () => window.renderFrame(RecordingDrawingContext()),
      throwsStateError,
    );
    expect(window.layoutPassCount, 0);

    window.content = TextBlock(text: 'Recovered');
    window.renderFrame(RecordingDrawingContext());
    expect(window.layoutPassCount, 1);
    expect(window.paintPassCount, 1);
  });
}

final class _PaintCallbackElement extends UIElement {
  _PaintCallbackElement(this.onPaint);

  final void Function() onPaint;

  @override
  Size measureCore(Size availableSize) => Size.zero;

  @override
  void renderCore(DrawingContext context) => onPaint();
}

final class _RecursiveLayoutElement extends UIElement {
  _RecursiveLayoutElement(this.onMeasure);

  final void Function() onMeasure;

  @override
  Size measureCore(Size availableSize) {
    onMeasure();
    return Size.zero;
  }
}
