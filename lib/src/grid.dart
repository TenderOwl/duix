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
  static const rowSpanProperty = DuiProperty<UIElement, int>(
    name: 'Grid.rowSpan',
    defaultValue: 1,
    affectsMeasure: true,
  );
  static const columnSpanProperty = DuiProperty<UIElement, int>(
    name: 'Grid.columnSpan',
    defaultValue: 1,
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

  static int getRowSpan(UIElement element) => element.getValue(rowSpanProperty);
  static void setRowSpan(UIElement element, int value) {
    _validateSpan(value);
    element.setValue(rowSpanProperty, value);
  }

  static int getColumnSpan(UIElement element) =>
      element.getValue(columnSpanProperty);
  static void setColumnSpan(UIElement element, int value) {
    _validateSpan(value);
    element.setValue(columnSpanProperty, value);
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
    final columnLengths =
        columns.map((definition) => definition.width).toList();
    final rowLengths = rows.map((definition) => definition.height).toList();

    _columnWidths = _resolveTracks(
      columnLengths,
      availableSize.width,
      columnSpacing,
      (column, width) => _measureColumn(column, width, rows),
    );
    _resolveSpans(
      _visibleChildren.where((child) => getColumnSpan(child) > 1),
      columnLengths,
      _columnWidths,
      availableSize.width,
      columnSpacing,
      getColumn,
      getColumnSpan,
      (child, width) => _measureColumnSpan(child, width, rows),
      (column, width) => _measureColumn(column, width, rows),
    );
    _rowHeights = _resolveTracks(
      rowLengths,
      availableSize.height,
      rowSpacing,
      _measureRow,
    );
    _resolveSpans(
      _visibleChildren.where((child) => getRowSpan(child) > 1),
      rowLengths,
      _rowHeights,
      availableSize.height,
      rowSpacing,
      getRow,
      getRowSpan,
      _measureRowSpan,
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

  double _measureColumnSpan(
    UIElement child,
    double width,
    List<RowDefinition> rows,
  ) {
    final rowLength = rows[getRow(child)].height;
    final height = rowLength.isPixel ? rowLength.value : double.infinity;
    child.measure(Size(width, height));
    return child.desiredSize.width;
  }

  double _measureRow(int row, double height) {
    var result = 0.0;
    for (final child in _childrenInRow(row)) {
      final width = _spanExtent(
        _columnWidths,
        getColumn(child),
        getColumnSpan(child),
        columnSpacing,
      );
      child.measure(Size(width, height));
      result = _max(result, child.desiredSize.height);
    }
    return result;
  }

  double _measureRowSpan(UIElement child, double height) {
    final width = _spanExtent(
      _columnWidths,
      getColumn(child),
      getColumnSpan(child),
      columnSpacing,
    );
    child.measure(Size(width, height));
    return child.desiredSize.height;
  }

  Iterable<UIElement> _childrenInColumn(int column) => _visibleChildren.where(
        (child) => getColumn(child) == column && getColumnSpan(child) == 1,
      );

  Iterable<UIElement> _childrenInRow(int row) => _visibleChildren.where(
        (child) => getRow(child) == row && getRowSpan(child) == 1,
      );

  List<double> _resolveTracks(
    List<GridLength> lengths,
    double available,
    double spacing,
    double Function(int index, double constraint) measureTrack,
  ) {
    final sizes = List<double>.filled(lengths.length, 0);
    for (var index = 0; index < lengths.length; index++) {
      final length = lengths[index];
      if (length.isPixel) {
        sizes[index] = length.value;
        measureTrack(index, length.value);
      } else if (length.isAuto || !available.isFinite) {
        sizes[index] = measureTrack(index, double.infinity);
      }
    }
    _distributeStars(lengths, sizes, available, spacing, measureTrack);
    return sizes;
  }

  void _resolveSpans(
    Iterable<UIElement> spanningChildren,
    List<GridLength> lengths,
    List<double> sizes,
    double available,
    double spacing,
    int Function(UIElement child) startOf,
    int Function(UIElement child) spanOf,
    double Function(UIElement child, double constraint) measureChild,
    double Function(int index, double constraint) measureTrack,
  ) {
    final children = spanningChildren.toList();
    for (final child in children) {
      final start = startOf(child);
      final span = spanOf(child);
      final end = start + span;
      final growthTargets = <int>[
        for (var index = start; index < end; index++)
          if (lengths[index].isAuto ||
              (!available.isFinite && lengths[index].isStar))
            index,
      ];
      final autoTargets =
          growthTargets.where((index) => lengths[index].isAuto).toList();
      final targets = autoTargets.isEmpty ? growthTargets : autoTargets;
      final current = _spanExtent(sizes, start, span, spacing);
      final desired = measureChild(
        child,
        targets.isEmpty ? current : double.infinity,
      );
      final deficit = desired - current;
      if (targets.isNotEmpty && deficit > 0) {
        final addition = deficit / targets.length;
        for (final index in targets) {
          sizes[index] += addition;
        }
        _distributeStars(
          lengths,
          sizes,
          available,
          spacing,
          measureTrack,
        );
      }
    }

    for (final child in children) {
      measureChild(
        child,
        _spanExtent(sizes, startOf(child), spanOf(child), spacing),
      );
    }
  }

  void _distributeStars(
    List<GridLength> lengths,
    List<double> sizes,
    double available,
    double spacing,
    double Function(int index, double constraint) measureTrack,
  ) {
    if (!available.isFinite) return;
    var fixedExtent = 0.0;
    var totalWeight = 0.0;
    for (var index = 0; index < lengths.length; index++) {
      final length = lengths[index];
      if (length.isStar) {
        totalWeight += length.value;
      } else {
        fixedExtent += sizes[index];
      }
    }
    if (totalWeight == 0) return;
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

  static double _spanExtent(
    List<double> sizes,
    int start,
    int span,
    double spacing,
  ) {
    var result = spacing * (span - 1);
    for (var index = start; index < start + span; index++) {
      result += sizes[index];
    }
    return result;
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
      final lastColumn = column + getColumnSpan(child) - 1;
      final lastRow = row + getRowSpan(child) - 1;
      final left = columnOffsets[column].$1;
      final top = rowOffsets[row].$1;
      final right = columnOffsets[lastColumn].$1 + columnOffsets[lastColumn].$2;
      final bottom = rowOffsets[lastRow].$1 + rowOffsets[lastRow].$2;
      child.arrange(
        Rect.fromLTWH(
          finalRect.left + left,
          finalRect.top + top,
          right - left,
          bottom - top,
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
      final column = getColumn(child);
      final row = getRow(child);
      final columnSpan = getColumnSpan(child);
      final rowSpan = getRowSpan(child);
      if (column < 0 || columnSpan < 1 || column + columnSpan > columnCount) {
        throw StateError(
          'Child column range $column..${column + columnSpan} is not defined.',
        );
      }
      if (row < 0 || rowSpan < 1 || row + rowSpan > rowCount) {
        throw StateError(
          'Child row range $row..${row + rowSpan} is not defined.',
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

  static double _sumWithSpacing(List<double> sizes, double spacing) {
    var result = 0.0;
    for (final size in sizes) {
      result += size;
    }
    return result + spacing * (sizes.length - 1);
  }

  static void _validateSpan(int value) {
    if (value < 1) {
      throw RangeError.value(value, 'value', 'Must be at least 1.');
    }
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
