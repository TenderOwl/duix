import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('popup layer', () {
    test('a popup is placed below the area that opened it', () async {
      final window =
          Window(width: 200, height: 200, content: Label(text: 'Base'));
      await window.show();

      window.overlay.open(
        _FixedControl(const Size(40, 20)),
        ownerArea: const Rect.fromLTWH(10, 10, 50, 20),
      );
      window.updateLayout();

      expect(window.overlay.isOpen, isTrue);
      expect(window.overlay.popupRect, const Rect.fromLTWH(10, 30, 40, 20));
    });

    test('a popup follows the placement', () async {
      final window =
          Window(width: 200, height: 200, content: Label(text: 'Base'));
      await window.show();
      const owner = Rect.fromLTWH(10, 40, 50, 20);

      window.overlay.open(
        _FixedControl(const Size(40, 20)),
        ownerArea: owner,
        placement: PopupPlacement.above,
      );
      window.updateLayout();
      expect(window.overlay.popupRect, const Rect.fromLTWH(10, 20, 40, 20));

      window.overlay.open(
        _FixedControl(const Size(40, 20)),
        ownerArea: owner,
        placement: PopupPlacement.right,
      );
      window.updateLayout();
      expect(window.overlay.popupRect, const Rect.fromLTWH(60, 40, 40, 20));

      window.overlay.open(
        _FixedControl(const Size(40, 20)),
        ownerArea: owner,
        placement: PopupPlacement.left,
      );
      window.updateLayout();
      expect(window.overlay.popupRect, const Rect.fromLTWH(-30, 40, 40, 20));

      window.overlay.open(
        _FixedControl(const Size(40, 20)),
        ownerArea: owner,
        pointerPosition: const Point(80, 90),
        placement: PopupPlacement.atPointer,
      );
      window.updateLayout();
      expect(window.overlay.popupRect, const Rect.fromLTWH(80, 90, 40, 20));
    });

    test('a popup that does not fit below opens above', () async {
      final window =
          Window(width: 200, height: 200, content: Label(text: 'Base'));
      await window.show();

      window.overlay.open(
        _FixedControl(const Size(40, 60)),
        ownerArea: const Rect.fromLTWH(10, 160, 50, 20),
      );
      window.updateLayout();

      expect(window.overlay.popupRect.top, 100);
    });

    test('the popup is drawn above the content of the window', () async {
      final window = Window(
          width: 200,
          height: 200,
          content: _FixedControl(const Size(200, 200)));
      await window.show();
      window.overlay.open(
        _FixedControl(const Size(40, 20)),
        ownerArea: const Rect.fromLTWH(10, 10, 50, 20),
      );
      final renderer = RecordingDrawingContext();

      window.renderFrame(renderer);

      final rectangles =
          renderer.commands.whereType<DrawRectCommand>().toList();
      expect(rectangles.length, 2);
      expect(rectangles.first.rect, const Rect.fromLTWH(0, 0, 200, 200));
      expect(rectangles.last.rect, const Rect.fromLTWH(10, 30, 40, 20));
    });

    test(
        'a click outside of the popup closes it and does not reach the content',
        () async {
      var clicks = 0;
      final content = _FixedControl(
        const Size(200, 200),
        onPointerDown: () => clicks++,
      );
      final window = Window(width: 200, height: 200, content: content);
      await window.show();
      window.overlay.open(
        _FixedControl(const Size(40, 20)),
        ownerArea: const Rect.fromLTWH(10, 10, 50, 20),
      );
      window.updateLayout();

      window.dispatchPointerDown(const Point(150, 150));

      expect(window.overlay.isOpen, isFalse);
      expect(clicks, 0);
    });

    test('a click inside of the popup reaches the popup', () async {
      var clicks = 0;
      final window = Window(
          width: 200,
          height: 200,
          content: _FixedControl(const Size(200, 200)));
      await window.show();
      window.overlay.open(
        _FixedControl(const Size(40, 20), onPointerDown: () => clicks++),
        ownerArea: const Rect.fromLTWH(10, 10, 50, 20),
      );
      window.updateLayout();

      window.dispatchPointerDown(const Point(20, 35));

      expect(clicks, 1);
      expect(window.overlay.isOpen, isTrue);
    });

    test('escape closes the popup and the focus goes back', () async {
      final content = Button(content: Label(text: 'Base'));
      final window = Window(width: 200, height: 200, content: content);
      await window.show();
      content.focus();
      expect(window.focusedElement, same(content));
      window.overlay.open(
        _FixedControl(const Size(40, 20)),
        ownerArea: const Rect.fromLTWH(10, 10, 50, 20),
      );

      expect(window.focusedElement, same(window.overlay));

      window.dispatchKeyDown('escape');

      expect(window.overlay.isOpen, isFalse);
      expect(window.focusedElement, same(content));
    });

    test('a closed popup does not take the clicks of the window', () async {
      var clicks = 0;
      final window = Window(
        width: 200,
        height: 200,
        content:
            _FixedControl(const Size(200, 200), onPointerDown: () => clicks++),
      );
      await window.show();

      window.dispatchPointerDown(const Point(150, 150));

      expect(clicks, 1);
    });
  });
}

final class _FixedControl extends Control {
  _FixedControl(this.size, {this.onPointerDown});

  final Size size;
  final void Function()? onPointerDown;

  @override
  bool get isFocusable => false;

  @override
  Size measureCore(Size availableSize) => size;

  @override
  void renderCore(DrawingContext context) {
    context.drawRect(bounds, const Paint(Color(0xFF808080)));
  }

  @override
  void onMounted() {
    if (onPointerDown == null) return;
    addHandler(UIElement.pointerDown, (sender, args) => onPointerDown!());
  }
}
