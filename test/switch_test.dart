import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('Switch', () {
    test('the switch starts off and a click turns it on', () {
      final switchControl = Switch(animationDuration: Duration.zero);
      final window = Window(width: 200, height: 100, content: switchControl);
      window.updateLayout();

      expect(switchControl.isChecked, isFalse);
      expect(switchControl.progress, 0);

      final position = Point(
        switchControl.bounds.left + Switch.trackWidth / 2,
        switchControl.bounds.top + Switch.trackHeight / 2,
      );
      window.dispatchPointerDown(position);
      window.dispatchPointerUp(position);

      expect(switchControl.isChecked, isTrue);
      expect(switchControl.progress, 1);
    });

    test('a second click turns the switch off', () {
      final switchControl = Switch(
        isChecked: true,
        animationDuration: Duration.zero,
      );
      final window = Window(width: 200, height: 100, content: switchControl);
      window.updateLayout();

      expect(switchControl.progress, 1);

      final position = Point(
        switchControl.bounds.left + Switch.trackWidth / 2,
        switchControl.bounds.top + Switch.trackHeight / 2,
      );
      window.dispatchPointerDown(position);
      window.dispatchPointerUp(position);

      expect(switchControl.isChecked, isFalse);
      expect(switchControl.progress, 0);
    });

    test('a click on the text of the label turns the switch on too', () {
      final switchControl = Switch(
        text: 'Wi-Fi',
        animationDuration: Duration.zero,
      );
      final window = Window(width: 200, height: 100, content: switchControl);
      window.updateLayout();

      final position = Point(
        switchControl.labelRect.left + 2,
        switchControl.bounds.top + switchControl.bounds.height / 2,
      );
      window.dispatchPointerDown(position);
      window.dispatchPointerUp(position);

      expect(switchControl.isChecked, isTrue);
    });

    test('the space bar turns a focused switch on', () {
      final switchControl = Switch(animationDuration: Duration.zero);
      final window = Window(width: 200, height: 100, content: switchControl);
      window.updateLayout();
      switchControl.focus();

      window.dispatchKeyDown('space');

      expect(switchControl.isChecked, isTrue);
    });

    test('the Enter key does not turn the switch on', () {
      final switchControl = Switch(animationDuration: Duration.zero);
      final window = Window(width: 200, height: 100, content: switchControl);
      window.updateLayout();
      switchControl.focus();

      window.dispatchKeyDown('enter');

      expect(switchControl.isChecked, isFalse);
    });

    test('the changed handler is called with the new state', () {
      final states = <bool>[];
      final switchControl = Switch(
        onChanged: states.add,
        animationDuration: Duration.zero,
      );
      final window = Window(width: 200, height: 100, content: switchControl);
      window.updateLayout();

      switchControl.toggle();

      expect(states, [true]);
    });

    test('a two-way binding keeps the model and the control equal', () {
      final model = ObservableValue<bool>(false);
      final switchControl = Switch(animationDuration: Duration.zero)
        ..bind(
          Switch.isCheckedProperty,
          model.asBinding(),
          mode: BindingMode.twoWay,
        );
      final window = Window(width: 200, height: 100, content: switchControl);
      window.updateLayout();

      switchControl.toggle();
      expect(model.value, isTrue);

      model.value = false;
      expect(switchControl.isChecked, isFalse);
    });

    test('a disabled control does not change its state', () {
      final switchControl = Switch(animationDuration: Duration.zero)
        ..isEnabled = false;
      final window = Window(width: 200, height: 100, content: switchControl);
      window.updateLayout();

      final position = Point(
        switchControl.bounds.left + Switch.trackWidth / 2,
        switchControl.bounds.top + Switch.trackHeight / 2,
      );
      window.dispatchPointerDown(position);
      window.dispatchPointerUp(position);

      expect(switchControl.isChecked, isFalse);
    });

    test('the measure of the control holds the track and the text', () {
      final switchControl = Switch(text: 'one', fontSize: 10);

      final size = switchControl.measure(const Size(200, 100));

      // The room of the focus ring, the track and the gap take 49 points, the
      // text of three characters of 6 points takes 18 more.
      expect(
        size.width,
        CheckableControl.focusRingPadding +
            Switch.trackWidth +
            CheckableControl.gapSize +
            18,
      );
      expect(
        size.height,
        greaterThanOrEqualTo(
          Switch.trackHeight + 2 * CheckableControl.focusRingPadding,
        ),
      );
    });

    test(
        'the track stands at the start of the control and the text next to '
        'it', () {
      final switchControl = Switch(text: 'one');
      final window = Window(width: 200, height: 100, content: switchControl);
      window.updateLayout();

      expect(
        switchControl.markRect.left,
        switchControl.bounds.left + CheckableControl.focusRingPadding,
      );
      expect(
        switchControl.labelRect.left,
        switchControl.bounds.left +
            CheckableControl.focusRingPadding +
            Switch.trackWidth +
            CheckableControl.gapSize,
      );
    });

    test('the track stands at the end of the control in a right to left tree',
        () {
      final switchControl = Switch(text: 'one')
        ..flowDirection = FlowDirection.rightToLeft;
      final window = Window(width: 200, height: 100, content: switchControl);
      window.updateLayout();

      expect(
        switchControl.markRect.right,
        switchControl.bounds.right - CheckableControl.focusRingPadding,
      );
      expect(
        switchControl.labelRect.right,
        switchControl.bounds.right -
            CheckableControl.focusRingPadding -
            Switch.trackWidth -
            CheckableControl.gapSize,
      );
    });

    test('the thumb stands at the start of the track when the switch is off',
        () {
      final switchControl = Switch();
      final window = Window(width: 200, height: 100, content: switchControl);
      window.updateLayout();

      expect(
        switchControl.thumbRect.left,
        switchControl.markRect.left + Switch.thumbInset,
      );
    });

    test('the thumb stands at the end of the track when the switch is on', () {
      final switchControl = Switch(isChecked: true);
      final window = Window(width: 200, height: 100, content: switchControl);
      window.updateLayout();

      expect(
        switchControl.thumbRect.right,
        switchControl.markRect.right - Switch.thumbInset,
      );
    });

    test('the thumb of a switch in a right to left tree starts at the end', () {
      final switchControl = Switch()..flowDirection = FlowDirection.rightToLeft;
      final window = Window(width: 200, height: 100, content: switchControl);
      window.updateLayout();

      expect(
        switchControl.thumbRect.right,
        switchControl.markRect.right - Switch.thumbInset,
      );
    });

    test('the thumb slides to the end when the switch is turned on', () async {
      final switchControl = Switch(
        animationDuration: const Duration(milliseconds: 500),
      );
      final window = Window(width: 200, height: 100, content: switchControl);
      window.updateLayout();

      switchControl.toggle();
      expect(switchControl.isAnimating, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(switchControl.progress, greaterThan(0));
      expect(switchControl.progress, lessThan(1));
      expect(switchControl.isAnimating, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(switchControl.progress, 1);
      expect(switchControl.isAnimating, isFalse);
    });

    test('the thumb slides back when the switch is turned off', () async {
      final switchControl = Switch(
        isChecked: true,
        animationDuration: const Duration(milliseconds: 500),
      );
      final window = Window(width: 200, height: 100, content: switchControl);
      window.updateLayout();

      switchControl.toggle();

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(switchControl.progress, lessThan(1));
      expect(switchControl.progress, greaterThan(0));

      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(switchControl.progress, 0);
      expect(switchControl.isAnimating, isFalse);
    });

    test('a switch without a time jumps to the end at once', () {
      final switchControl = Switch(animationDuration: Duration.zero);

      switchControl.toggle();

      expect(switchControl.progress, 1);
      expect(switchControl.isAnimating, isFalse);
    });

    test('the focus ring of the switch stands around the track', () {
      final switchControl = Switch(text: 'one');
      final window = Window(
        width: 200,
        height: 100,
        content: StackPanel(children: [switchControl]),
      );
      window.updateLayout();

      final ring = switchControl.focusRingBounds;
      final track = switchControl.markRect;

      expect(switchControl.defaultFocusRingShape, FocusRingShape.capsule);
      expect(ring.left, lessThan(track.left));
      expect(ring.right, greaterThan(track.right));
      expect(ring.top, switchControl.bounds.top);
      expect(ring.bottom, switchControl.bounds.bottom);
      expect(
        ring.right,
        lessThan(switchControl.labelRect.left),
        reason: 'the ring does not reach the text of the label',
      );
    });

    test('the control draws the track and the thumb', () async {
      final switchControl = Switch();
      final window = Window(width: 200, height: 100, content: switchControl);
      await window.show();
      final renderer = RecordingDrawingContext();

      window.renderFrame(renderer);

      final tracks = renderer.commands.whereType<DrawRoundedRectCommand>();
      final thumbs = renderer.commands.whereType<DrawPathCommand>();
      expect(tracks, hasLength(2), reason: 'the track and its border');
      expect(thumbs, hasLength(1), reason: 'the thumb');
    });

    test('the control draws the text of the label', () async {
      final switchControl = Switch(text: 'Wi-Fi');
      final window = Window(width: 200, height: 100, content: switchControl);
      await window.show();
      final renderer = RecordingDrawingContext();

      window.renderFrame(renderer);

      final texts = renderer.commands.whereType<DrawTextCommand>().toList();
      expect(texts, hasLength(1));
      expect(texts.first.text, 'Wi-Fi');
      expect(
        texts.first.position.x,
        greaterThanOrEqualTo(
          switchControl.bounds.left +
              Switch.trackWidth +
              CheckableControl.gapSize,
        ),
      );
    });

    test('a disabled control draws the thumb in gray', () async {
      final switchControl = Switch(text: 'one', isChecked: true)
        ..isEnabled = false;
      final window = Window(width: 200, height: 100, content: switchControl);
      await window.show();
      final renderer = RecordingDrawingContext();

      window.renderFrame(renderer);

      final thumb = renderer.commands.whereType<DrawPathCommand>().single;
      expect(thumb.paint.color.value, Switch.disabledThumbColor.value);
    });

    test('the semantics of the control carry the state and the name', () {
      final switchControl = Switch(text: 'Wi-Fi');

      final tree = SemanticsTree.fromElement(switchControl);
      final node = tree.nodeFor(switchControl)!;

      expect(node.role, SemanticsRole.toggleSwitch);
      expect(node.name, 'Wi-Fi');
      expect(node.state.checked, isFalse);

      switchControl.isChecked = true;
      final checked =
          SemanticsTree.fromElement(switchControl).nodeFor(switchControl)!;
      expect(checked.state.checked, isTrue);
    });

    test('the control keeps the focus when it is pressed', () {
      final switchControl = Switch(animationDuration: Duration.zero);
      final window = Window(width: 200, height: 100, content: switchControl);
      window.updateLayout();

      window.dispatchPointerDown(Point(10, 10));

      expect(switchControl.isFocused, isTrue);
      expect(switchControl.state.pressed, isTrue);
    });
  });
}
