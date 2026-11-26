import 'dart:collection';

enum CollectionChangeAction { add, insert, remove, replace, move, reset }

final class CollectionChangedEvent<T> {
  CollectionChangedEvent._(
    this.action, {
    this.index = -1,
    this.oldIndex = -1,
    Iterable<T> addedItems = const [],
    Iterable<T> removedItems = const [],
  })  : addedItems = List.unmodifiable(addedItems),
        removedItems = List.unmodifiable(removedItems);

  final CollectionChangeAction action;
  final int index;
  final int oldIndex;
  final List<T> addedItems;
  final List<T> removedItems;
}

typedef CollectionChangedListener<T> = void Function(
  CollectionChangedEvent<T> event,
);

final class CollectionSubscription {
  CollectionSubscription._(this._cancel);

  final void Function() _cancel;
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _cancel();
  }
}

final class ObservableCollection<T> extends ListBase<T> {
  ObservableCollection([Iterable<T> items = const []])
      : _items = List<T>.of(items);

  factory ObservableCollection.generate(
    int length,
    T Function(int) generator,
  ) =>
      ObservableCollection(List<T>.generate(length, generator));

  final List<T> _items;
  final _listeners = <CollectionChangedListener<T>>[];
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;

  @override
  int get length => _items.length;

  @override
  set length(int value) {
    _checkNotDisposed();
    if (value < 0) throw RangeError.value(value, 'length');
    if (value < length) {
      final removed = _items.sublist(value);
      _items.removeRange(value, length);
      _notify(CollectionChangedEvent<T>._(
        CollectionChangeAction.reset,
        removedItems: removed,
      ));
      return;
    }
    if (value == length) return;
    throw UnsupportedError(
      'Add items explicitly instead of extending the collection length.',
    );
  }

  @override
  T operator [](int index) => _items[index];

  @override
  void operator []=(int index, T value) {
    _checkNotDisposed();
    final oldValue = _items[index];
    if (oldValue == value) return;
    _items[index] = value;
    _notify(CollectionChangedEvent<T>._(
      CollectionChangeAction.replace,
      index: index,
      addedItems: [value],
      removedItems: [oldValue],
    ));
  }

  @override
  void add(T element) {
    _checkNotDisposed();
    final index = length;
    _items.add(element);
    _notify(CollectionChangedEvent<T>._(
      CollectionChangeAction.add,
      index: index,
      addedItems: [element],
    ));
  }

  @override
  void insert(int index, T element) {
    _checkNotDisposed();
    RangeError.checkValidIndex(index, _items, 'index', length + 1);
    _items.insert(index, element);
    _notify(CollectionChangedEvent<T>._(
      CollectionChangeAction.insert,
      index: index,
      addedItems: [element],
    ));
  }

  @override
  T removeAt(int index) {
    _checkNotDisposed();
    final element = _items.removeAt(index);
    _notify(CollectionChangedEvent<T>._(
      CollectionChangeAction.remove,
      index: index,
      removedItems: [element],
    ));
    return element;
  }

  @override
  void clear() {
    _checkNotDisposed();
    if (isEmpty) return;
    final removed = List<T>.of(_items);
    _items.clear();
    _notify(CollectionChangedEvent<T>._(
      CollectionChangeAction.reset,
      removedItems: removed,
    ));
  }

  void move(int oldIndex, int newIndex) {
    _checkNotDisposed();
    RangeError.checkValidIndex(oldIndex, _items, 'oldIndex');
    RangeError.checkValidIndex(newIndex, _items, 'newIndex');
    if (oldIndex == newIndex) return;
    final element = _items.removeAt(oldIndex);
    _items.insert(newIndex, element);
    _notify(CollectionChangedEvent<T>._(
      CollectionChangeAction.move,
      index: newIndex,
      oldIndex: oldIndex,
      addedItems: [element],
      removedItems: [element],
    ));
  }

  void reset(Iterable<T> items) {
    _checkNotDisposed();
    final oldItems = List<T>.of(_items);
    final newItems = List<T>.of(items);
    _items
      ..clear()
      ..addAll(newItems);
    _notify(CollectionChangedEvent<T>._(
      CollectionChangeAction.reset,
      addedItems: newItems,
      removedItems: oldItems,
    ));
  }

  CollectionSubscription subscribe(CollectionChangedListener<T> listener) {
    _checkNotDisposed();
    _listeners.add(listener);
    return CollectionSubscription._(() => removeListener(listener));
  }

  void addListener(CollectionChangedListener<T> listener) {
    _checkNotDisposed();
    _listeners.add(listener);
  }

  void removeListener(CollectionChangedListener<T> listener) {
    _listeners.remove(listener);
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _listeners.clear();
  }

  void _checkNotDisposed() {
    if (_isDisposed) throw StateError('The collection is disposed.');
  }

  void _notify(CollectionChangedEvent<T> event) {
    for (final listener in List<CollectionChangedListener<T>>.of(_listeners)) {
      listener(event);
    }
  }
}
