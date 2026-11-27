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
      final border = Border(content: Label(text: 'Hello'));

      expect(border.template, isNull);
      expect(
        () => border.template = ControlTemplate<Border>((control) => Label()),
        throwsStateError,
      );
    });
  });
}

List<DrawRectCommand> _focusRing(RecordingDrawingContext renderer) =>
    renderer.commands
        .whereType<DrawRectCommand>()
        .where((command) => command.paint.color.value == _focusRingColor)
        .toList();
