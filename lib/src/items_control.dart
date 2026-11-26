import 'dart:math' as math;

import 'drawing.dart';
import 'geometry.dart';
import 'label.dart';
import 'observable_collection.dart';
import 'scroll_viewer.dart';
import 'ui_element.dart';

typedef ItemTemplate<T> = UIElement Function(T item);
typedef ItemKeySelector<T> = Object? Function(T item);

class ItemsControl<T> extends UIElement {
  ItemsControl({
    Iterable<T> itemsSource = const [],
    ItemTemplate<T>? itemTemplate,
    ItemKeySelector<T>? keySelector,
    double spacing = 0,
    EdgeInsets padding = EdgeInsets.zero,
  }) : this._internal(
          itemsSource: itemsSource,
          itemTemplate: itemTemplate,
          keySelector: keySelector,
          spacing: spacing,
          padding: padding,
          virtualizing: false,
          estimatedItemExtent: 24,
        );

  ItemsControl.virtualizing({
    Iterable<T> itemsSource = const [],
    ItemTemplate<T>? itemTemplate,
    ItemKeySelector<T>? keySelector,
    double spacing = 0,
    EdgeInsets padding = EdgeInsets.zero,
    double estimatedItemExtent = 24,
  }) : this._internal(
          itemsSource: itemsSource,
          itemTemplate: itemTemplate,
          keySelector: keySelector,
          spacing: spacing,
          padding: padding,
          virtualizing: true,
          estimatedItemExtent: estimatedItemExtent,
        );

  ItemsControl._internal({
    required Iterable<T> itemsSource,
    required ItemTemplate<T>? itemTemplate,
    required ItemKeySelector<T>? keySelector,
    required double spacing,
    required EdgeInsets padding,
    required bool virtualizing,
    required double estimatedItemExtent,
  })  : _itemsSource = itemsSource,
        _itemTemplate = itemTemplate ?? _defaultTemplate,
        _keySelector = keySelector ?? _defaultKey,
        _spacing = spacing,
        _padding = padding,
        _virtualizing = virtualizing,
        _estimatedItemExtent = estimatedItemExtent {
    if (spacing < 0 || !spacing.isFinite) {
      throw ArgumentError.value(spacing, 'spacing');
    }
    if (estimatedItemExtent <= 0 || !estimatedItemExtent.isFinite) {
      throw ArgumentError.value(estimatedItemExtent, 'estimatedItemExtent');
    }
    _reconcileAll();
  }

  Iterable<T> _itemsSource;
  ItemTemplate<T> _itemTemplate;
  ItemKeySelector<T> _keySelector;
  double _spacing;
  EdgeInsets _padding;
  final bool _virtualizing;
  double _estimatedItemExtent;
  final _containers = <_ItemContainer<T>>[];
  final _containersByKey = <Object?, _ItemContainer<T>>{};
  final _knownHeights = <int, double>{};
  CollectionSubscription? _sourceSubscription;
  int _firstVisibleIndex = -1;
  int _lastVisibleIndex = -1;

  static UIElement _defaultTemplate<S>(S item) => Label(text: '$item');
  static Object? _defaultKey<S>(S item) => item;

  Iterable<T> get itemsSource => _itemsSource;
  set itemsSource(Iterable<T> value) {
    _checkNotDisposed();
    if (identical(_itemsSource, value)) return;
    _unsubscribe();
    _itemsSource = value;
    _reconcileAll();
    _subscribe();
  }

  ItemTemplate<T> get itemTemplate => _itemTemplate;
  set itemTemplate(ItemTemplate<T> value) {
    _checkNotDisposed();
    if (identical(_itemTemplate, value)) return;
    _itemTemplate = value;
    _removeAllContainers();
    _reconcileAll();
  }

  ItemKeySelector<T> get keySelector => _keySelector;
  set keySelector(ItemKeySelector<T> value) {
    _checkNotDisposed();
    if (identical(_keySelector, value)) return;
    _keySelector = value;
    _removeAllContainers();
    _reconcileAll();
  }

  double get spacing => _spacing;
  set spacing(double value) {
    if (value < 0 || !value.isFinite) {
      throw ArgumentError.value(value, 'spacing');
    }
    if (_spacing == value) return;
    _spacing = value;
    invalidateMeasure();
  }

  EdgeInsets get padding => _padding;
  set padding(EdgeInsets value) {
    if (_padding == value) return;
    _padding = value;
    invalidateMeasure();
  }

  double get estimatedItemExtent => _estimatedItemExtent;
  set estimatedItemExtent(double value) {
    if (!_virtualizing) {
      throw StateError('Estimated extent is used only by virtualizing items.');
    }
    if (value <= 0 || !value.isFinite) {
      throw ArgumentError.value(value, 'estimatedItemExtent');
    }
    if (_estimatedItemExtent == value) return;
    _estimatedItemExtent = value;
    invalidateMeasure();
  }

  int get containerCount => _containers.length;
  int get firstVisibleIndex => _firstVisibleIndex;
  int get lastVisibleIndex => _lastVisibleIndex;

  UIElement? elementAt(int index) {
    for (final container in _containers) {
      if (container.index == index) return container.element;
    }
    return null;
  }

  UIElement? elementForKey(Object? key) => _containersByKey[key]?.element;

  void refresh() {
    _checkNotDisposed();
    _reconcileAll();
  }

  @override
  Iterable<UIElement> get logicalChildren =>
      _containers.map((container) => container.element);

  @override
  void onMounted() => _subscribe();

  @override
  void onUnmounted() => _unsubscribe();

  @override
  void dispose() {
    if (isDisposed) return;
    _unsubscribe();
    for (final container in List<_ItemContainer<T>>.of(_containers)) {
      container.element.dispose();
    }
    _removeAllContainers();
    super.dispose();
  }

  @override
  void removeChild(UIElement child) {
    for (final container in List<_ItemContainer<T>>.of(_containers)) {
      if (identical(container.element, child)) {
        _removeContainer(container);
        return;
      }
    }
  }

  void _subscribe() {
    if (isDisposed || !isMounted || _sourceSubscription != null) return;
    final source = _itemsSource;
    if (source is ObservableCollection<T>) {
      _sourceSubscription = source.subscribe(_collectionChanged);
    }
  }

  void _unsubscribe() {
    _sourceSubscription?.cancel();
    _sourceSubscription = null;
  }

  void _collectionChanged(CollectionChangedEvent<T> event) {
    if (isDisposed) return;
    if (_virtualizing || event.action == CollectionChangeAction.reset) {
      _knownHeights.clear();
      _reconcileAll();
      return;
    }

    switch (event.action) {
      case CollectionChangeAction.add:
      case CollectionChangeAction.insert:
        for (var offset = 0; offset < event.addedItems.length; offset++) {
          final index = event.index + offset;
          final item = event.addedItems[offset];
          final container = _createContainer(item, index);
          _containers.insert(index, container);
        }
        _reindexContainers();
      case CollectionChangeAction.remove:
        for (var offset = 0; offset < event.removedItems.length; offset++) {
          _removeContainerAt(event.index);
        }
        _reindexContainers();
      case CollectionChangeAction.replace:
        for (var offset = 0; offset < event.addedItems.length; offset++) {
          _removeContainerAt(event.index + offset);
          final container = _createContainer(
            event.addedItems[offset],
            event.index + offset,
          );
          _containers.insert(event.index + offset, container);
        }
        _reindexContainers();
      case CollectionChangeAction.move:
        final container = _containers.removeAt(event.oldIndex);
        _containers.insert(event.index, container);
        _reindexContainers();
      case CollectionChangeAction.reset:
        break;
    }
    invalidateMeasure();
  }

  void _reconcileAll() {
    _checkNotDisposed();
    final items = List<T>.of(_itemsSource);
    final itemsByKey = <Object?, T>{};
    for (final item in items) {
      final key = _keySelector(item);
      if (itemsByKey.containsKey(key)) {
        throw ArgumentError('Item keys must be unique.');
      }
      itemsByKey[key] = item;
    }

    if (_virtualizing) {
      for (final container in List<_ItemContainer<T>>.of(_containers)) {
        if (itemsByKey.containsKey(container.key) &&
            itemsByKey[container.key] == container.item) {
          container.element.dataContext = container.item;
        } else {
          _removeContainer(container);
        }
      }
      _knownHeights.clear();
      if (isMounted || _containers.isNotEmpty) {
        _updateVisibleRange();
      } else {
        _firstVisibleIndex = -1;
        _lastVisibleIndex = -1;
      }
    } else {
      final previous = Map<Object?, _ItemContainer<T>>.of(_containersByKey);
      final next = <_ItemContainer<T>>[];
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        final key = _keySelector(item);
        final existing = previous.remove(key);
        if (existing != null && existing.item == item) {
          existing
            ..item = item
            ..index = index;
          existing.element.dataContext = item;
          next.add(existing);
        } else {
          if (existing != null) _removeContainer(existing);
          next.add(_createContainer(item, index));
        }
      }
      for (final stale in previous.values) {
        _removeContainer(stale);
      }
      _containers
        ..clear()
        ..addAll(next);
    }
    invalidateMeasure();
  }

  _ItemContainer<T> _createContainer(T item, int index) {
    final key = _keySelector(item);
    if (_containersByKey.containsKey(key)) {
      throw ArgumentError('Item keys must be unique.');
    }
    final element = _itemTemplate(item);
    if (element.logicalParent != null) {
      throw StateError(
          'An item template must return a new unparented element.');
    }
    element
      ..dataContext = item
      ..attachToParent(this)
      ..mountTo(window);
    final container = _ItemContainer<T>(item, key, index, element);
    _containersByKey[key] = container;
    return container;
  }

  void _removeContainerAt(int index) {
    _removeContainer(_containers[index]);
  }

  void _removeContainer(_ItemContainer<T> container) {
    _containers.remove(container);
    if (identical(_containersByKey[container.key], container)) {
      _containersByKey.remove(container.key);
    }
    container.element
      ..attachToParent(null)
      ..mountTo(null);
  }

  void _removeAllContainers() {
    for (final container in List<_ItemContainer<T>>.of(_containers)) {
      _removeContainer(container);
    }
    _containers.clear();
    _containersByKey.clear();
    _firstVisibleIndex = -1;
    _lastVisibleIndex = -1;
  }

  void _reindexContainers() {
    for (var index = 0; index < _containers.length; index++) {
      _containers[index].index = index;
    }
  }

  @override
  Size measureCore(Size availableSize) {
    final innerWidth = math.max(0.0, availableSize.width - _padding.horizontal);
    if (_virtualizing) {
      _updateVisibleRange(availableHeight: availableSize.height);
      var width = 0.0;
      for (final container in _containers) {
        final size =
            container.element.measure(Size(innerWidth, double.infinity));
        _updateKnownHeight(container.index, size.height);
        width = math.max(width, size.width);
      }
      return _padding.inflateSize(Size(width, _estimatedExtent));
    }

    var width = 0.0;
    var height = 0.0;
    for (final container in _containers) {
      final size = container.element.measure(Size(innerWidth, double.infinity));
      width = math.max(width, size.width);
      height += size.height;
    }
    if (_containers.length > 1) {
      height += _spacing * (_containers.length - 1);
    }
    return _padding.inflateSize(Size(width, height));
  }

  @override
  void arrangeCore(Rect finalRect) {
    if (_virtualizing) _updateVisibleRange();
    final content = finalRect.deflate(_padding);
    for (final container in _containers) {
      final top = content.top + _extentBefore(container.index);
      final width = content.width;
      final height = container.element
          .measure(Size(math.max(0.0, width), double.infinity))
          .height;
      if (_virtualizing) _updateKnownHeight(container.index, height);
      container.element.arrange(
        Rect.fromLTWH(content.left, top, math.max(0.0, width), height),
      );
    }
  }

  void _updateVisibleRange({double? availableHeight}) {
    if (!_virtualizing) return;
    final count = _itemsSource.length;
    if (count == 0) {
      for (final container in List<_ItemContainer<T>>.of(_containers)) {
        _removeContainer(container);
      }
      _firstVisibleIndex = -1;
      _lastVisibleIndex = -1;
      return;
    }

    final parent = logicalParent;
    final scrollViewer = parent is ScrollViewer ? parent : null;
    final offset = scrollViewer?.verticalOffset ?? 0;
    final viewport = scrollViewer != null && scrollViewer.viewportHeight > 0
        ? scrollViewer.viewportHeight
        : (availableHeight != null && availableHeight.isFinite
            ? availableHeight
            : 0.0);
    var scanIndex = 0;
    var scanOffset = 0.0;
    while (
        scanIndex < count - 1 && scanOffset + _heightAt(scanIndex) <= offset) {
      scanOffset += _heightAt(scanIndex);
      scanIndex++;
    }

    final visibleStart = scanIndex;
    var visibleEnd = visibleStart;
    final endOffset = offset + viewport;
    while (visibleEnd < count &&
        (scanOffset < endOffset || visibleEnd < visibleStart + 2)) {
      scanOffset += _heightAt(visibleEnd);
      visibleEnd++;
    }
    final first = math.max(0, visibleStart - 2);
    final last = math.min(count - 1, visibleEnd + 1);
    final desiredIndexes = <int>{
      for (var index = first; index <= last; index++) index,
    };
    final desiredItems = <int, T>{
      for (final index in desiredIndexes) index: _itemAt(index),
    };
    final desiredIndexByKey = <Object?, int>{
      for (final entry in desiredItems.entries)
        _keySelector(entry.value): entry.key,
    };

    for (final container in List<_ItemContainer<T>>.of(_containers)) {
      final desiredIndex = desiredIndexByKey[container.key];
      if (desiredIndex == null) {
        _removeContainer(container);
        continue;
      }
      final item = desiredItems[desiredIndex] as T;
      if (item != container.item) _removeContainer(container);
    }
    for (final entry in desiredItems.entries) {
      final index = entry.key;
      final item = entry.value;
      final key = _keySelector(item);
      final existing = _containersByKey[key];
      if (existing != null && existing.item == item) {
        existing.index = index;
        existing.element.dataContext = item;
      } else {
        if (existing != null) _removeContainer(existing);
        _containers.add(_createContainer(item, index));
      }
    }
    _containers.sort((a, b) => a.index.compareTo(b.index));
    _firstVisibleIndex = first;
    _lastVisibleIndex = last;
  }

  T _itemAt(int index) {
    final source = _itemsSource;
    return source is List<T> ? source[index] : source.elementAt(index);
  }

  void _updateKnownHeight(int index, double height) {
    if (!_virtualizing) return;
    if (_knownHeights[index] == height) return;
    _knownHeights[index] = height;
    invalidateMeasure();
  }

  double _heightAt(int index) =>
      (_knownHeights[index] ?? _estimatedItemExtent) +
      (index + 1 < _itemsSource.length ? _spacing : 0);

  double _extentBefore(int index) {
    if (!_virtualizing) {
      var extent = 0.0;
      for (var current = 0; current < index; current++) {
        extent += _containers[current].element.desiredSize.height + _spacing;
      }
      return extent;
    }
    var extent = 0.0;
    for (var current = 0; current < index; current++) {
      extent += _heightAt(current);
    }
    return extent;
  }

  double get _estimatedExtent {
    var extent = 0.0;
    for (var index = 0; index < _itemsSource.length; index++) {
      extent += _heightAt(index);
    }
    return extent;
  }

  @override
  void renderCore(DrawingContext context) {
    for (final container in _containers) {
      container.element.render(context);
    }
  }

  @override
  UIElement? hitTestCore(Point position) {
    for (final container in _containers.reversed) {
      final hit = container.element.hitTest(position);
      if (hit != null) return hit;
    }
    return null;
  }

  void _checkNotDisposed() {
    if (isDisposed) throw StateError('The items control is disposed.');
  }
}

final class VirtualizingStackPanel<T> extends ItemsControl<T> {
  VirtualizingStackPanel({
    super.itemsSource,
    super.itemTemplate,
    super.keySelector,
    super.spacing,
    super.padding,
    super.estimatedItemExtent,
  }) : super.virtualizing();
}

final class _ItemContainer<T> {
  _ItemContainer(this.item, this.key, this.index, this.element);

  T item;
  final Object? key;
  int index;
  final UIElement element;
}
