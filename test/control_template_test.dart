import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  test('template keeps content and visual identity across property changes',
      () {
    final original = Label(text: 'Original');
    final button = Button(content: original);
    var factoryCalls = 0;
    late Border root;
    late ContentPresenter presenter;

    button.template = ControlTemplate<Button>((control) {
      factoryCalls++;
      presenter = ContentPresenter(control);
      root = Border(
        color: const Color(0xFF102030),
        padding: const EdgeInsets.all(4),
        content: presenter,
      );
      return root;
    });

    expect(factoryCalls, 1);
    expect(button.templateRoot, same(root));
    expect(root.logicalParent, same(button));
    expect(presenter.content, same(original));
    expect(original.logicalParent, same(presenter));

    original.text = 'Updated';
    expect(button.templateRoot, same(root));
    expect(presenter.content, same(original));
    expect(factoryCalls, 1);

    final replacement = Label(text: 'Replacement');
    button.content = replacement;
    expect(presenter.content, same(replacement));
    expect(replacement.logicalParent, same(presenter));
    expect(original.logicalParent, isNull);
    expect(factoryCalls, 1);

    button.template = null;
    expect(button.templateRoot, isNull);
    expect(button.content, same(replacement));
    expect(replacement.logicalParent, same(button));
    expect(root.isDisposed, isTrue);
  });

  test('typed template binding reacts without recreating the subtree', () {
    var clicks = 0;
    final button = Button(onClick: () => clicks++);
    late StackPanel root;
    late Label state;

    button.template = ControlTemplate<Button>((control) {
      state = Label()
        ..bind(
          Label.textProperty,
          control.propertyBinding(Button.isPressedProperty).map(
                (pressed) => pressed ? 'Pressed' : 'Idle',
              ),
        );
      root = StackPanel(children: [state, ContentPresenter(control)]);
      return root;
    });

    expect(state.text, 'Idle');
    button.raiseEvent(
      UIElement.pointerDown,
      PointerEventArgs(pointerId: 1, position: const Point(1, 1)),
    );
    expect(state.text, 'Pressed');
    expect(button.templateRoot, same(root));

    button.raiseEvent(
      UIElement.pointerUp,
      PointerEventArgs(pointerId: 1, position: const Point(1, 1)),
    );
    expect(state.text, 'Idle');
    expect(clicks, 1);
    expect(state.logicalParent, same(root));
  });

  test('template changes button visuals but preserves focus decoration',
      () async {
    final button = Button(content: Label(text: 'Action'));
    late Border root;
    button.template = ControlTemplate<Button>((control) {
      root = Border(
        color: const Color(0xFF654321),
        content: ContentPresenter(control),
      );
      return root;
    });
    final window = Window(width: 120, height: 50, content: button);
    await window.show();
    button.focus();

    final renderer = RecordingDrawingContext();
    window.renderFrame(renderer);

    final rectangles = renderer.commands.whereType<DrawRectCommand>().toList();
    expect(
      rectangles.any((command) => command.paint.color.value == 0xFF654321),
      isTrue,
    );
    expect(
      rectangles.any((command) => command.paint.color.value == 0xFFE0E0E0),
      isFalse,
    );
    expect(
      rectangles.where((command) => command.paint.color.value == 0xFF356AC3),
      hasLength(4),
    );
    expect(button.templateRoot, same(root));
  });
}
