import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  test('dock attached property defaults to left and invalidates parent layout',
      () {
    final child = _FixedElement(const Size(30, 20));
    final panel = DockPanel(lastChildFill: false, children: [child]);

    expect(DockPanel.getDock(child), Dock.left);
    _layout(panel);
    expect(child.bounds, const Rect.fromLTWH(0, 0, 30, 100));

    DockPanel.setDock(child, Dock.top);
    _layout(panel);

    expect(DockPanel.getDock(child), Dock.top);
    expect(child.bounds, const Rect.fromLTWH(0, 0, 200, 20));
  });

  test('children sequentially consume space on all four sides', () {
    final left = _FixedElement(const Size(30, 20));
    final top = _FixedElement(const Size(40, 15));
    final right = _FixedElement(const Size(25, 20));
    final bottom = _FixedElement(const Size(35, 10));
    DockPanel.setDock(top, Dock.top);
    DockPanel.setDock(right, Dock.right);
    DockPanel.setDock(bottom, Dock.bottom);
    final panel = DockPanel(
      lastChildFill: false,
      children: [left, top, right, bottom],
    );

    _layout(panel);

    expect(panel.desiredSize, const Size(55, 25));
    expect(left.bounds, const Rect.fromLTWH(0, 0, 30, 100));
    expect(top.bounds, const Rect.fromLTWH(30, 0, 170, 15));
    expect(right.bounds, const Rect.fromLTWH(175, 15, 25, 85));
    expect(bottom.bounds, const Rect.fromLTWH(30, 90, 145, 10));
  });

  test('last visible child fills the remaining rectangle by default', () {
    final left = _FixedElement(const Size(30, 20));
    final top = _FixedElement(const Size(20, 10));
    final fill = _FixedElement(const Size(50, 40));
    final hidden = _FixedElement(const Size(100, 100))..isVisible = false;
    DockPanel.setDock(top, Dock.top);
    final panel = DockPanel(children: [left, top, fill, hidden]);

    _layout(panel);

    expect(panel.desiredSize, const Size(80, 50));
    expect(left.bounds, const Rect.fromLTWH(0, 0, 30, 100));
    expect(top.bounds, const Rect.fromLTWH(30, 0, 170, 10));
    expect(fill.bounds, const Rect.fromLTWH(30, 10, 170, 90));
    expect(hidden.bounds, Rect.zero);
  });

  test('lastChildFill can be changed after the initial layout', () {
    final left = _FixedElement(const Size(30, 20));
    final last = _FixedElement(const Size(50, 40));
    final panel = DockPanel(
      lastChildFill: false,
      children: [left, last],
    );

    _layout(panel);
    expect(last.bounds, const Rect.fromLTWH(30, 0, 50, 100));

    panel.lastChildFill = true;
    _layout(panel);

    expect(last.bounds, const Rect.fromLTWH(30, 0, 170, 100));
  });

  test('docked children consume margins while alignment uses their slots', () {
    final left = _FixedElement(const Size(30, 20))
      ..margin = const EdgeInsets.symmetric(horizontal: 5, vertical: 3);
    final fill = _FixedElement(const Size(10, 10));
    final panel = DockPanel(children: [left, fill]);

    _layout(panel);

    expect(left.desiredSize, const Size(40, 26));
    expect(left.bounds, const Rect.fromLTWH(5, 3, 30, 94));
    expect(fill.bounds, const Rect.fromLTWH(40, 0, 160, 100));
  });

  test('oversized docked child cannot create negative remaining space', () {
    final left = _FixedElement(const Size(30, 20));
    final fill = _FixedElement(const Size(50, 40));
    final panel = DockPanel(children: [left, fill]);

    _layout(panel, available: const Size(20, 10));

    expect(left.bounds, const Rect.fromLTWH(0, 0, 20, 10));
    expect(fill.bounds, const Rect.fromLTWH(20, 0, 0, 10));
  });

  test('infinite cross axis remains finite in measured child geometry', () {
    final left = _FixedElement(const Size(30, 20));
    final fill = _FixedElement(const Size(50, 40));
    final panel = DockPanel(children: [left, fill]);

    panel.measure(const Size(double.infinity, 100));
    panel.arrange(const Rect.fromLTWH(0, 0, 200, 100));

    expect(panel.desiredSize, const Size(80, 40));
    expect(left.bounds, const Rect.fromLTWH(0, 0, 30, 100));
    expect(fill.bounds, const Rect.fromLTWH(30, 0, 170, 100));
  });
}

void _layout(
  DockPanel panel, {
  Size available = const Size(200, 100),
}) {
  panel.measure(available);
  panel.arrange(Rect.fromLTWH(0, 0, available.width, available.height));
}

final class _FixedElement extends UIElement {
  _FixedElement(this.size);

  final Size size;

  @override
  Size measureCore(Size availableSize) => size;
}
