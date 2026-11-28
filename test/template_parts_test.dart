import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('template parts', () {
    test('a text box offers the part with the text', () {
      final box = TextBox(text: 'Hello');

      expect(box.part('text'), isNotNull);
      expect(box.part('missing'), isNull);
      expect(box.templateParts, hasLength(1));
      expect(box.hasTemplate, isFalse);
    });

    test('a template places the text and the text survives it', () async {
      final box = TextBox(text: 'Hello');
      late Border root;

      box.template = ControlTemplate<TextBox>((control) {
        root = Border(
          color: const Color(0xFF224466),
          content: control.part('text'),
        );
        return root;
      });

      final window = Window(width: 200, height: 60, content: box);
      await window.show();
      window.updateLayout();

      expect(box.hasTemplate, isTrue);
      expect(root.logicalParent, same(box));
      expect(box.part('text')!.logicalParent, same(root));

      final renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(_texts(renderer), ['Hello']);
    });

    test('the text stays when the template ignores the part', () async {
      final box = TextBox(text: 'Hello');

      box.template = ControlTemplate<TextBox>((control) {
        return Border(color: const Color(0xFF224466));
      });

      final window = Window(width: 200, height: 60, content: box);
      await window.show();
      window.updateLayout();

      expect(box.part('text')!.logicalParent, same(box));
      final renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(_texts(renderer), ['Hello']);
    });

    test('the part outlives the template that placed it', () {
      final box = TextBox(text: 'Hello');
      late Border firstRoot;

      box.template = ControlTemplate<TextBox>((control) {
        firstRoot = Border(content: control.part('text'));
        return firstRoot;
      });
      final part = box.part('text')!;

      box.template = ControlTemplate<TextBox>((control) {
        return Border(content: control.part('text'));
      });

      expect(firstRoot.isDisposed, isTrue);
      expect(part.isDisposed, isFalse);
      expect(part.logicalParent, isNotNull);
      expect(part.logicalParent, isNot(same(firstRoot)));
    });

    test('the text comes back when the template is removed', () async {
      final box = TextBox(text: 'Hello');
      box.template = ControlTemplate<TextBox>((control) {
        return Border(content: control.part('text'));
      });

      final window = Window(width: 200, height: 60, content: box);
      await window.show();

      box.template = null;
      window.updateLayout();

      expect(box.hasTemplate, isFalse);
      expect(box.part('text')!.logicalParent, same(box));
      final renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(_texts(renderer), ['Hello']);
    });

    test('the parts are released with the control', () {
      final box = TextBox(text: 'Hello');
      final part = box.part('text')!;

      box.dispose();

      expect(part.isDisposed, isTrue);
    });

    test('a control cannot have two parts with the same name', () {
      final box = TextBox();

      expect(() => box.registerPart('text', Label()), throwsStateError);
    });

    test('a scroll viewer offers the content and the scroll bars', () {
      final viewer = ScrollViewer();

      expect(viewer.part('content'), isNotNull);
      expect(
        viewer.part('horizontalScrollBar'),
        same(viewer.horizontalScrollBar),
      );
      expect(viewer.part('verticalScrollBar'), same(viewer.verticalScrollBar));
      expect(viewer.templateParts, hasLength(3));
    });

    test('a template places the content and the bars of a scroll viewer',
        () async {
      final content = _FixedControl(const Size(400, 300));
      final viewer = ScrollViewer(content: content);
      late Grid root;

      viewer.template = ControlTemplate<ScrollViewer>((control) {
        root = _gridOf(control);
        return root;
      });

      final window = Window(width: 200, height: 100, content: viewer);
      await window.show();
      window.updateLayout();

      expect(root.logicalParent, same(viewer));
      expect(viewer.part('content')!.logicalParent, same(root));
      expect(viewer.horizontalScrollBar.logicalParent, same(root));
      expect(viewer.verticalScrollBar.logicalParent, same(root));
      expect(viewer.isHorizontalScrollBarVisible, isTrue);
      expect(viewer.isVerticalScrollBarVisible, isTrue);
    });

    test('the content of a scroll viewer stays clipped in a template',
        () async {
      final content = _FixedControl(const Size(400, 300));
      final viewer = ScrollViewer(content: content);

      viewer.template = ControlTemplate<ScrollViewer>(_gridOf);

      final window = Window(width: 200, height: 100, content: viewer);
      await window.show();
      window.updateLayout();

      final renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      final clip = renderer.commands.whereType<PushClipRectCommand>().single;
      expect(clip.rect, viewer.part('content')!.bounds);
    });

    test('the scroll bars of a template follow the offset of the viewer',
        () async {
      final content = _FixedControl(const Size(400, 300));
      final viewer = ScrollViewer(content: content);

      viewer.template = ControlTemplate<ScrollViewer>(_gridOf);

      final window = Window(width: 200, height: 100, content: viewer);
      await window.show();
      window.updateLayout();

      viewer.scrollTo(vertical: 48);
      window.updateLayout();

      expect(viewer.verticalOffset, 48);
      expect(viewer.verticalScrollBar.value, 48);
      expect(content.bounds.top, viewer.part('content')!.bounds.top - 48);
    });

    test('the content of a scroll viewer stays when the template is removed',
        () async {
      final content = _FixedControl(const Size(400, 300));
      final viewer = ScrollViewer(content: content);
      viewer.template = ControlTemplate<ScrollViewer>(_gridOf);

      final window = Window(width: 200, height: 100, content: viewer);
      await window.show();

      viewer.template = null;
      window.updateLayout();

      expect(viewer.content, same(content));
      expect(content.isDisposed, isFalse);
      expect(viewer.part('content')!.logicalParent, same(viewer));
    });
  });
}

/// A template that puts the content and the scroll bars of a viewer into a
/// grid, the way a scrollable area looks on a desktop.
Grid _gridOf(ScrollViewer control) {
  final content = control.part('content')!;
  final horizontal = control.part('horizontalScrollBar')!;
  final vertical = control.part('verticalScrollBar')!;
  Grid.setRow(content, 0);
  Grid.setColumn(content, 0);
  Grid.setRow(horizontal, 1);
  Grid.setColumn(horizontal, 0);
  Grid.setRow(vertical, 0);
  Grid.setColumn(vertical, 1);
  return Grid(
    columns: [
      ColumnDefinition(width: GridLength.star()),
      ColumnDefinition(
          width: GridLength.pixel(ScrollViewer.scrollBarThickness)),
    ],
    rows: [
      RowDefinition(height: GridLength.star()),
      RowDefinition(height: GridLength.pixel(ScrollViewer.scrollBarThickness)),
    ],
    children: [content, horizontal, vertical],
  );
}

List<String> _texts(RecordingDrawingContext renderer) => renderer.commands
    .whereType<DrawTextCommand>()
    .map((command) => command.text)
    .toList();

final class _FixedControl extends Control {
  _FixedControl(this.size);

  final Size size;

  @override
  Size measureCore(Size availableSize) => size;

  @override
  void renderCore(DrawingContext context) {
    context.drawRect(bounds, const Paint(Color(0xFFCCCCCC)));
  }
}
