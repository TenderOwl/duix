import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('CheckBox', () {
    test('the box starts unchecked and a click checks it', () {
      final checkBox = CheckBox();
      final window = Window(width: 200, height: 100, content: checkBox);
      window.updateLayout();

      expect(checkBox.isChecked, isFalse);

      window.dispatchPointerDown(Point(10, 10));
      window.dispatchPointerUp(Point(10, 10));

      expect(checkBox.isChecked, isTrue);
    });

    test('a second click checks the box back', () {
      final checkBox = CheckBox(isChecked: true);
      final window = Window(width: 200, height: 100, content: checkBox);
      window.updateLayout();

      window.dispatchPointerDown(Point(10, 10));
      window.dispatchPointerUp(Point(10, 10));

      expect(checkBox.isChecked, isFalse);
    });

    test('a click on the text of the label checks the box too', () {
      final checkBox = CheckBox(text: 'Enable notifications');
      final window = Window(width: 200, height: 100, content: checkBox);
      window.updateLayout();

      window.dispatchPointerDown(Point(120, 10));
      window.dispatchPointerUp(Point(120, 10));

      expect(checkBox.isChecked, isTrue);
    });

    test('Space checks the box of a focused control', () {
      final checkBox = CheckBox();
      final window = Window(width: 200, height: 100, content: checkBox);
      window.updateLayout();
      checkBox.focus();

      window.dispatchKeyDown('space');

      expect(checkBox.isChecked, isTrue);
      window.dispatchKeyDown('space');
      expect(checkBox.isChecked, isFalse);
    });

    test('the Enter key does not check the box', () {
      final checkBox = CheckBox();
      final window = Window(width: 200, height: 100, content: checkBox);
      window.updateLayout();
      checkBox.focus();

      window.dispatchKeyDown('enter');

      expect(checkBox.isChecked, isFalse);
    });

    test('the changed handler is called with the new state', () {
      final states = <bool>[];
      final checkBox = CheckBox(onChanged: states.add);
      final window = Window(width: 200, height: 100, content: checkBox);
      window.updateLayout();

      window.dispatchPointerDown(Point(10, 10));
      window.dispatchPointerUp(Point(10, 10));

      expect(states, [true]);
    });

    test('a two-way binding keeps the model and the control equal', () {
      final model = ObservableValue<bool>(false);
      final checkBox = CheckBox()
        ..bind(
          CheckBox.isCheckedProperty,
          model.asBinding(),
          mode: BindingMode.twoWay,
        );
      final window = Window(width: 200, height: 100, content: checkBox);
      window.updateLayout();

      window.dispatchPointerDown(Point(10, 10));
      window.dispatchPointerUp(Point(10, 10));

      expect(model.value, isTrue);
      expect(checkBox.isChecked, isTrue);

      model.value = false;
      expect(checkBox.isChecked, isFalse);
    });

    test('a disabled control does not change its state', () {
      final checkBox = CheckBox()..isEnabled = false;
      final window = Window(width: 200, height: 100, content: checkBox);
      window.updateLayout();

      window.dispatchPointerDown(Point(10, 10));
      window.dispatchPointerUp(Point(10, 10));

      expect(checkBox.isChecked, isFalse);
    });

    test('the measure of the control holds the box and the text', () {
      final checkBox = CheckBox(text: 'one', fontSize: 10);

      final size = checkBox.measure(const Size(200, 100));

      // The box and the gap take 26 points, the text of three characters of
      // 6 points takes 18 more.
      expect(size.width, 26 + 18);
      expect(size.height, greaterThanOrEqualTo(CheckableControl.markSize));
    });

    test('the box stands at the left edge and the text next to it', () {
      final checkBox = CheckBox(text: 'one', fontSize: 10);
      final window = Window(width: 200, height: 100, content: checkBox);
      window.updateLayout();

      expect(checkBox.markRect.left, checkBox.bounds.left);
      expect(
        checkBox.labelRect.left,
        checkBox.bounds.left +
            CheckableControl.markSize +
            CheckableControl.gapSize,
      );
    });

    test('the box stands at the right edge in a right to left tree', () {
      final checkBox = CheckBox(text: 'one', fontSize: 10);
      final window = Window(width: 200, height: 100, content: checkBox)
        ..flowDirection = FlowDirection.rightToLeft;
      window.updateLayout();

      expect(checkBox.markRect.right, checkBox.bounds.right);
      expect(
        checkBox.labelRect.right,
        checkBox.bounds.right -
            CheckableControl.markSize -
            CheckableControl.gapSize,
      );
    });

    test('the control draws the box and the check mark', () async {
      final checkBox = CheckBox();
      final window = Window(width: 200, height: 100, content: checkBox);
      await window.show();
      final renderer = RecordingDrawingContext();

      window.renderFrame(renderer);
      final empty = renderer.commands.whereType<DrawPathCommand>().length;

      checkBox.isChecked = true;
      window.renderFrame(renderer);
      final marked = renderer.commands.whereType<DrawPathCommand>().length;

      expect(empty, 0, reason: 'an unchecked box has no check mark');
      expect(marked, 1, reason: 'a checked box draws the check mark');
    });

    test('the control draws the text of the label', () async {
      final checkBox = CheckBox(text: 'one');
      final window = Window(width: 200, height: 100, content: checkBox);
      await window.show();
      final renderer = RecordingDrawingContext();

      window.renderFrame(renderer);

      final texts = renderer.commands.whereType<DrawTextCommand>().toList();
      expect(texts, hasLength(1));
      expect(texts.first.text, 'one');
      expect(
        texts.first.position.x,
        greaterThanOrEqualTo(
          checkBox.bounds.left +
              CheckableControl.markSize +
              CheckableControl.gapSize,
        ),
      );
    });

    test('a disabled control draws the check mark in gray', () async {
      final checkBox = CheckBox(text: 'one', isChecked: true)
        ..isEnabled = false;
      final window = Window(width: 200, height: 100, content: checkBox);
      await window.show();
      final renderer = RecordingDrawingContext();

      window.renderFrame(renderer);

      final mark = renderer.commands.whereType<DrawPathCommand>().single;
      final text = renderer.commands.whereType<DrawTextCommand>().single;
      expect(mark.paint.color.value, CheckableControl.disabledColor.value);
      expect(text.color.value, CheckableControl.disabledColor.value);
    });

    test('the semantics of the control carry the state and the name', () {
      final checkBox = CheckBox(text: 'Enable notifications');

      final tree = SemanticsTree.fromElement(checkBox);
      final node = tree.nodeFor(checkBox)!;

      expect(node.role, SemanticsRole.checkBox);
      expect(node.name, 'Enable notifications');
      expect(node.state.checked, isFalse);

      checkBox.isChecked = true;
      final checked = SemanticsTree.fromElement(checkBox).nodeFor(checkBox)!;
      expect(checked.state.checked, isTrue);
    });

    test('the control keeps the focus when it is pressed', () {
      final checkBox = CheckBox();
      final window = Window(width: 200, height: 100, content: checkBox);
      window.updateLayout();

      window.dispatchPointerDown(Point(10, 10));

      expect(checkBox.isFocused, isTrue);
      expect(checkBox.state.pressed, isTrue);
    });
  });
}
