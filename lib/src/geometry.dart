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

  /// Mixes two colors.
  ///
  /// The share of the mix tells how much of the second color is in the
  /// result: zero gives the first color, one gives the second one.
  static Color lerp(Color from, Color to, double share) {
    final t = share < 0 ? 0.0 : (share > 1 ? 1.0 : share);
    int channel(int shift) {
      final a = (from.value >> shift) & 0xFF;
      final b = (to.value >> shift) & 0xFF;
      return (a + (b - a) * t).round().clamp(0, 255).toInt();
    }

    return Color(
      (channel(24) << 24) |
          (channel(16) << 16) |
          (channel(8) << 8) |
          channel(0),
    );
  }
}

/// The way a shape is mixed with the pixels under it.
enum BlendMode {
  /// The shape covers the pixels under it.
  srcOver,

  /// The shape keeps the light of the pixels under it.
  screen,

  /// The shape keeps the dark of the pixels under it.
  multiply,

  /// The shape adds its color to the pixels under it.
  plus,

  /// The shape inverts the pixels under it.
  difference,

  /// The lighter of the shape and the pixels under it wins.
  lighten,

  /// The darker of the shape and the pixels under it wins.
  darken,

  /// The shape multiplies or screens the pixels under it.
  overlay,
}

/// A soft shadow under a shape.
final class Shadow {
  const Shadow(
    this.color, {
    this.blurRadius = 0,
    this.offsetX = 0,
    this.offsetY = 0,
  });

  /// The color of the shadow.
  final Color color;

  /// The softness of the shadow.
  ///
  /// Zero draws a hard shadow, a bigger value spreads it.
  final double blurRadius;

  /// The horizontal shift of the shadow.
  final double offsetX;

  /// The vertical shift of the shadow.
  final double offsetY;
}

final class Paint {
  const Paint(
    this.color, {
    this.strokeWidth = 0,
    this.opacity = 1,
    this.blendMode = BlendMode.srcOver,
    this.shadow,
  });

  /// The color of the paint.
  final Color color;

  /// The width of the stroke.
  ///
  /// Zero fills the shape. A positive value strokes its outline with that
  /// width, so the paint decides how a shape is drawn.
  final double strokeWidth;

  /// The transparency of the paint.
  ///
  /// One is opaque, zero is invisible. The value multiplies the alpha of the
  /// color of the paint.
  final double opacity;

  /// The way the paint is mixed with the pixels under it.
  final BlendMode blendMode;

  /// The shadow under the shape.
  ///
  /// The shadow is the silhouette of the shape, blurred and shifted.
  final Shadow? shadow;

  /// Whether the paint strokes the outline instead of filling the shape.
  bool get isStroke => strokeWidth > 0;
}

enum Orientation { horizontal, vertical }

enum TextAlignment { start, center, end }

enum HorizontalAlignment { left, center, right, stretch, start, end }

enum VerticalAlignment { top, center, bottom, stretch }

/// The direction the layout of a tree follows.
///
/// The direction decides where the start of the layout is: the left edge of
/// the window for [leftToRight] and the right edge for [rightToLeft]. The
/// logical alignment (`start` and `end`), the order of the children of a
/// panel and the side of a dock follow it.
enum FlowDirection { leftToRight, rightToLeft }
