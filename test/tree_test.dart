import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  test('children receive parent and window lifecycle', () async {
    final child = TextBlock(text: 'child');
    final panel = StackPanel();
    final window = Window(content: panel);
    await window.show();

    panel.children.add(child);

    expect(child.logicalParent, same(panel));
    expect(child.window, same(window));
    expect(child.isMounted, isTrue);

    panel.children.remove(child);
    expect(child.logicalParent, isNull);
    expect(child.window, isNull);
    expect(child.isMounted, isFalse);
  });

  test('an element cannot have two parents', () {
    final child = TextBlock();
    StackPanel(children: [child]);

    expect(() => StackPanel(children: [child]), throwsStateError);
  });

  test('StackPanel measures and arranges children vertically', () {
    final first = TextBlock(text: 'a', fontSize: 10);
    final second = TextBlock(text: 'b', fontSize: 10);
    final panel = StackPanel(spacing: 5, children: [first, second]);

    panel.measure(const Size(200, 200));
    panel.arrange(const Rect.fromLTWH(0, 0, 200, 200));

    expect(first.bounds.top, 0);
    expect(second.bounds.top, 18);
    expect(first.bounds.width, 200);
  });
}
