import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  test('add, insert and remove publish precise changes', () {
    final items = ObservableCollection<String>(['b']);
    final events = <CollectionChangedEvent<String>>[];
    items.subscribe(events.add);

    items.add('c');
    items.insert(0, 'a');
    expect(items.removeAt(1), 'b');

    expect(items, ['a', 'c']);
    expect(events.map((event) => event.action), [
      CollectionChangeAction.add,
      CollectionChangeAction.insert,
      CollectionChangeAction.remove,
    ]);
    expect(events[0].index, 1);
    expect(events[0].addedItems, ['c']);
    expect(events[1].index, 0);
    expect(events[1].addedItems, ['a']);
    expect(events[2].index, 1);
    expect(events[2].removedItems, ['b']);
  });

  test('replace, move and reset include old and new values', () {
    final items = ObservableCollection<String>(['a', 'b', 'c']);
    final events = <CollectionChangedEvent<String>>[];
    items.subscribe(events.add);

    items[1] = 'B';
    items.move(2, 0);
    items.reset(['x', 'y']);

    expect(events[0].action, CollectionChangeAction.replace);
    expect(events[0].index, 1);
    expect(events[0].addedItems, ['B']);
    expect(events[0].removedItems, ['b']);
    expect(events[1].action, CollectionChangeAction.move);
    expect(events[1].oldIndex, 2);
    expect(events[1].index, 0);
    expect(events[1].addedItems, ['c']);
    expect(events[1].removedItems, ['c']);
    expect(events[2].action, CollectionChangeAction.reset);
    expect(events[2].addedItems, ['x', 'y']);
    expect(events[2].removedItems, ['c', 'a', 'B']);
    expect(
        () => events[0].addedItems.add('unexpected'), throwsUnsupportedError);
  });

  test('clear and length truncation emit reset with removed items', () {
    final items = ObservableCollection<int>([1, 2, 3]);
    final events = <CollectionChangedEvent<int>>[];
    items.subscribe(events.add);

    items.length = 1;
    items.clear();
    items.clear();

    expect(items, isEmpty);
    expect(events, hasLength(2));
    expect(events[0].removedItems, [2, 3]);
    expect(events[1].removedItems, [1]);
    expect(() => items.length = 3, throwsUnsupportedError);
  });

  test('subscriptions cancel independently and listeners are snapshotted', () {
    final items = ObservableCollection<int>();
    final calls = <String>[];
    late CollectionSubscription second;
    final first = items.subscribe((event) {
      calls.add('first');
      second.cancel();
    });
    second = items.subscribe((event) => calls.add('second'));
    items.subscribe((event) => calls.add('third'));

    items.add(1);
    expect(calls, ['first', 'second', 'third']);
    expect(second.isCancelled, isTrue);

    calls.clear();
    first.cancel();
    first.cancel();
    items.add(2);
    expect(calls, ['third']);
  });

  test('removeListener stops future notifications', () {
    final items = ObservableCollection<int>();
    var calls = 0;
    void listener(CollectionChangedEvent<int> event) => calls++;
    items.addListener(listener);
    items.add(1);
    items.removeListener(listener);
    items.add(2);

    expect(calls, 1);
  });

  test('dispose is idempotent and prohibits changes and subscriptions', () {
    final items = ObservableCollection<int>([1]);
    items.dispose();
    items.dispose();

    expect(items.isDisposed, isTrue);
    expect(items, [1]);
    expect(() => items.add(2), throwsStateError);
    expect(() => items[0] = 2, throwsStateError);
    expect(() => items.reset([2]), throwsStateError);
    expect(() => items.subscribe((event) {}), throwsStateError);
  });
}
