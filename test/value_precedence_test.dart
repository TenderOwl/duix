import 'package:duix/dui.dart';
import 'package:test/test.dart';

const _property = DuiProperty<_Owner, String>(
  name: 'value',
  defaultValue: 'default',
);
const _nullableProperty = DuiProperty<_Owner, String?>(
  name: 'nullable',
  defaultValue: null,
);

void main() {
  test('default, inherited and style values resolve in priority order', () {
    final owner = _Owner();
    expect(owner.getValue(_property), 'default');
    expect(owner.getValueSource(_property), DuiValueSource.defaultValue);

    owner.setInheritedValue(_property, 'inherited');
    expect(owner.getValue(_property), 'inherited');
    expect(owner.getValueSource(_property), DuiValueSource.inherited);

    owner.setStyleValue(_property, 'style');
    expect(owner.getValue(_property), 'style');
    expect(owner.getValueSource(_property), DuiValueSource.style);

    owner.clearStyleValue(_property);
    expect(owner.getValue(_property), 'inherited');
    owner.clearInheritedValue(_property);
    expect(owner.getValue(_property), 'default');
  });

  test('binding, local and animation override lower layers', () {
    final owner = _Owner();
    final source = ObservableValue<String>('binding');
    owner.setInheritedValue(_property, 'inherited');
    owner.setStyleValue(_property, 'style');
    owner.bind(_property, source.asBinding());
    expect(owner.getValue(_property), 'binding');
    expect(owner.getValueSource(_property), DuiValueSource.binding);

    owner.setValue(_property, 'local');
    expect(owner.getValue(_property), 'local');
    expect(owner.getValueSource(_property), DuiValueSource.local);

    owner.setAnimationValue(_property, 'animation');
    expect(owner.getValue(_property), 'animation');
    expect(owner.getValueSource(_property), DuiValueSource.animation);

    owner.clearAnimationValue(_property);
    expect(owner.getValue(_property), 'local');
    owner.clearLocalValue(_property);
    expect(owner.getValue(_property), 'binding');
    expect(owner.getValueSource(_property), DuiValueSource.binding);
  });

  test('local masks one-way binding without cancelling it', () {
    final owner = _Owner();
    final source = ObservableValue<String>('first');
    final subscription = owner.bind(_property, source.asBinding());
    final changes = <String>[];
    owner.addPropertyListener((event) {
      changes.add('${event.oldValue}->${event.newValue}');
    });

    owner.setValue(_property, 'local');
    source.value = 'second';
    expect(owner.getValue(_property), 'local');
    expect(subscription.isCancelled, isFalse);
    expect(changes, ['first->local']);

    owner.clearLocalValue(_property);
    expect(owner.getValue(_property), 'second');
    expect(changes, ['first->local', 'local->second']);
  });

  test('masked animation updates notify only when effective value changes', () {
    final owner = _Owner();
    final source = ObservableValue<String>('binding');
    owner.bind(_property, source.asBinding());
    owner.setAnimationValue(_property, 'animation');
    var notifications = 0;
    owner.addPropertyListener((event) => notifications++);

    source.value = 'new binding';
    owner.setValue(_property, 'local');
    owner.setStyleValue(_property, 'style');
    expect(notifications, 0);

    owner.clearAnimationValue(_property);
    expect(owner.getValue(_property), 'local');
    expect(notifications, 1);
  });

  test('attaching a binding replaces but does not snapshot old local', () {
    final owner = _Owner();
    final first = ObservableValue<String>('first');
    final second = ObservableValue<String>('second');
    owner.bind(_property, first.asBinding());
    owner.setValue(_property, 'local');
    final changes = <String>[];
    owner.addPropertyListener((event) {
      changes.add('${event.oldValue}->${event.newValue}');
    });

    owner.bind(_property, second.asBinding());

    expect(owner.getValue(_property), 'second');
    expect(owner.getValueSource(_property), DuiValueSource.binding);
    expect(changes, ['local->second']);
  });

  test('cancel preserves binding only when no explicit local masks it', () {
    final owner = _Owner();
    final source = ObservableValue<String>('binding');
    final subscription = owner.bind(_property, source.asBinding());
    owner.setValue(_property, 'local');

    subscription.cancel();
    expect(owner.getValue(_property), 'local');
    expect(owner.getValueSource(_property), DuiValueSource.local);

    owner.clearLocalValue(_property);
    expect(owner.getValue(_property), 'default');
  });

  test('nullable local and animation values use presence, not null fallback',
      () {
    final owner = _Owner();
    final source = ObservableValue<String?>('binding');
    owner.bind(_nullableProperty, source.asBinding());

    owner.setValue(_nullableProperty, null);
    expect(owner.getValue(_nullableProperty), isNull);
    expect(owner.getValueSource(_nullableProperty), DuiValueSource.local);

    owner.clearLocalValue(_nullableProperty);
    owner.setAnimationValue(_nullableProperty, null);
    expect(owner.getValue(_nullableProperty), isNull);
    expect(owner.getValueSource(_nullableProperty), DuiValueSource.animation);
  });

  test('two-way local setter writes through an animation mask', () {
    final source = ObservableValue<String>('initial');
    final text = Label()
      ..bind(
        Label.textProperty,
        source.asBinding(),
        mode: BindingMode.twoWay,
      );
    text.setAnimationValue(Label.textProperty, 'animation');

    text.text = 'written';
    expect(source.value, 'written');
    expect(text.text, 'animation');

    text.clearAnimationValue(Label.textProperty);
    expect(text.text, 'written');
  });

  test('constructor defaults do not become explicit local values', () {
    final text = Label();
    expect(
        text.getValueSource(Label.textProperty), DuiValueSource.defaultValue);

    text.setStyleValue(Label.textProperty, 'styled');
    expect(text.text, 'styled');
    expect(text.getValueSource(Label.textProperty), DuiValueSource.style);
  });
}

final class _Owner extends PropertyOwner {}
