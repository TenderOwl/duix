final class Point {
  const Point(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is Point && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

final class Size {
  const Size(this.width, this.height);

  static const zero = Size(0, 0);

  final double width;
  final double height;

  Size constrain(Size available) => Size(
        width.clamp(0, available.width),
        height.clamp(0, available.height),
      );

  @override
  bool operator ==(Object other) =>
      other is Size && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'Size($width, $height)';
}

final class Rect {
  const Rect.fromLTWH(this.left, this.top, this.width, this.height);

  static const zero = Rect.fromLTWH(0, 0, 0, 0);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  Size get size => Size(width, height);

  bool contains(Point point) =>
      point.x >= left && point.x < right && point.y >= top && point.y < bottom;

  Rect deflate(EdgeInsets padding) => Rect.fromLTWH(
        left + padding.left,
        top + padding.top,
        (width - padding.horizontal).clamp(0, double.infinity),
        (height - padding.vertical).clamp(0, double.infinity),
      );

  @override
  bool operator ==(Object other) =>
      other is Rect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

final class EdgeInsets {
  const EdgeInsets.all(double value)
      : left = value,
        top = value,
        right = value,
        bottom = value;

  const EdgeInsets.symmetric({double horizontal = 0, double vertical = 0})
      : left = horizontal,
        right = horizontal,
        top = vertical,
        bottom = vertical;

  const EdgeInsets.only({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  static const zero = EdgeInsets.all(0);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get horizontal => left + right;
  double get vertical => top + bottom;

  Size inflateSize(Size size) =>
      Size(size.width + horizontal, size.height + vertical);

  @override
  bool operator ==(Object other) =>
      other is EdgeInsets &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

final class Color {
  const Color(this.value);

  static const transparent = Color(0x00000000);
  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);

  final int value;
}

final class Paint {
  const Paint(this.color);

  final Color color;
}

enum Orientation { horizontal, vertical }

enum TextAlignment { start, center, end }

enum HorizontalAlignment { left, center, right, stretch }

enum VerticalAlignment { top, center, bottom, stretch }
