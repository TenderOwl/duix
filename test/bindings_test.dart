import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('bindings', () {
    test('one-way binding updates the existing control', () {
      final source = ObservableValue<String>('first');
      final text = Label();
      final identity = text;

      text.bind(Label.textProperty, source.asBinding());
      source.value = 'second';

      expect(text.text, 'second');
      expect(identical(text, identity), isTrue);
    });

    test('property changes contain correct previous values', () {
      final source = ObservableValue<String>('a');
      final text = Label()..bind(Label.textProperty, source.asBinding());
      final changes = <String>[];
      text.addPropertyListener((event) {
        changes.add('${event.oldValue}->${event.newValue}');
      });

      source.value = 'b';
      source.value = 'c';

      expect(changes, ['a->b', 'b->c']);
    });

    test('two-way binding writes back to its source', () {
      final source = ObservableValue<String>('initial');
      final box = TextBox()
        ..bind(
          TextBox.textProperty,
          source.asBinding(),
          mode: BindingMode.twoWay,
        );

      box.text = 'from control';
      expect(source.value, 'from control');

      source.value = 'from model';
      expect(box.text, 'from model');
    });

    test('cancelling a subscription stops updates', () {
      final source = ObservableValue<String>('a');
      final text = Label();
      final subscription = text.bind(Label.textProperty, source.asBinding());

      subscription.cancel();
      text.text = 'local';
      source.value = 'b';

      expect(text.text, 'local');
    });
  });
}
