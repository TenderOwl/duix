import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  test('data context is inherited recursively and updates notify descendants',
      () {
    final leaf = Label();
    final branch = StackPanel(children: [leaf]);
    final root = StackPanel(children: [branch]);
    final first = _ViewModel('first');
    final second = _ViewModel('second');
    final changes = <String>[];
    leaf.addPropertyListener((event) {
      if (identical(event.property, UIElement.dataContextProperty)) {
        changes.add('${(event.oldValue as _ViewModel?)?.name}->'
            '${(event.newValue as _ViewModel?)?.name}');
      }
    });

    root.dataContext = first;

    expect(leaf.dataContext, same(first));
    expect(leaf.effectiveDataContext, same(first));
    expect(
      leaf.getValueSource(UIElement.dataContextProperty),
      DuiValueSource.inherited,
    );

    root.dataContext = second;
    expect(leaf.dataContext, same(second));
    expect(changes, ['null->first', 'first->second']);
  });

  test('local context masks inherited updates until cleared', () {
    final child = Label();
    final root = StackPanel(children: [child])..dataContext = 'parent';
    child.dataContext = 'local';

    root.dataContext = 'new parent';
    expect(child.dataContext, 'local');
    expect(
      child.getValueSource(UIElement.dataContextProperty),
      DuiValueSource.local,
    );

    child.clearLocalValue(UIElement.dataContextProperty);
    expect(child.dataContext, 'new parent');
    expect(
      child.getValueSource(UIElement.dataContextProperty),
      DuiValueSource.inherited,
    );

    child.dataContext = null;
    expect(child.dataContext, 'new parent');
  });

  test('bound parent context propagates through a local mask', () {
    final source = ObservableValue<Object?>('first');
    final child = Label();
    final root = StackPanel(children: [child]);
    root.bind(UIElement.dataContextProperty, source.asBinding());
    child.dataContext = 'local';

    source.value = 'second';
    expect(root.dataContext, 'second');
    expect(child.dataContext, 'local');

    child.clearLocalValue(UIElement.dataContextProperty);
    expect(child.dataContext, 'second');
  });

  test('detaching and reparenting update the inherited context', () {
    final child = Label();
    final first = StackPanel(children: [child])..dataContext = 'first';
    final second = StackPanel()..dataContext = 'second';

    expect(child.dataContext, 'first');
    first.children.remove(child);
    expect(child.dataContext, isNull);
    expect(
      child.getValueSource(UIElement.dataContextProperty),
      DuiValueSource.defaultValue,
    );

    second.children.add(child);
    expect(child.dataContext, 'second');
  });

  test('typed accessors return matches and reject missing or wrong types', () {
    final element = Label()..dataContext = _ViewModel('model');

    expect(element.dataContextAs<_ViewModel>()?.name, 'model');
    expect(element.dataContextAs<String>(), isNull);
    expect(element.requireDataContext<_ViewModel>().name, 'model');
    expect(
      () => element.requireDataContext<String>(),
      throwsA(isA<StateError>()),
    );

    element.clearLocalValue(UIElement.dataContextProperty);
    expect(element.dataContextAs<_ViewModel>(), isNull);
    expect(
      () => element.requireDataContext<_ViewModel>(),
      throwsA(isA<StateError>()),
    );
  });

  test('item context overrides the items control and flows to item children',
      () {
    final child = Label();
    final itemRoot = StackPanel(children: [child]);
    final control = ItemsControl<String>(
      itemsSource: ['item'],
      itemTemplate: (_) => itemRoot,
    )..dataContext = 'ancestor';

    expect(itemRoot.dataContext, 'item');
    expect(child.dataContext, 'item');
    expect(control.dataContext, 'ancestor');
  });
}

final class _ViewModel {
  const _ViewModel(this.name);

  final String name;
}
