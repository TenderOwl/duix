import 'drawing.dart';
import 'geometry.dart';
import 'panel.dart';
import 'ui_element.dart';

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
