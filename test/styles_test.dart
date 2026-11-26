import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  test('typed style applies setters through the style layer', () {
    final label = Label()
      ..style = Style<Label>(
        name: 'accent',
        setters: [
          DuiSetter(Label.colorProperty, const Color(0xFF123456)),
          DuiSetter(Label.fontSizeProperty, 20.0),
        ],
      );

    expect(label.style?.name, 'accent');
    expect(label.color.value, 0xFF123456);
    expect(label.fontSize, 20);
    expect(label.getValueSource(Label.colorProperty), DuiValueSource.style);
    expect(label.getValueSource(Label.fontSizeProperty), DuiValueSource.style);
  });

  test('local and binding values mask style setters', () {
    final source = ObservableValue<String>('binding');
    final label = Label(text: 'local')
      ..style = Style<Label>(
        setters: [DuiSetter(Label.textProperty, 'style')],
      );
    expect(label.text, 'local');

    label.clearLocalValue(Label.textProperty);
    expect(label.text, 'style');

    label.bind(Label.textProperty, source.asBinding());
    expect(label.text, 'binding');
  });

  test('replacing and clearing style updates only style-owned properties', () {
    final label = Label()
      ..style = Style<Label>(
        setters: [
          DuiSetter(Label.textProperty, 'first'),
          DuiSetter(Label.fontSizeProperty, 18.0),
        ],
      );

    label.style = Style<Label>(
      setters: [DuiSetter(Label.textProperty, 'second')],
    );
    expect(label.text, 'second');
    expect(label.fontSize, 14);

    label.style = null;
    expect(label.text, '');
    expect(
        label.getValueSource(Label.textProperty), DuiValueSource.defaultValue);
  });

  test('setter rejects an incompatible target type', () {
    final button = Button();

    expect(
      () => button.style = Style<Label>(
        setters: [DuiSetter(Label.textProperty, 'wrong')],
      ),
      throwsA(isA<StateError>()),
    );
  });
}
