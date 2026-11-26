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

    test('cancel preserves the latest value and exposes diagnostics', () {
      final source = ObservableValue<String>('a');
      final text = Label();
      final subscription = text.bind(Label.textProperty, source.asBinding());
      source.value = 'b';

      subscription.cancel();
      subscription.cancel();
      source.value = 'c';

      expect(text.text, 'b');
      expect(subscription.property, same(Label.textProperty));
      expect(subscription.mode, BindingMode.oneWay);
      expect(subscription.isCancelled, isTrue);
      expect(subscription.toString(), contains('property: text'));
      expect(subscription.toString(), contains('cancelled: true'));
    });

    test('replacing a binding cancels only the previous subscription', () {
      final first = ObservableValue<String>('first');
      final second = ObservableValue<String>('second');
      final text = Label();
      final firstSubscription =
          text.bind(Label.textProperty, first.asBinding());
      final secondSubscription =
          text.bind(Label.textProperty, second.asBinding());

      first.value = 'ignored';
      second.value = 'updated';

      expect(firstSubscription.isCancelled, isTrue);
      expect(secondSubscription.isCancelled, isFalse);
      expect(text.text, 'updated');
    });

    test('two-way source and control changes notify exactly once', () {
      final source = ObservableValue<String>('initial');
      final box = TextBox()
        ..bind(
          TextBox.textProperty,
          source.asBinding(),
          mode: BindingMode.twoWay,
        );
      final changes = <String>[];
      box.addPropertyListener((event) {
        if (event.property == TextBox.textProperty) {
          changes.add('${event.oldValue}->${event.newValue}');
        }
      });

      box.text = 'from control';
      source.value = 'from control';
      source.value = 'from model';

      expect(changes, ['initial->from control', 'from control->from model']);
    });

    test('two-way write synchronizes when callback does not notify', () {
      var model = 'initial';
      final binding = CallbackBinding<String>(
        read: () => model,
        write: (value) => model = value,
      );
      final box = TextBox()
        ..bind(
          TextBox.textProperty,
          binding,
          mode: BindingMode.twoWay,
        );
      var notifications = 0;
      box.addPropertyListener((event) {
        if (event.property == TextBox.textProperty) notifications++;
      });

      box.text = 'updated';

      expect(model, 'updated');
      expect(box.text, 'updated');
      expect(notifications, 1);
    });

    test('reentrant callback notification does not duplicate changes', () {
      var model = 'initial';
      late final CallbackBinding<String> binding;
      binding = CallbackBinding<String>(
        read: () => model,
        write: (value) {
          model = value;
          binding.notifyChanged();
          return value;
        },
      );
      final box = TextBox()
        ..bind(
          TextBox.textProperty,
          binding,
          mode: BindingMode.twoWay,
        );
      var notifications = 0;
      box.addPropertyListener((event) {
        if (event.property == TextBox.textProperty) notifications++;
      });

      box.text = 'updated';

      expect(notifications, 1);
      expect(box.text, 'updated');
    });

    test('dispose cancels bindings and prohibits further mutation', () {
      final source = ObservableValue<String>('a');
      final text = Label();
      final subscription = text.bind(Label.textProperty, source.asBinding());

      text.dispose();
      text.dispose();
      source.value = 'b';

      expect(text.isDisposed, isTrue);
      expect(subscription.isCancelled, isTrue);
      expect(text.text, 'a');
      expect(() => text.text = 'local', throwsStateError);
      expect(
        () => text.bind(Label.textProperty, source.asBinding()),
        throwsStateError,
      );
    });

    test('failed initial read preserves the existing binding', () {
      final source = ObservableValue<String>('stable');
      final text = Label()..bind(Label.textProperty, source.asBinding());
      final broken = CallbackBinding<String>(
        read: () => throw StateError('unavailable'),
      );

      expect(
        () => text.bind(Label.textProperty, broken),
        throwsA(
          isA<BindingException>()
              .having((error) => error.property, 'property',
                  same(Label.textProperty))
              .having((error) => error.operation, 'operation', 'Initial read')
              .having((error) => error.toString(), 'message',
                  contains('unavailable')),
        ),
      );
      source.value = 'still active';
      expect(text.text, 'still active');
    });

    test('write failures identify property, operation and cause', () {
      final binding = CallbackBinding<String>(
        read: () => 'initial',
        write: (value) => throw StateError('denied'),
      );
      final box = TextBox()
        ..bind(
          TextBox.textProperty,
          binding,
          mode: BindingMode.twoWay,
        );

      expect(
        () => box.text = 'forbidden',
        throwsA(
          isA<BindingException>()
              .having((error) => error.operation, 'operation', 'Write')
              .having((error) => error.toString(), 'message',
                  allOf(contains('text'), contains('denied'))),
        ),
      );
    });

    test('two-way binding rejects a read-only source before attachment', () {
      final text = Label();
      final binding = CallbackBinding<String>(read: () => 'value');

      expect(
        () => text.bind(
          Label.textProperty,
          binding,
          mode: BindingMode.twoWay,
        ),
        throwsArgumentError,
      );
      expect(text.text, isEmpty);
    });
  });
}
