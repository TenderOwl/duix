import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('the path of a widget', () {
    test('holds the commands in the order they were added', () {
      final path = Path()
        ..moveTo(const Point(0, 0))
        ..lineTo(const Point(10, 0))
        ..quadTo(const Point(20, 0), const Point(20, 10))
        ..cubicTo(
          const Point(20, 20),
          const Point(10, 20),
          const Point(10, 10),
        )
        ..close();

      expect(path.isEmpty, isFalse);
      expect(path.commands, hasLength(5));
      expect(path.commands[0].type, PathCommandType.move);
      expect(path.commands[0].x1, 0);
      expect(path.commands[0].y1, 0);
      expect(path.commands[1].type, PathCommandType.line);
      expect(path.commands[1].x1, 10);
      expect(path.commands[2].type, PathCommandType.quad);
      expect(path.commands[2].x1, 20);
      expect(path.commands[2].y1, 0);
      expect(path.commands[2].x2, 20);
      expect(path.commands[2].y2, 10);
      expect(path.commands[3].type, PathCommandType.cubic);
      expect(path.commands[3].x3, 10);
      expect(path.commands[3].y3, 10);
      expect(path.commands[4].type, PathCommandType.close);
    });

    test('is empty until a command is added', () {
      final path = Path();
      expect(path.isEmpty, isTrue);
      expect(path.bounds, isNull);

      path.moveTo(const Point(4, 5));
      expect(path.isEmpty, isFalse);
    });

    test('a rectangle is a closed contour', () {
      final path = Path()..addRect(const Rect.fromLTWH(10, 20, 30, 40));

      expect(path.commands.first.type, PathCommandType.move);
      expect(path.commands.last.type, PathCommandType.close);
      expect(path.bounds?.left, 10);
      expect(path.bounds?.top, 20);
      expect(path.bounds?.width, 30);
      expect(path.bounds?.height, 40);
    });

    test('a rounded rectangle clamps the radii', () {
      final path = Path()
        ..addRoundedRect(const Rect.fromLTWH(0, 0, 40, 20), 100, 100);

      final bounds = path.bounds;
      expect(bounds?.left, 0);
      expect(bounds?.top, 0);
      expect(bounds?.width, 40);
      expect(bounds?.height, 20);
      // The contour is closed and holds the curves of the corners.
      expect(path.commands.last.type, PathCommandType.close);
      expect(
        path.commands.where((command) => command.type == PathCommandType.quad),
        hasLength(4),
      );
    });

    test('the bounds hold the control points of the curves', () {
      final path = Path()
        ..moveTo(const Point(0, 0))
        ..cubicTo(
          const Point(0, 50),
          const Point(100, 50),
          const Point(100, 0),
        );

      expect(path.bounds?.height, 50);
      expect(path.bounds?.width, 100);
    });
  });

  group('the paint of a shape', () {
    test('fills the shape by default', () {
      const paint = Paint(Color(0xFF102030));
      expect(paint.strokeWidth, 0);
      expect(paint.isStroke, isFalse);
      expect(paint.opacity, 1);
      expect(paint.blendMode, BlendMode.srcOver);
      expect(paint.shadow, isNull);
    });

    test('carries the transparency, the blend mode and the shadow', () {
      const paint = Paint(
        Color(0xFF102030),
        strokeWidth: 2,
        opacity: 0.5,
        blendMode: BlendMode.multiply,
        shadow:
            Shadow(Color(0x80000000), blurRadius: 4, offsetX: 1, offsetY: 2),
      );

      expect(paint.isStroke, isTrue);
      expect(paint.opacity, 0.5);
      expect(paint.blendMode, BlendMode.multiply);
      expect(paint.shadow?.color.value, 0x80000000);
      expect(paint.shadow?.blurRadius, 4);
      expect(paint.shadow?.offsetX, 1);
      expect(paint.shadow?.offsetY, 2);
    });
  });

  group('the recording of the drawing', () {
    test('holds the path and the paint of the shape', () {
      final context = RecordingDrawingContext();
      final path = Path()..addRect(const Rect.fromLTWH(1, 2, 3, 4));
      const paint = Paint(Color(0xFF00FF00), opacity: 0.25);

      context.drawPath(path, paint);

      expect(context.commands, hasLength(1));
      final command = context.commands.single as DrawPathCommand;
      expect(command.path, same(path));
      expect(command.paint.opacity, 0.25);
      expect(command.strokeWidth, 0);
    });
  });
}
