import 'drawing.dart';
import 'geometry.dart';
import 'panel.dart';
import 'properties.dart';
import 'ui_element.dart';

enum Dock { left, top, right, bottom }

final class DockPanel extends Panel {
  DockPanel({
    bool lastChildFill = true,
    bool isFocusScope = false,
    Iterable<UIElement> children = const [],
  }) : _lastChildFill = lastChildFill {
    this.isFocusScope = isFocusScope;
    this.children.addAll(children);
  }

  static const dockProperty = DuiProperty<UIElement, Dock>(
    name: 'DockPanel.dock',
    defaultValue: Dock.left,
    affectsMeasure: true,
  );

  bool _lastChildFill;
  List<UIElement> _visibleChildren = const [];

  static Dock getDock(UIElement element) => element.getValue(dockProperty);

  static void setDock(UIElement element, Dock value) {
    element.setValue(dockProperty, value);
  }

  bool get lastChildFill => _lastChildFill;
  set lastChildFill(bool value) {
    if (_lastChildFill == value) return;
    _lastChildFill = value;
    invalidateMeasure();
  }

  @override
  Size measureCore(Size availableSize) {
    _visibleChildren = children.where((child) => child.isVisible).toList();
    var remaining = availableSize;
    var horizontalExtent = 0.0;
    var verticalExtent = 0.0;
    var crossWidth = 0.0;
    var crossHeight = 0.0;

    for (var index = 0; index < _visibleChildren.length; index++) {
      final child = _visibleChildren[index];
      final fillsRemaining =
          _lastChildFill && index == _visibleChildren.length - 1;
      final size = child.measure(remaining);
      final dock = getDock(child);

      if (fillsRemaining) {
        horizontalExtent += size.width;
        verticalExtent += size.height;
        continue;
      }
      switch (dock) {
        case Dock.left:
        case Dock.right:
          horizontalExtent += size.width;
          crossHeight = _max(crossHeight, size.height);
          remaining = Size(
            (remaining.width - size.width).clamp(0, double.infinity),
            remaining.height,
          );
        case Dock.top:
        case Dock.bottom:
          verticalExtent += size.height;
          crossWidth = _max(crossWidth, size.width);
          remaining = Size(
            remaining.width,
            (remaining.height - size.height).clamp(0, double.infinity),
          );
      }
    }

    return Size(
      _max(horizontalExtent, crossWidth),
      _max(verticalExtent, crossHeight),
    );
  }

  @override
  void arrangeCore(Rect finalRect) {
    var remaining = finalRect;

    for (var index = 0; index < _visibleChildren.length; index++) {
      final child = _visibleChildren[index];
      if (_lastChildFill && index == _visibleChildren.length - 1) {
        child.arrange(remaining);
        break;
      }

      final size = child.desiredSize;
      switch (getDock(child)) {
        case Dock.left:
          final width = _min(size.width, remaining.width);
          child.arrange(
            Rect.fromLTWH(
              remaining.left,
              remaining.top,
              width,
              remaining.height,
            ),
          );
          remaining = Rect.fromLTWH(
            remaining.left + width,
            remaining.top,
            remaining.width - width,
            remaining.height,
          );
        case Dock.right:
          final width = _min(size.width, remaining.width);
          child.arrange(
            Rect.fromLTWH(
              remaining.right - width,
              remaining.top,
              width,
              remaining.height,
            ),
          );
          remaining = Rect.fromLTWH(
            remaining.left,
            remaining.top,
            remaining.width - width,
            remaining.height,
          );
        case Dock.top:
          final height = _min(size.height, remaining.height);
          child.arrange(
            Rect.fromLTWH(
              remaining.left,
              remaining.top,
              remaining.width,
              height,
            ),
          );
          remaining = Rect.fromLTWH(
            remaining.left,
            remaining.top + height,
            remaining.width,
            remaining.height - height,
          );
        case Dock.bottom:
          final height = _min(size.height, remaining.height);
          child.arrange(
            Rect.fromLTWH(
              remaining.left,
              remaining.bottom - height,
              remaining.width,
              height,
            ),
          );
          remaining = Rect.fromLTWH(
            remaining.left,
            remaining.top,
            remaining.width,
            remaining.height - height,
          );
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

  static double _min(double first, double second) =>
      first < second ? first : second;

  static double _max(double first, double second) =>
      first > second ? first : second;
}
