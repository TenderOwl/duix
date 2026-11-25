import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  test('empty definitions create one star cell by default', () {
    final child = _FixedElement(const Size(30, 20));
    final grid = Grid(children: [child]);

    _layout(grid);

    expect(Grid.getRow(child), 0);
    expect(Grid.getColumn(child), 0);
    expect(grid.desiredSize, const Size(200, 100));
    expect(child.bounds, const Rect.fromLTWH(0, 0, 200, 100));
  });

  test('auto and pixel columns leave the remainder to star', () {
    final auto = _FixedElement(const Size(30, 10));
    final pixel = _FixedElement(const Size(50, 10));
    final star = _FixedElement(const Size(70, 10));
    Grid.setColumn(pixel, 1);
    Grid.setColumn(star, 2);
    final grid = Grid(
      columns: [
        ColumnDefinition(),
        ColumnDefinition(width: GridLength.pixel(40)),
        ColumnDefinition(width: GridLength.star()),
      ],
      children: [auto, pixel, star],
    );

    _layout(grid);

    expect(grid.desiredSize, const Size(200, 100));
    expect(auto.bounds, const Rect.fromLTWH(0, 0, 30, 100));
    expect(pixel.bounds, const Rect.fromLTWH(30, 0, 40, 100));
    expect(star.bounds, const Rect.fromLTWH(70, 0, 130, 100));
  });

  test('weighted stars and gaps produce fractional track geometry', () {
    final first = _FixedElement(const Size(10, 10));
    final second = _FixedElement(const Size(10, 10));
    Grid.setColumn(second, 1);
    Grid.setRow(second, 1);
    final grid = Grid(
      columns: [
        ColumnDefinition(width: GridLength.star()),
        ColumnDefinition(width: GridLength.star(2)),
      ],
      rows: [
        RowDefinition(height: GridLength.pixel(20)),
        RowDefinition(height: GridLength.star()),
      ],
      columnSpacing: 10,
      rowSpacing: 5,
      children: [first, second],
    );

    _layout(grid, const Size(210, 120));

    expect(first.bounds.left, 0);
    expect(first.bounds.top, 0);
    expect(first.bounds.width, 67);
    expect(first.bounds.height, 20);
    expect(second.bounds.left, 77);
    expect(second.bounds.top, 25);
    expect(second.bounds.width, 133);
    expect(second.bounds.height, 95);
  });

  test('auto row is measured after the resolved column width', () {
    final child = _WrapElement();
    final grid = Grid(
      columns: [ColumnDefinition(width: GridLength.pixel(50))],
      rows: [RowDefinition()],
      children: [child],
    );

    _layout(grid);

    expect(grid.desiredSize, const Size(50, 20));
    expect(child.bounds, const Rect.fromLTWH(0, 0, 50, 20));
  });

  test('infinite star constraints measure content before finite arrange', () {
    final first = _FixedElement(const Size(30, 10));
    final second = _FixedElement(const Size(50, 20));
    Grid.setColumn(second, 1);
    final grid = Grid(
      columns: [
        ColumnDefinition(width: GridLength.star()),
        ColumnDefinition(width: GridLength.star()),
      ],
      children: [first, second],
    );

    grid.measure(const Size(double.infinity, double.infinity));
    grid.arrange(const Rect.fromLTWH(0, 0, 200, 100));

    expect(grid.desiredSize, const Size(80, 20));
    expect(first.bounds, const Rect.fromLTWH(0, 0, 100, 100));
    expect(second.bounds, const Rect.fromLTWH(100, 0, 100, 100));
  });

  test('auto tracks and spacing determine the desired size', () {
    final children = [
      _FixedElement(const Size(30, 10)),
      _FixedElement(const Size(40, 10)),
      _FixedElement(const Size(10, 20)),
      _FixedElement(const Size(10, 10)),
    ];
    for (var index = 0; index < children.length; index++) {
      Grid.setColumn(children[index], index % 2);
      Grid.setRow(children[index], index ~/ 2);
    }
    final grid = Grid(
      columns: [ColumnDefinition(), ColumnDefinition()],
      rows: [RowDefinition(), RowDefinition()],
      columnSpacing: 5,
      rowSpacing: 7,
      children: children,
    );

    _layout(grid, const Size(75, 37));

    expect(grid.desiredSize, const Size(75, 37));
    expect(children[3].bounds, const Rect.fromLTWH(35, 17, 40, 20));
  });

  test('attached cell and definition changes invalidate layout', () {
    final child = _FixedElement(const Size(10, 10));
    final grid = Grid(
      columns: [
        ColumnDefinition(width: GridLength.pixel(20)),
        ColumnDefinition(width: GridLength.pixel(80)),
      ],
      children: [child],
    );

    _layout(grid);
    expect(child.bounds, const Rect.fromLTWH(0, 0, 20, 100));

    Grid.setColumn(child, 1);
    _layout(grid);
    expect(child.bounds, const Rect.fromLTWH(20, 0, 80, 100));

    grid.columnDefinitions[1].width = GridLength.pixel(50);
    _layout(grid);
    expect(child.bounds, const Rect.fromLTWH(20, 0, 50, 100));

    Grid.setColumn(child, 0);
    grid.columnDefinitions.removeAt(0);
    _layout(grid);
    expect(child.bounds, const Rect.fromLTWH(0, 0, 50, 100));
  });

  test('invisible children do not contribute to auto tracks', () {
    final visible = _FixedElement(const Size(20, 10));
    final hidden = _FixedElement(const Size(100, 50))..isVisible = false;
    final grid = Grid(
      columns: [ColumnDefinition()],
      rows: [RowDefinition()],
      children: [visible, hidden],
    );

    _layout(grid, const Size(20, 10));

    expect(grid.desiredSize, const Size(20, 10));
    expect(visible.bounds, const Rect.fromLTWH(0, 0, 20, 10));
    expect(hidden.bounds, Rect.zero);
  });

  test('fractional star boundaries are rounded to physical pixels', () {
    final children = List.generate(3, (_) => _FixedElement(Size.zero));
    for (var index = 0; index < children.length; index++) {
      Grid.setColumn(children[index], index);
    }
    final grid = Grid(
      columns: List.generate(
        3,
        (_) => ColumnDefinition(width: GridLength.star()),
      ),
      children: children,
    );
    final window = Window(width: 101, height: 20, content: grid)
      ..updateDevicePixelRatio(1.25);

    window.updateLayout();

    for (final child in children) {
      expect(child.bounds.left * 1.25,
          closeTo((child.bounds.left * 1.25).round(), 0.000001));
      expect(child.bounds.width * 1.25,
          closeTo((child.bounds.width * 1.25).round(), 0.000001));
      expect(child.bounds.width, closeTo(33.6, 0.000001));
    }
    expect(
        children[0].bounds.right, closeTo(children[1].bounds.left, 0.000001));
    expect(
        children[1].bounds.right, closeTo(children[2].bounds.left, 0.000001));
  });

  test('column span includes intermediate tracks and spacing', () {
    final child = _FixedElement(const Size(30, 20));
    Grid.setColumnSpan(child, 2);
    final grid = Grid(
      columns: [
        ColumnDefinition(width: GridLength.pixel(40)),
        ColumnDefinition(width: GridLength.pixel(60)),
      ],
      rows: [RowDefinition(height: GridLength.pixel(30))],
      columnSpacing: 10,
      children: [child],
    );

    _layout(grid, const Size(110, 30));

    expect(Grid.getColumnSpan(child), 2);
    expect(child.bounds, const Rect.fromLTWH(0, 0, 110, 30));
  });

  test('row span includes intermediate tracks and spacing', () {
    final child = _FixedElement(const Size(20, 10));
    Grid.setRowSpan(child, 2);
    final grid = Grid(
      rows: [
        RowDefinition(height: GridLength.pixel(20)),
        RowDefinition(height: GridLength.pixel(30)),
      ],
      rowSpacing: 5,
      children: [child],
    );

    _layout(grid, const Size(200, 55));

    expect(Grid.getRowSpan(child), 2);
    expect(child.bounds, const Rect.fromLTWH(0, 0, 200, 55));
  });

  test('column span distributes its deficit between auto columns', () {
    final child = _FixedElement(const Size(100, 60));
    Grid.setColumnSpan(child, 2);
    final grid = Grid(
      columns: [ColumnDefinition(), ColumnDefinition()],
      children: [child],
    );

    _layout(grid, const Size(100, 60));

    expect(grid.desiredSize, const Size(100, 60));
    expect(child.bounds, const Rect.fromLTWH(0, 0, 100, 60));

    Grid.setColumnSpan(child, 1);
    _layout(grid, const Size(100, 60));
    expect(child.bounds, const Rect.fromLTWH(0, 0, 100, 60));
  });

  test('auto span growth reduces finite star tracks', () {
    final spanning = _FixedElement(const Size(120, 20));
    final star = _FixedElement(const Size(10, 10));
    Grid.setColumnSpan(spanning, 2);
    Grid.setColumn(star, 1);
    final grid = Grid(
      columns: [
        ColumnDefinition(),
        ColumnDefinition(width: GridLength.star()),
      ],
      children: [spanning, star],
    );

    _layout(grid, const Size(100, 60));

    expect(spanning.bounds, const Rect.fromLTWH(0, 0, 100, 60));
    expect(star.bounds, const Rect.fromLTWH(20, 0, 80, 60));
  });

  test('infinite star tracks accept a spanning content deficit', () {
    final child = _FixedElement(const Size(100, 20));
    Grid.setColumnSpan(child, 2);
    final grid = Grid(
      columns: [
        ColumnDefinition(width: GridLength.star()),
        ColumnDefinition(width: GridLength.star()),
      ],
      children: [child],
    );

    grid.measure(const Size(double.infinity, double.infinity));
    grid.arrange(const Rect.fromLTWH(0, 0, 200, 100));

    expect(grid.desiredSize, const Size(100, 20));
    expect(child.bounds, const Rect.fromLTWH(0, 0, 200, 100));
  });

  test('row span distributes its deficit between auto rows', () {
    final child = _FixedElement(const Size(20, 60));
    Grid.setRowSpan(child, 2);
    final grid = Grid(
      rows: [RowDefinition(), RowDefinition()],
      children: [child],
    );

    _layout(grid, const Size(40, 60));

    expect(grid.desiredSize, const Size(40, 60));
    expect(child.bounds, const Rect.fromLTWH(0, 0, 40, 60));
  });

  test('spanned arrange uses the same HiDPI-rounded track boundaries', () {
    final spanning = _FixedElement(Size.zero);
    Grid.setColumnSpan(spanning, 2);
    final singles = List.generate(3, (_) => _FixedElement(Size.zero));
    for (var index = 0; index < singles.length; index++) {
      Grid.setColumn(singles[index], index);
    }
    final grid = Grid(
      columns: List.generate(
        3,
        (_) => ColumnDefinition(width: GridLength.star()),
      ),
      columnSpacing: 2,
      children: [spanning, ...singles],
    );
    final window = Window(width: 101, height: 20, content: grid)
      ..updateDevicePixelRatio(1.25);

    window.updateLayout();

    expect(spanning.bounds.left, singles[0].bounds.left);
    expect(spanning.bounds.right, singles[1].bounds.right);
    expect(
      spanning.bounds.width * 1.25,
      closeTo((spanning.bounds.width * 1.25).round(), 0.000001),
    );
  });

  test('invalid spans and ranges are rejected', () {
    expect(
        () => Grid.setRowSpan(_FixedElement(Size.zero), 0), throwsRangeError);
    expect(
      () => Grid.setColumnSpan(_FixedElement(Size.zero), -1),
      throwsRangeError,
    );

    final child = _FixedElement(Size.zero);
    Grid.setColumnSpan(child, 2);
    final grid = Grid(children: [child]);
    expect(() => grid.measure(const Size(100, 100)), throwsStateError);
  });

  test('invalid lengths, cells and spacing are rejected', () {
    expect(() => GridLength.pixel(-1), throwsArgumentError);
    expect(() => GridLength.pixel(double.infinity), throwsArgumentError);
    expect(() => GridLength.star(0), throwsArgumentError);
    expect(() => GridLength.star(double.nan), throwsArgumentError);
    expect(() => Grid.setRow(_FixedElement(Size.zero), -1), throwsRangeError);
    expect(
        () => Grid.setColumn(_FixedElement(Size.zero), -1), throwsRangeError);
    expect(() => Grid(columnSpacing: -1), throwsArgumentError);

    final child = _FixedElement(Size.zero);
    Grid.setColumn(child, 1);
    final grid = Grid(children: [child]);
    expect(() => grid.measure(const Size(100, 100)), throwsStateError);
  });
}

void _layout(
  Grid grid, [
  Size available = const Size(200, 100),
]) {
  grid.measure(available);
  grid.arrange(Rect.fromLTWH(0, 0, available.width, available.height));
}

final class _FixedElement extends UIElement {
  _FixedElement(this.size);

  final Size size;

  @override
  Size measureCore(Size availableSize) => size;
}

final class _WrapElement extends UIElement {
  @override
  Size measureCore(Size availableSize) {
    if (!availableSize.width.isFinite) return const Size(100, 10);
    return Size(100, 1000 / availableSize.width);
  }
}
