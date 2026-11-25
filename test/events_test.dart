import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  test('events tunnel and bubble through the retained tree', () async {
    final child = TextBlock(text: 'target');
    final root = StackPanel(children: [child]);
    final window = Window(width: 200, height: 100, content: root);
    await window.show();
    final calls = <String>[];

    root.addHandler(
        UIElement.previewPointerDown, (_, __) => calls.add('root preview'));
    child.addHandler(
        UIElement.previewPointerDown, (_, __) => calls.add('child preview'));
    child.addHandler(
        UIElement.pointerDown, (_, __) => calls.add('child bubble'));
    root.addHandler(UIElement.pointerDown, (_, __) => calls.add('root bubble'));

    window.dispatchPointerDown(const Point(1, 1));

    expect(calls, [
      'root preview',
      'child preview',
      'child bubble',
      'root bubble',
    ]);
  });

  test('handled event stops bubbling', () async {
    final child = TextBlock(text: 'target');
    final root = StackPanel(children: [child]);
    final window = Window(width: 200, height: 100, content: root);
    await window.show();
    var rootCalled = false;

    child.addHandler(UIElement.pointerDown, (_, args) => args.handled = true);
    root.addHandler(UIElement.pointerDown, (_, __) => rootCalled = true);

    window.dispatchPointerDown(const Point(1, 1));

    expect(rootCalled, isFalse);
  });
}
