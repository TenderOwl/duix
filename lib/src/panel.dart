import 'dart:collection';

import 'drawing.dart';
import 'geometry.dart';
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

final class StackPanel extends Panel {
  StackPanel({
    Orientation orientation = Orientation.vertical,
    double spacing = 0,
    EdgeInsets padding = EdgeInsets.zero,
    Iterable<UIElement> children = const [],
  })  : _orientation = orientation,
        _spacing = spacing,
        _padding = padding {
    this.children.addAll(children);
  }

  Orientation _orientation;
  double _spacing;
  EdgeInsets _padding;

  Orientation get orientation => _orientation;
  set orientation(Orientation value) {
    if (_orientation == value) return;
    _orientation = value;
    invalidateMeasure();
  }

  double get spacing => _spacing;
  set spacing(double value) {
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

  @override
  Size measureCore(Size availableSize) {
    final inner = Size(
      (availableSize.width - _padding.horizontal).clamp(0, double.infinity),
      (availableSize.height - _padding.vertical).clamp(0, double.infinity),
    );
    var mainExtent = 0.0;
    var crossExtent = 0.0;
    var visibleCount = 0;

    for (final child in children) {
      if (!child.isVisible) continue;
      final size = child.measure(inner);
      visibleCount++;
      if (_orientation == Orientation.vertical) {
        mainExtent += size.height;
        crossExtent = crossExtent > size.width ? crossExtent : size.width;
      } else {
        mainExtent += size.width;
        crossExtent = crossExtent > size.height ? crossExtent : size.height;
      }
    }
    if (visibleCount > 1) mainExtent += spacing * (visibleCount - 1);

    return _padding.inflateSize(
      _orientation == Orientation.vertical
          ? Size(crossExtent, mainExtent)
          : Size(mainExtent, crossExtent),
    );
  }

  @override
  void arrangeCore(Rect finalRect) {
    final content = finalRect.deflate(_padding);
    var offset =
        _orientation == Orientation.vertical ? content.top : content.left;

    for (final child in children) {
      if (!child.isVisible) continue;
      final size = child.desiredSize;
      if (_orientation == Orientation.vertical) {
        child.arrange(
            Rect.fromLTWH(content.left, offset, content.width, size.height));
        offset += size.height + spacing;
      } else {
        child.arrange(
            Rect.fromLTWH(offset, content.top, size.width, content.height));
        offset += size.width + spacing;
      }
    }
  }

  @override
  void renderCore(DrawingContext context) {
    for (final child in children) {
      child.render(context);
    }
  }

  @override
  UIElement? hitTestCore(Point position) {
    for (final child in children.toList().reversed) {
      final hit = child.hitTest(position);
      if (hit != null) return hit;
    }
    return null;
  }
}
