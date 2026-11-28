import 'package:duix/dui.dart';
import 'package:test/test.dart';

const _focusRingColor = 0xFF356AC3;

/// A control that is not a button, but supports a template like every other
/// templated control.
final class _Panel extends ContentControl {
  _Panel({super.content}) : super(templateProperty: templateProperty);

  static const templateProperty = DuiProperty<_Panel, ControlTemplate<_Panel>?>(
    name: 'template',
    defaultValue: null,
    affectsMeasure: true,
    affectsPaint: true,
  );

  @override
  ControlTemplate<_Panel>? get template =>
      super.template as ControlTemplate<_Panel>?;
}

/// A control that inherits the template mechanics but declares no template
/// property of its own.
final class _Plain extends TemplatedControl {}

void main() {
  group('templated control', () {
    test('a template works for any control, not only for a button', () {
      final label = Label(text: 'Hello');
      final panel = _Panel(content: label);
      expect(panel.hasTemplate, isFalse);
      expect(panel.template, isNull);

      late Border root;
      late ContentPresenter presenter;
      panel.template = ControlTemplate<_Panel>((control) {
        presenter = ContentPresenter(control);
        root = Border(
          color: const Color(0xFF224466),
          content: presenter,
        );
        return root;
      });

      expect(panel.hasTemplate, isTrue);
      expect(panel.templateRoot, same(root));
      expect(root.logicalParent, same(panel));
      expect(panel.logicalChildren, [same(root)]);
      expect(presenter.content, same(label));
      expect(label.logicalParent, same(presenter));
    });

    test('the template owns the measure and the arrange of the control',
        () async {
      final panel = _Panel(content: Label(text: 'Hello'));
      late Border root;
      panel.template = ControlTemplate<_Panel>((control) {
        root = Border(content: ContentPresenter(control));
        return root;
      });

      final window = Window(width: 200, height: 100, content: panel);
      await window.show();
      window.updateLayout();

      expect(panel.templateRoot, same(root));
      expect(root.bounds.width, 200);
      expect(root.bounds.height, 100);
    });

    test('the content comes back when the template is removed', () {
      final label = Label(text: 'Hello');
      final panel = _Panel(content: label);
      late Border root;
      panel.template = ControlTemplate<_Panel>((control) {
        root = Border(content: ContentPresenter(control));
        return root;
      });

      panel.template = null;

      expect(panel.hasTemplate, isFalse);
      expect(panel.templateRoot, isNull);
      expect(panel.content, same(label));
      expect(label.logicalParent, same(panel));
      expect(label.isDisposed, isFalse);
      expect(root.isDisposed, isTrue);
    });

    test('a replaced template disposes the old subtree and keeps the content',
        () {
      final label = Label(text: 'Hello');
      final panel = _Panel(content: label);
      late Border firstRoot;
      late Border secondRoot;
      late ContentPresenter secondPresenter;

      panel.template = ControlTemplate<_Panel>((control) {
        firstRoot = Border(content: ContentPresenter(control));
        return firstRoot;
      });
      panel.template = ControlTemplate<_Panel>((control) {
        secondPresenter = ContentPresenter(control);
        secondRoot = Border(content: secondPresenter);
        return secondRoot;
      });

      expect(panel.templateRoot, same(secondRoot));
      expect(firstRoot.isDisposed, isTrue);
      expect(secondPresenter.content, same(label));
      expect(label.logicalParent, same(secondPresenter));
      expect(label.isDisposed, isFalse);
    });

    test('the template subtree is disposed together with the control', () {
      final panel = _Panel(content: Label(text: 'Hello'));
      late Border root;
      panel.template = ControlTemplate<_Panel>((control) {
        root = Border(content: ContentPresenter(control));
        return root;
      });

      panel.dispose();

      expect(root.isDisposed, isTrue);
    });

    test('a templated control draws the focus ring on its own', () async {
      final panel = _Panel(content: Label(text: 'Hello'));
      final window = Window(width: 120, height: 50, content: panel);
      await window.show();

      var renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(_focusRing(renderer), isEmpty);

      panel.focus();
      renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(_focusRing(renderer), hasLength(4));
    });

    test('a control without a template property does not support templates',
        () {
      final plain = _Plain();

      expect(plain.template, isNull);
      expect(
        () => plain.template = ControlTemplate<_Plain>((control) => Label()),
        throwsStateError,
      );
    });

    test('a label can be templated', () {
      final label = Label(text: 'Outer');
      late Border root;
      label.template = ControlTemplate<Label>((control) {
        root = Border(
          color: const Color(0xFF224466),
          content: Label(text: 'Inner'),
        );
        return root;
      });

      expect(label.hasTemplate, isTrue);
      expect(label.templateRoot, same(root));
      expect(root.logicalParent, same(label));
    });

    test('the template of a label replaces its own text', () async {
      final label = Label(text: 'Outer');
      final window = Window(width: 200, height: 100, content: label);
      await window.show();

      var renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(_texts(renderer), ['Outer']);

      label.template = ControlTemplate<Label>((control) {
        return Border(content: Label(text: 'Inner'));
      });

      renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(_texts(renderer), ['Inner']);
    });

    test('the text of a label comes back when the template is removed',
        () async {
      final label = Label(text: 'Outer');
      final window = Window(width: 200, height: 100, content: label);
      await window.show();

      label.template = ControlTemplate<Label>((control) {
        return Border(content: Label(text: 'Inner'));
      });
      label.template = null;

      final renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(_texts(renderer), ['Outer']);
      expect(label.hasTemplate, isFalse);
    });

    test('a border can be templated and presents its content', () {
      final content = Label(text: 'Hello');
      final border = Border(content: content);
      late Border root;
      late ContentPresenter presenter;
      border.template = ControlTemplate<Border>((control) {
        presenter = ContentPresenter(control);
        root = Border(color: const Color(0xFF224466), content: presenter);
        return root;
      });

      expect(border.hasTemplate, isTrue);
      expect(border.templateRoot, same(root));
      expect(presenter.content, same(content));
      expect(content.logicalParent, same(presenter));
    });

    test('a scroll bar can be templated', () async {
      final bar = ScrollBar(maximum: 100, value: 20, viewportSize: 50);
      final window = Window(width: 100, height: 200, content: bar);
      await window.show();

      var renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(renderer.commands.whereType<DrawRectCommand>(), hasLength(2));

      late Border root;
      bar.template = ControlTemplate<ScrollBar>((control) {
        root = Border(color: const Color(0xFF224466));
        return root;
      });

      expect(bar.hasTemplate, isTrue);
      expect(bar.templateRoot, same(root));

      renderer = RecordingDrawingContext();
      window.renderFrame(renderer);
      expect(renderer.commands.whereType<DrawRectCommand>(), hasLength(1));
    });
  });
}

List<String> _texts(RecordingDrawingContext renderer) => renderer.commands
    .whereType<DrawTextCommand>()
    .map((command) => command.text)
    .toList();

List<DrawRectCommand> _focusRing(RecordingDrawingContext renderer) =>
    renderer.commands
        .whereType<DrawRectCommand>()
        .where((command) => command.paint.color.value == _focusRingColor)
        .toList();
