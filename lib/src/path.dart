import 'geometry.dart';

/// The kind of a command of a path.
enum PathCommandType { move, line, quad, cubic, close }

/// One command of a path with its points.
final class PathCommand {
  const PathCommand(
    this.type, [
    this.x1 = 0,
    this.y1 = 0,
    this.x2 = 0,
    this.y2 = 0,
    this.x3 = 0,
    this.y3 = 0,
  ]);

  /// The kind of the command.
  final PathCommandType type;

  /// The first point of the command.
  final double x1;
  final double y1;

  /// The second point of the command.
  final double x2;
  final double y2;

  /// The third point of the command.
  final double x3;
  final double y3;
}

/// A path of segments that a widget can draw.
///
/// The path is a list of commands: the pen moves, draws straight lines and
/// curves and closes the contours. The commands of the path are drawn in the
/// order they were added.
final class Path {
  Path();

  /// The commands of the path.
  final commands = <PathCommand>[];

  /// Whether the path holds no commands.
  bool get isEmpty => commands.isEmpty;

  /// Moves the pen to a point without drawing.
  void moveTo(Point point) {
    commands.add(PathCommand(PathCommandType.move, point.x, point.y));
  }

  /// Draws a straight line from the pen to a point.
  void lineTo(Point point) {
    commands.add(PathCommand(PathCommandType.line, point.x, point.y));
  }

  /// Draws a quadratic curve from the pen to a point.
  void quadTo(Point control, Point end) {
    commands.add(
      PathCommand(PathCommandType.quad, control.x, control.y, end.x, end.y),
    );
  }

  /// Draws a cubic curve from the pen to a point.
  void cubicTo(Point control1, Point control2, Point end) {
    commands.add(
      PathCommand(
        PathCommandType.cubic,
        control1.x,
        control1.y,
        control2.x,
        control2.y,
        end.x,
        end.y,
      ),
    );
  }

  /// Closes the current contour with a straight line.
  void close() {
    commands.add(const PathCommand(PathCommandType.close));
  }

  /// Adds a rectangle as a closed contour.
  void addRect(Rect rect) {
    moveTo(Point(rect.left, rect.top));
    lineTo(Point(rect.right, rect.top));
    lineTo(Point(rect.right, rect.bottom));
    lineTo(Point(rect.left, rect.bottom));
    close();
  }

  /// Adds a rounded rectangle as a closed contour.
  ///
  /// The radii are clamped, so a big radius does not fold the shape.
  void addRoundedRect(Rect rect, double radiusX, double radiusY) {
    final rx = radiusX.clamp(0.0, rect.width / 2);
    final ry = radiusY.clamp(0.0, rect.height / 2);
    moveTo(Point(rect.left + rx, rect.top));
    lineTo(Point(rect.right - rx, rect.top));
    quadTo(Point(rect.right, rect.top), Point(rect.right, rect.top + ry));
    lineTo(Point(rect.right, rect.bottom - ry));
    quadTo(Point(rect.right, rect.bottom), Point(rect.right - rx, rect.bottom));
    lineTo(Point(rect.left + rx, rect.bottom));
    quadTo(Point(rect.left, rect.bottom), Point(rect.left, rect.bottom - ry));
    lineTo(Point(rect.left, rect.top + ry));
    quadTo(Point(rect.left, rect.top), Point(rect.left + rx, rect.top));
    close();
  }

  /// The bounds of the path, or null when the path is empty.
  ///
  /// The bounds hold every point of the commands, the control points of the
  /// curves included, so they are a safe frame around the path.
  Rect? get bounds {
    if (commands.isEmpty) return null;
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    void include(double x, double y) {
      if (x < left) left = x;
      if (y < top) top = y;
      if (x > right) right = x;
      if (y > bottom) bottom = y;
    }

    for (final command in commands) {
      switch (command.type) {
        case PathCommandType.move:
        case PathCommandType.line:
          include(command.x1, command.y1);
        case PathCommandType.quad:
          include(command.x1, command.y1);
          include(command.x2, command.y2);
        case PathCommandType.cubic:
          include(command.x1, command.y1);
          include(command.x2, command.y2);
          include(command.x3, command.y3);
        case PathCommandType.close:
          break;
      }
    }
    if (left == double.infinity) return null;
    return Rect.fromLTWH(left, top, right - left, bottom - top);
  }
}
