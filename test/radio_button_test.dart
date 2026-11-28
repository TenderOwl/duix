import 'package:duix/dui.dart';
import 'package:test/test.dart';

/// Builds a group of two radio buttons.
RadioGroup<String> buildGroup({
  String? selectedValue,
  String first = 'one',
  String second = 'two',
}) {
  final group = RadioGroup<String>(
    selectedValue: selectedValue,
    content: StackPanel(
      spacing: 8,
      children: [
        RadioButton<String>(value: first, text: 'First'),
        RadioButton<String>(value: second, text: 'Second'),
      ],
    ),
  );
  return group;
}

void main() {
  group('RadioGroup', () {
    test('the group finds the buttons of its content', () {
      final group = buildGroup();

      expect(group.radioButtons, hasLength(2));
      expect(group.radioButtons.first.value, 'one');
      expect(group.radioButtons.last.value, 'two');
    });

    test('the group checks the button of its value', () {
      final group = buildGroup(selectedValue: 'two');
      final window = Window(width: 200, height: 200, content: group);
      window.updateLayout();

      expect(group.radioButtons.first.isChecked, isFalse);
      expect(group.radioButtons.last.isChecked, isTrue);
    });

    test('a click checks the button and unchecks the other one', () {
      final group = buildGroup();
      final window = Window(width: 200, height: 200, content: group);
      window.updateLayout();
      final buttons = group.radioButtons;

      final position = Point(
        buttons.first.bounds.left + 4,
        buttons.first.bounds.top + buttons.first.bounds.height / 2,
      );
      window.dispatchPointerDown(position);
      window.dispatchPointerUp(position);

      expect(buttons.first.isChecked, isTrue);
      expect(buttons.last.isChecked, isFalse);
      expect(group.selectedValue, 'one');
    });

    test('a click on a checked button keeps it checked', () {
      final group = buildGroup(selectedValue: 'one');
      final window = Window(width: 200, height: 200, content: group);
      window.updateLayout();
      final button = group.radioButtons.first;

      final position = Point(
        button.bounds.left + 4,
        button.bounds.top + button.bounds.height / 2,
      );
      window.dispatchPointerDown(position);
      window.dispatchPointerUp(position);

      expect(button.isChecked, isTrue);
      expect(group.selectedValue, 'one');
    });

    test('the value of the group follows the checked button', () {
      final group = buildGroup();
      final window = Window(width: 200, height: 200, content: group);
      window.updateLayout();

      group.radioButtons.last.select();

      expect(group.selectedValue, 'two');
      expect(group.radioButtons.first.isChecked, isFalse);
    });

    test('the value of the group checks the button that holds it', () {
      final group = buildGroup();
      final window = Window(width: 200, height: 200, content: group);
      window.updateLayout();

      group.selectedValue = 'two';

      expect(group.radioButtons.last.isChecked, isTrue);
      expect(group.radioButtons.first.isChecked, isFalse);
    });

    test('the changed handler of the group is called with the new value', () {
      final values = <String?>[];
      final group = buildGroup();
      group.addChangedHandler(values.add);
      final window = Window(width: 200, height: 200, content: group);
      window.updateLayout();

      group.radioButtons.first.select();

      expect(values, ['one']);
    });

    test('the value of the group can be bound to a model', () {
      final model = ObservableValue<String?>('one');
      final group = buildGroup();
      group.bind(
        RadioGroup.selectedValueProperty,
        model.asBinding(),
        mode: BindingMode.twoWay,
      );
      final window = Window(width: 200, height: 200, content: group);
      window.updateLayout();

      group.radioButtons.last.select();

      expect(model.value, 'two');
      expect(group.radioButtons.last.isChecked, isTrue);
    });

    test('the arrows walk over the buttons and move the focus', () {
      final group = buildGroup(selectedValue: 'one');
      final window = Window(width: 200, height: 200, content: group);
      window.updateLayout();
      final buttons = group.radioButtons;
      buttons.first.focus();

      window.dispatchKeyDown('down');

      expect(buttons.last.isChecked, isTrue);
      expect(buttons.first.isChecked, isFalse);
      expect(buttons.last.isFocused, isTrue);
      expect(group.selectedValue, 'two');

      window.dispatchKeyDown('up');

      expect(buttons.first.isChecked, isTrue);
      expect(buttons.first.isFocused, isTrue);
    });

    test('the arrows of a horizontal group walk to the sides', () {
      final group = buildGroup(selectedValue: 'one')
        ..orientation = Orientation.horizontal;
      final window = Window(width: 200, height: 200, content: group);
      window.updateLayout();
      final buttons = group.radioButtons;
      buttons.first.focus();

      window.dispatchKeyDown('right');

      expect(buttons.last.isChecked, isTrue);
      expect(group.selectedValue, 'two');
    });

    test('the vertical arrows do not move a horizontal group', () {
      final group = buildGroup(selectedValue: 'one')
        ..orientation = Orientation.horizontal;
      final window = Window(width: 200, height: 200, content: group);
      window.updateLayout();
      final buttons = group.radioButtons;
      buttons.first.focus();

      window.dispatchKeyDown('down');

      expect(buttons.first.isChecked, isTrue);
      expect(group.selectedValue, 'one');
    });

    test('the space bar checks the focused button', () {
      final group = buildGroup();
      final window = Window(width: 200, height: 200, content: group);
      window.updateLayout();
      final buttons = group.radioButtons;
      buttons.first.focus();

      window.dispatchKeyDown('space');

      expect(buttons.first.isChecked, isTrue);
      expect(group.selectedValue, 'one');
    });

    test('the group is a focus scope', () {
      final group = buildGroup();
      final outside = CheckBox(text: 'Outside');
      final window = Window(
        width: 200,
        height: 200,
        content: StackPanel(children: [group, outside]),
      );
      window.updateLayout();
      final buttons = group.radioButtons;

      buttons.first.focus();
      window.dispatchKeyDown('tab');

      expect(buttons.last.isFocused, isTrue);
      expect(outside.isFocused, isFalse);
    });

    test('the buttons of a nested group belong to that group', () {
      final inner = buildGroup(selectedValue: 'one');
      final outer = RadioGroup<String>(
        content: StackPanel(
          children: [
            RadioButton<String>(value: 'outer', text: 'Outer'),
            inner,
          ],
        ),
      );
      final window = Window(width: 200, height: 300, content: outer);
      window.updateLayout();

      expect(outer.radioButtons, hasLength(1));
      expect(outer.radioButtons.single.value, 'outer');
      expect(inner.radioButtons, hasLength(2));
    });

    test('the semantics of the group and of the buttons carry the state', () {
      final group = buildGroup(selectedValue: 'one');
      final window = Window(width: 200, height: 200, content: group);
      window.updateLayout();

      final tree = SemanticsTree.fromElement(group);
      final groupNode = tree.nodeFor(group)!;
      final buttonNode = tree.nodeFor(group.radioButtons.first)!;

      expect(groupNode.role, SemanticsRole.group);
      expect(buttonNode.role, SemanticsRole.radioButton);
      expect(buttonNode.name, 'First');
      expect(buttonNode.state.checked, isTrue);
    });
  });

  group('RadioButton', () {
    test('a button without a group keeps its own state', () {
      final button = RadioButton<String>(value: 'one', text: 'First');
      final window = Window(width: 200, height: 100, content: button);
      window.updateLayout();

      button.select();

      expect(button.isChecked, isTrue);
      expect(button.group, isNull);
    });

    test('the button draws a circle and the dot of a checked button', () async {
      final button = RadioButton<String>(value: 'one', text: 'First');
      final window = Window(width: 200, height: 100, content: button);
      await window.show();
      final renderer = RecordingDrawingContext();

      window.renderFrame(renderer);
      final empty = renderer.commands.whereType<DrawPathCommand>().length;

      button.isChecked = true;
      final checked = RecordingDrawingContext();
      window.renderFrame(checked);
      final marked = checked.commands.whereType<DrawPathCommand>().length;

      expect(empty, 1, reason: 'an unchecked button draws the circle only');
      expect(marked, 2, reason: 'a checked button draws the dot as well');
    });

    test('the circle of the button stands at the start of the control', () {
      final button = RadioButton<String>(value: 'one', text: 'First');
      final window = Window(width: 200, height: 100, content: button)
        ..flowDirection = FlowDirection.rightToLeft;
      window.updateLayout();

      expect(button.markRect.right, button.bounds.right);
      expect(
        button.labelRect.right,
        button.bounds.right -
            CheckableControl.markSize -
            CheckableControl.gapSize,
      );
    });
  });
}
