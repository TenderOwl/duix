import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('selection model', () {
    test('a single selection keeps one item', () {
      final model = SelectionModel(count: 5);

      expect(model.isEmpty, isTrue);
      expect(model.selectedIndex, -1);

      model.select(2);

      expect(model.selectedIndex, 2);
      expect(model.selectedIndexes, [2]);
      expect(model.selectedCount, 1);
      expect(model.isSelected(2), isTrue);
      expect(model.isSelected(1), isFalse);

      model.select(4);

      expect(model.selectedIndexes, [4]);
      expect(model.selectedIndex, 4);
    });

    test('a multiple selection keeps every item', () {
      final model = SelectionModel(mode: SelectionMode.multiple, count: 5);

      model.select(1);
      model.toggle(3);

      expect(model.selectedIndexes, [1, 3]);
      expect(model.selectedIndex, 3);

      model.toggle(1);

      expect(model.selectedIndexes, [3]);
    });

    test('the selection is reported to the listeners', () {
      final model = SelectionModel(mode: SelectionMode.multiple, count: 5);
      final changes = <String>[];
      model.addSelectionChangedListener((model, added, removed) {
        changes.add('+${added.join(',')}-${removed.join(',')}');
      });

      model.select(0);
      model.toggle(2);
      model.toggle(2);
      model.extendTo(4);

      expect(changes, ['+0-', '+2-', '+-2', '+2,3,4-']);
    });

    test('a range grows from the anchor', () {
      final model = SelectionModel(mode: SelectionMode.multiple, count: 8);

      model.select(3);
      model.extendTo(5);

      expect(model.selectedIndexes, [3, 4, 5]);
      expect(model.anchorIndex, 3);
      expect(model.selectedIndex, 5);

      model.extendTo(1);

      expect(model.selectedIndexes, [1, 2, 3, 4, 5]);
    });

    test('the keyboard moves the current item', () {
      final model = SelectionModel(count: 5);

      expect(model.moveSelection(1), isTrue);
      expect(model.selectedIndex, 0);

      expect(model.moveSelection(1), isTrue);
      expect(model.selectedIndex, 1);

      expect(model.moveSelection(-1), isTrue);
      expect(model.selectedIndex, 0);

      expect(model.moveSelection(-1), isFalse);
      expect(model.selectedIndex, 0);

      expect(model.selectLast(), isTrue);
      expect(model.selectedIndex, 4);
      expect(model.moveSelection(1), isFalse);

      expect(model.selectFirst(), isTrue);
      expect(model.selectedIndex, 0);
    });

    test('an extended move keeps the range', () {
      final model = SelectionModel(mode: SelectionMode.multiple, count: 8);

      model.select(2);
      model.moveSelection(2, extend: true);

      expect(model.selectedIndexes, [2, 3, 4]);
      expect(model.selectedIndex, 4);
    });

    test('the selection is trimmed when the items disappear', () {
      final model = SelectionModel(mode: SelectionMode.multiple, count: 5);
      model.select(1);
      model.select(4);

      model.count = 3;

      expect(model.selectedIndexes, [1]);
      expect(model.selectedIndex, 1);
      expect(model.count, 3);
    });

    test('the whole list can be selected and cleared', () {
      final model = SelectionModel(mode: SelectionMode.multiple, count: 3);

      model.selectAll();
      expect(model.selectedIndexes, [0, 1, 2]);

      model.clear();
      expect(model.isEmpty, isTrue);
      expect(model.selectedIndex, -1);
      expect(model.anchorIndex, isNull);
    });

    test('an index outside of the list is rejected', () {
      final model = SelectionModel(count: 2);

      expect(() => model.select(2), throwsRangeError);
      expect(() => model.select(-1), throwsRangeError);
      expect(() => model.toggle(5), throwsRangeError);
    });
  });
}
