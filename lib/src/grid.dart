import 'dart:collection';

import 'drawing.dart';
import 'geometry.dart';
import 'observable.dart';
import 'panel.dart';
import 'properties.dart';
import 'ui_element.dart';

enum GridUnitType { auto, pixel, star }

final class GridLength {
  const GridLength._(this.value, this.type);

  static const auto = GridLength._(0, GridUnitType.auto);

  factory GridLength.pixel(double value) {
    if (value < 0 || !value.isFinite) {
      throw ArgumentError.value(
        value,
        'value',
        'A pixel length must be finite and non-negative.',
      );
    }
    return GridLength._(value, GridUnitType.pixel);
  }

  factory GridLength.star([double weight = 1]) {
    if (weight <= 0 || !weight.isFinite) {
      throw ArgumentError.value(
        weight,
        'weight',
        'A star weight must be finite and positive.',
      );
    }
    return GridLength._(weight, GridUnitType.star);
  }

  final double value;
  final GridUnitType type;

  bool get isAuto => type == GridUnitType.auto;
  bool get isPixel => type == GridUnitType.pixel;
  bool get isStar => type == GridUnitType.star;

  @override
  bool operator ==(Object other) =>
      other is GridLength && other.value == value && other.type == type;

  @override
  int get hashCode => Object.hash(value, type);
}

abstract class GridDefinition extends ObservableObject {
  GridDefinition(GridLength length) : _length = length;

  GridLength _length;

  GridLength get length => _length;
  set length(GridLength value) {
    if (_length == value) return;
    final oldValue = _length;
    _length = value;
    notifyPropertyChanged('length', oldValue, value);
  }
}

final class ColumnDefinition extends GridDefinition {
  ColumnDefinition({GridLength? width}) : super(width ?? GridLength.auto);

  GridLength get width => length;
  set width(GridLength value) => length = value;
}

final class RowDefinition extends GridDefinition {
  RowDefinition({GridLength? height}) : super(height ?? GridLength.auto);

  GridLength get height => length;
  set height(GridLength value) => length = value;
}

final class GridDefinitionList<T extends GridDefinition> extends ListBase<T> {
  GridDefinitionList._(this.owner);

  final Grid owner;
  final _items = <T>[];

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
    if (newLength == length) return;
    throw UnsupportedError(
      'Add definitions explicitly instead of extending length.',
    );
  }

  @override
  T operator [](int index) => _items[index];

  @override
  void operator []=(int index, T value) {
    final oldValue = _items[index];
    if (identical(oldValue, value)) return;
    oldValue.removePropertyListener(_definitionChanged);
    _items[index] = value;
    value.addPropertyListener(_definitionChanged);
    owner.invalidateMeasure();
  }

  @override
  void add(T element) {
    _items.add(element);
    element.addPropertyListener(_definitionChanged);
    owner.invalidateMeasure();
  }

  @override
  T removeAt(int index) {
    final value = _items.removeAt(index);
    value.removePropertyListener(_definitionChanged);
    owner.invalidateMeasure();
    return value;
  }

  @override
  void clear() {
    for (final value in _items) {
      value.removePropertyListener(_definitionChanged);
    }
    _items.clear();
    owner.invalidateMeasure();
  }

  void _definitionChanged(PropertyChangedEvent event) {
    owner.invalidateMeasure();
  }
}

final class Grid extends Panel {
  Grid({
    Iterable<ColumnDefinition> columns = const [],
    Iterable<RowDefinition> rows = const [],
    double columnSpacing = 0,
    double rowSpacing = 0,
    bool isFocusScope = false,
    Iterable<UIElement> children = const [],
  })  : _columnSpacing = _validateSpacing(columnSpacing, 'columnSpacing'),
        _rowSpacing = _validateSpacing(rowSpacing, 'rowSpacing') {
    this.isFocusScope = isFocusScope;
    columnDefinitions.addAll(columns);
    rowDefinitions.addAll(rows);
    this.children.addAll(children);
  }

  static const rowProperty = DuiProperty<UIElement, int>(
    name: 'Grid.row',
    defaultValue: 0,
    affectsMeasure: true,
  );
  static const columnProperty = DuiProperty<UIElement, int>(
    name: 'Grid.column',
    defaultValue: 0,
    affectsMeasure: true,
  );

  late final GridDefinitionList<ColumnDefinition> columnDefinitions =
      GridDefinitionList<ColumnDefinition>._(this);
  late final GridDefinitionList<RowDefinition> rowDefinitions =
      GridDefinitionList<RowDefinition>._(this);
  final _defaultColumns = <ColumnDefinition>[
    ColumnDefinition(width: GridLength.star())
  ];
  final _defaultRows = <RowDefinition>[
    RowDefinition(height: GridLength.star())
  ];

  double _columnSpacing;
  double _rowSpacing;
  List<UIElement> _visibleChildren = const [];
  List<double> _columnWidths = const [];
  List<double> _rowHeights = const [];

  static int getRow(UIElement element) => element.getValue(rowProperty);
  static void setRow(UIElement element, int value) {
    if (value < 0) {
      throw RangeError.value(value, 'value', 'Must be non-negative.');
    }
    element.setValue(rowProperty, value);
  }

  static int getColumn(UIElement element) => element.getValue(columnProperty);
  static void setColumn(UIElement element, int value) {
    if (value < 0) {
      throw RangeError.value(value, 'value', 'Must be non-negative.');
    }
    element.setValue(columnProperty, value);
  }

  double get columnSpacing => _columnSpacing;
  set columnSpacing(double value) {
    _validateSpacing(value, 'columnSpacing');
    if (_columnSpacing == value) return;
    _columnSpacing = value;
    invalidateMeasure();
  }

  double get rowSpacing => _rowSpacing;
  set rowSpacing(double value) {
    _validateSpacing(value, 'rowSpacing');
    if (_rowSpacing == value) return;
    _rowSpacing = value;
    invalidateMeasure();
  }

  List<ColumnDefinition> get _columns =>
      columnDefinitions.isEmpty ? _defaultColumns : columnDefinitions;
  List<RowDefinition> get _rows =>
      rowDefinitions.isEmpty ? _defaultRows : rowDefinitions;

  @override
  Size measureCore(Size availableSize) {
    _visibleChildren = children.where((child) => child.isVisible).toList();
    final columns = _columns;
    final rows = _rows;
    _validateCells(columns.length, rows.length);

    _columnWidths = _resolveTracks(
      columns.map((definition) => definition.width).toList(),
      availableSize.width,
      columnSpacing,
      (column, width) => _measureColumn(column, width, rows),
    );
    _rowHeights = _resolveTracks(
      rows.map((definition) => definition.height).toList(),
      availableSize.height,
      rowSpacing,
      _measureRow,
    );

    return Size(
      _sumWithSpacing(_columnWidths, columnSpacing),
      _sumWithSpacing(_rowHeights, rowSpacing),
    );
  }

  double _measureColumn(
    int column,
    double width,
    List<RowDefinition> rows,
  ) {
    var result = 0.0;
    for (final child in _childrenInColumn(column)) {
      final rowLength = rows[getRow(child)].height;
      final height = rowLength.isPixel ? rowLength.value : double.infinity;
      child.measure(Size(width, height));
      result = _max(result, child.desiredSize.width);
    }
    return result;
  }

  double _measureRow(int row, double height) {
    var result = 0.0;
    for (final child in _childrenInRow(row)) {
      child.measure(Size(_columnWidths[getColumn(child)], height));
      result = _max(result, child.desiredSize.height);
    }
    return result;
  }

  Iterable<UIElement> _childrenInColumn(int column) =>
      _visibleChildren.where((child) => getColumn(child) == column);

  Iterable<UIElement> _childrenInRow(int row) =>
      _visibleChildren.where((child) => getRow(child) == row);

  List<double> _resolveTracks(
    List<GridLength> lengths,
    double available,
    double spacing,
    double Function(int index, double constraint) measureTrack,
  ) {
    final sizes = List<double>.filled(lengths.length, 0);
    var fixedExtent = 0.0;
    var totalWeight = 0.0;

    for (var index = 0; index < lengths.length; index++) {
      final length = lengths[index];
      if (length.isPixel) {
        sizes[index] = length.value;
        measureTrack(index, length.value);
        fixedExtent += length.value;
      } else if (length.isAuto || !available.isFinite) {
        final desired = measureTrack(index, double.infinity);
        sizes[index] = desired;
        fixedExtent += desired;
      } else {
        totalWeight += length.value;
      }
    }

    if (available.isFinite && totalWeight > 0) {
      final gaps = spacing * (lengths.length - 1);
      final remaining = _max(0, available - fixedExtent - gaps);
      for (var index = 0; index < lengths.length; index++) {
        final length = lengths[index];
        if (!length.isStar) continue;
        final size = remaining * length.value / totalWeight;
        sizes[index] = size;
        measureTrack(index, size);
      }
    }
    return sizes;
  }

  @override
  void arrangeCore(Rect finalRect) {
    final widths = _arrangeTrackSizes(
      _columns.map((definition) => definition.width).toList(),
      _columnWidths,
      finalRect.width,
      columnSpacing,
    );
    final heights = _arrangeTrackSizes(
      _rows.map((definition) => definition.height).toList(),
      _rowHeights,
      finalRect.height,
      rowSpacing,
    );
    final scale = window?.displayScale ?? 1;
    final columnOffsets = _pixelOffsets(widths, columnSpacing, scale);
    final rowOffsets = _pixelOffsets(heights, rowSpacing, scale);

    for (final child in _visibleChildren) {
      final column = getColumn(child);
      final row = getRow(child);
      child.arrange(
        Rect.fromLTWH(
          finalRect.left + columnOffsets[column].$1,
          finalRect.top + rowOffsets[row].$1,
          columnOffsets[column].$2,
          rowOffsets[row].$2,
        ),
      );
    }
  }

  List<double> _arrangeTrackSizes(
    List<GridLength> lengths,
    List<double> measured,
    double available,
    double spacing,
  ) {
    final sizes = List<double>.of(measured);
    var fixedExtent = 0.0;
    var totalWeight = 0.0;
    for (var index = 0; index < lengths.length; index++) {
      if (lengths[index].isStar) {
        totalWeight += lengths[index].value;
      } else {
        fixedExtent += sizes[index];
      }
    }
    if (totalWeight == 0) return sizes;
    final gaps = spacing * (lengths.length - 1);
    final remaining = _max(0, available - fixedExtent - gaps);
    for (var index = 0; index < lengths.length; index++) {
      final length = lengths[index];
      if (length.isStar) {
        sizes[index] = remaining * length.value / totalWeight;
      }
    }
    return sizes;
  }

  List<(double, double)> _pixelOffsets(
    List<double> sizes,
    double spacing,
    double scale,
  ) {
    final result = <(double, double)>[];
    var offset = 0.0;
    for (final size in sizes) {
      final start = (offset * scale).round();
      final end = ((offset + size) * scale).round();
      result.add((start / scale, (end - start) / scale));
      offset += size + spacing;
    }
    return result;
  }

  void _validateCells(int columnCount, int rowCount) {
    for (final child in _visibleChildren) {
      if (getColumn(child) >= columnCount) {
        throw StateError('Child column ${getColumn(child)} is not defined.');
      }
      if (getRow(child) >= rowCount) {
        throw StateError('Child row ${getRow(child)} is not defined.');
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

  static double _sumWithSpacing(List<double> sizes, double spacing) {
    var result = 0.0;
    for (final size in sizes) {
      result += size;
    }
    return result + spacing * (sizes.length - 1);
  }

  static double _validateSpacing(double value, String name) {
    if (value < 0 || !value.isFinite) {
      throw ArgumentError.value(
        value,
        name,
        'Must be finite and non-negative.',
      );
    }
    return value;
  }

  static double _max(double first, double second) =>
      first > second ? first : second;
}
