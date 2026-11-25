import 'dart:collection';

import 'ui_element.dart';

abstract class Panel extends UIElement {
  late final ElementChildrenList children = ElementChildrenList._(this);

  @override
  Iterable<UIElement> get logicalChildren => children;
}

final class ElementChildrenList extends ListBase<UIElement> {
  ElementChildrenList._(this.owner);

  final Panel owner;
  final _items = <UIElement>[];

  @override
  int get length => _items.length;

  @override
  set length(int newLength) {
    if (newLength < 0) throw RangeError.value(newLength, 'newLength');
    if (newLength < _items.length) {
      while (_items.length > newLength) {
        removeAt(_items.length - 1);
      }
      return;
    }
    if (newLength == _items.length) return;
    throw UnsupportedError(
      'Add elements explicitly instead of extending length.',
    );
  }

  @override
  UIElement operator [](int index) => _items[index];

  @override
  void operator []=(int index, UIElement value) {
    final oldValue = _items[index];
    if (identical(oldValue, value)) return;
    _prepareChild(value);
    _items[index] = value;
    oldValue.attachToParent(null);
    oldValue.mountTo(null);
    owner.invalidateMeasure();
  }

  @override
  void add(UIElement element) {
    _prepareChild(element);
    _items.add(element);
    owner.invalidateMeasure();
  }

  @override
  UIElement removeAt(int index) {
    final element = _items.removeAt(index);
    element.attachToParent(null);
    element.mountTo(null);
    owner.invalidateMeasure();
    return element;
  }

  @override
  void clear() {
    for (final element in _items) {
      element.attachToParent(null);
      element.mountTo(null);
    }
    _items.clear();
    owner.invalidateMeasure();
  }

  void _prepareChild(UIElement element) {
    if (element.logicalParent != null) {
      throw StateError('The element already belongs to another parent.');
    }
    element.attachToParent(owner);
    element.mountTo(owner.window);
  }
}
