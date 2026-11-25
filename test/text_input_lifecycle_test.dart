import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  test('focus starts input and caret changes update the input area', () async {
    final handler = _RecordingTextInputHandler();
    final box = TextBox(text: 'abc');
    final button = Button();
    final window = Window(
      content: StackPanel(children: [box, button]),
    )..textInputHandler = handler;
    await window.show();

    box.focus();
    expect(handler.startCount, 1);
    expect(handler.areas, isNotEmpty);

    window.renderFrame(RecordingDrawingContext());
    final areaCount = handler.areas.length;
    box.moveCaret(0);

    expect(handler.areas.length, areaCount + 1);
    expect(handler.areas.last.cursorX, 0);
    expect(handler.areas.last.area.width, greaterThan(0));

    button.focus();
    expect(handler.stopCount, 1);
    expect(box.isFocused, isFalse);
  });

  test('focus before show starts input when the window becomes visible',
      () async {
    final handler = _RecordingTextInputHandler();
    final box = TextBox();
    final window = Window(content: box)..textInputHandler = handler;

    box.focus();
    expect(handler.startCount, 0);

    await window.show();
    expect(handler.startCount, 1);
    expect(handler.areas, isNotEmpty);
  });

  test('unmounting a focused TextBox stops input', () async {
    final handler = _RecordingTextInputHandler();
    final box = TextBox();
    final window = Window(content: box)..textInputHandler = handler;
    await window.show();
    box.focus();

    window.content = null;

    expect(handler.stopCount, 1);
    expect(box.isMounted, isFalse);
  });

  test('closing a window stops input before unmount', () async {
    final handler = _RecordingTextInputHandler();
    final box = TextBox();
    final window = Window(content: box)..textInputHandler = handler;
    await window.show();
    box.focus();

    window.close();

    expect(handler.stopCount, 1);
    expect(box.isMounted, isFalse);
  });
}

final class _RecordingTextInputHandler implements TextInputHandler {
  int startCount = 0;
  int stopCount = 0;
  final areas = <({Rect area, double cursorX})>[];

  @override
  void startTextInput(Window window) => startCount++;

  @override
  void stopTextInput(Window window) => stopCount++;

  @override
  void setTextInputArea(Window window, Rect area, double cursorX) {
    areas.add((area: area, cursorX: cursorX));
  }
}
