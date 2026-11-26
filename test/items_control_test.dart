import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('ItemsControl', () {
    test('creates templated children and reuses unaffected siblings', () {
      final items = ObservableCollection<String>(['a', 'b']);
      var created = 0;
      final control = ItemsControl<String>(
        itemsSource: items,
        itemTemplate: (item) {
          created++;
          return Label(text: item);
        },
      );
      Window(width: 200, height: 100, content: control);
      final a = control.elementAt(0);
      final b = control.elementAt(1);

      items.add('c');
      expect(control.elementAt(0), same(a));
      expect(control.elementAt(1), same(b));
      expect(control.containerCount, 3);

      items.insert(1, 'inserted');
      expect(control.elementAt(0), same(a));
      expect(control.elementAt(2), same(b));
      expect(control.containerCount, 4);

      items.removeAt(0);
      expect(control.elementAt(0), isNot(same(a)));
      expect(control.elementAt(1), same(b));
      expect(control.containerCount, 3);
      expect(a!.logicalParent, isNull);
      expect(a.isMounted, isFalse);

      final inserted = control.elementAt(0);
      items[0] = 'replacement';
      expect(control.elementAt(0), isNot(same(inserted)));
      expect(control.elementAt(1), same(b));
      expect(created, 5);
    });

    test('move retains identity, data context and focus', () {
      final items = ObservableCollection<String>(['a', 'b', 'c']);
      final control = ItemsControl<String>(
        itemsSource: items,
        itemTemplate: (item) => _FixedControl(const Size(40, 24)),
      );
      final window = Window(width: 200, height: 100, content: control);
      final a = control.elementForKey('a')!;

      (a as Control).focus();
      items.move(0, 2);

      expect(control.elementAt(2), same(a));
      expect(a.dataContext, 'a');
      expect(a.logicalParent, same(control));
      expect(window.focusedElement, same(a));
    });

    test('reset reuses equal keys and rejects duplicates', () {
      final items = ObservableCollection<String>(['a', 'b']);
      final control = ItemsControl<String>(itemsSource: items);
      Window(width: 200, height: 100, content: control);
      final a = control.elementForKey('a');
      final b = control.elementForKey('b');

      items.reset(['b', 'a', 'c']);

      expect(control.elementAt(0), same(b));
      expect(control.elementAt(1), same(a));
      expect(control.elementAt(2)!.dataContext, 'c');
      expect(() => items.reset(['a', 'a']), throwsArgumentError);
      expect(
        () => ItemsControl<String>(itemsSource: ['x', 'x']),
        throwsArgumentError,
      );
    });

    test('replacing the source unsubscribes the old collection', () {
      final oldItems = ObservableCollection<String>(['old']);
      final newItems = ObservableCollection<String>(['new']);
      final control = ItemsControl<String>(itemsSource: oldItems);
      Window(width: 200, height: 100, content: control);

      control.itemsSource = newItems;
      oldItems.add('ignored');
      newItems.add('added');

      expect(control.containerCount, 2);
      expect(control.elementAt(0)!.dataContext, 'new');
      expect(control.elementAt(1)!.dataContext, 'added');
    });

    test('removing the focused item unmounts it and clears focus', () {
      final items = ObservableCollection<String>(['a', 'b']);
      final control = ItemsControl<String>(
        itemsSource: items,
        itemTemplate: (item) => _FixedControl(const Size(40, 24)),
      );
      final window = Window(width: 200, height: 100, content: control);
      final a = control.elementAt(0)!;
      expect((a as Control).focus(), isTrue);

      items.removeAt(0);

      expect(a.logicalParent, isNull);
      expect(a.isMounted, isFalse);
      expect(a.isFocused, isFalse);
      expect(window.focusedElement, isNull);
    });
  });

  group('VirtualizingStackPanel', () {
    test('materializes only the viewport of 100000 items', () {
      final fixture = _virtualFixture(100000);

      expect(fixture.panel.containerCount, lessThan(50));
      expect(fixture.panel.containerCount, greaterThan(2));
      expect(fixture.panel.firstVisibleIndex, 0);
      expect(fixture.panel.elementAt(0), isNotNull);
      expect(fixture.panel.elementAt(100), isNull);
      expect(fixture.viewer.extentHeight, closeTo(2400000, 0.001));
      expect(fixture.panel.elementAt(0)!.bounds,
          const Rect.fromLTWH(0, 0, 308, 24));
    });

    test('scrolls to the middle and end with correct bounds', () {
      final fixture = _virtualFixture(100000);
      final initial = fixture.panel.elementAt(0)!;

      fixture.viewer.scrollTo(vertical: 24 * 50000);
      fixture.window.updateLayout();

      expect(fixture.panel.containerCount, lessThan(50));
      expect(fixture.panel.firstVisibleIndex, 49998);
      expect(fixture.panel.elementAt(50000), isNotNull);
      expect(fixture.panel.elementAt(50000)!.bounds.top, 0);
      expect(initial.isMounted, isFalse);
      expect(initial.logicalParent, isNull);

      fixture.viewer.scrollToEnd();
      fixture.window.updateLayout();

      expect(fixture.panel.elementAt(99999), isNotNull);
      expect(fixture.panel.elementAt(99999)!.bounds.bottom,
          fixture.viewer.viewportHeight);
      expect(fixture.panel.containerCount, lessThan(50));
    });

    test('keeps overlapping containers across arrange and move', () {
      final items = ObservableCollection<int>.generate(1000, (index) => index);
      final fixture = _virtualFixture(1000, items: items);
      final existing = {
        for (var index = fixture.panel.firstVisibleIndex;
            index <= fixture.panel.lastVisibleIndex;
            index++)
          index: fixture.panel.elementAt(index)!,
      };

      fixture.viewer.scrollTo(vertical: 24);
      fixture.window.updateLayout();
      for (final entry in existing.entries.skip(1)) {
        expect(fixture.panel.elementForKey(entry.key), same(entry.value));
      }

      final focused = fixture.panel.elementForKey(5)!;
      (focused as Control).focus();
      items.move(5, 6);
      fixture.window.updateLayout();
      expect(fixture.panel.elementForKey(5), same(focused));
      expect(fixture.window.focusedElement, same(focused));
    });

    test('recycling clears focus and does not leak selection state', () {
      final fixture = _virtualFixture(1000);
      final focused = fixture.panel.elementAt(0)! as _FixedControl;
      focused.isSelected = true;
      focused.focus();

      fixture.viewer.scrollTo(vertical: 24 * 500);
      fixture.window.updateLayout();

      expect(focused.isMounted, isFalse);
      expect(focused.isFocused, isFalse);
      expect(fixture.window.focusedElement, isNull);

      fixture.viewer.scrollToStart();
      fixture.window.updateLayout();
      final recreated = fixture.panel.elementAt(0)! as _FixedControl;
      expect(recreated, isNot(same(focused)));
      expect(recreated.isSelected, isFalse);
    });

    test('uses measured variable item heights', () {
      final panel = VirtualizingStackPanel<int>(
        itemsSource: List<int>.generate(100, (index) => index),
        estimatedItemExtent: 20,
        itemTemplate: (item) => _FixedControl(Size(40, item.isEven ? 20 : 40)),
      );
      final viewer = ScrollViewer(
        content: panel,
        horizontalScrollBarVisibility: ScrollBarVisibility.disabled,
      );
      final window = Window(width: 200, height: 100, content: viewer);
      window.updateLayout();

      viewer.scrollTo(vertical: 600);
      window.updateLayout();

      expect(panel.containerCount, lessThan(20));
      expect(panel.elementAt(panel.firstVisibleIndex), isNotNull);
      expect(viewer.extentHeight, greaterThan(2000));
      expect(panel.elementAt(20)?.bounds.height, anyOf(isNull, 20));
      expect(panel.elementAt(21)?.bounds.height, anyOf(isNull, 40));
    });
  });
}

_VirtualFixture _virtualFixture(
  int count, {
  ObservableCollection<int>? items,
}) {
  final panel = VirtualizingStackPanel<int>(
    itemsSource: items ?? List<int>.generate(count, (index) => index),
    estimatedItemExtent: 24,
    itemTemplate: (item) => _FixedControl(const Size(40, 24)),
  );
  final viewer = ScrollViewer(
    content: panel,
    horizontalScrollBarVisibility: ScrollBarVisibility.disabled,
  );
  final window = Window(width: 320, height: 200, content: viewer);
  window.updateLayout();
  return _VirtualFixture(window, viewer, panel);
}

final class _VirtualFixture {
  _VirtualFixture(this.window, this.viewer, this.panel);

  final Window window;
  final ScrollViewer viewer;
  final VirtualizingStackPanel<int> panel;
}

final class _FixedControl extends Control {
  _FixedControl(this.size);

  final Size size;
  bool isSelected = false;

  @override
  Size measureCore(Size availableSize) => size;
}
