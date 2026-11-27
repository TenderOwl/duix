import 'dart:math' as math;

/// How many items a selection model keeps selected.
enum SelectionMode { single, multiple }

/// Called when the selection of a model changes.
typedef SelectionChangedListener = void Function(
  SelectionModel model,
  List<int> added,
  List<int> removed,
);

/// The selection of a list of items.
///
/// The model owns the selected indexes, the current item and the anchor of a
/// range selection. A control uses it to show the selection and to move it
/// with the keyboard: [moveSelection] walks through the items and keeps the
/// current item in sync, so the control can move the focus to it.
final class SelectionModel {
  SelectionModel({this.mode = SelectionMode.single, int count = 0})
      : _count = count < 0 ? 0 : count;

  /// How many items the model keeps selected at once.
  final SelectionMode mode;

  int _count;
  final Set<int> _selected = <int>{};
  int _currentIndex = -1;
  int? _anchorIndex;
  final _listeners = <SelectionChangedListener>[];

  /// The number of items the model works with.
  ///
  /// The selection is trimmed when the items disappear.
  int get count => _count;
  set count(int value) {
    if (value < 0) {
      throw ArgumentError.value(value, 'count', 'Must be non-negative.');
    }
    if (_count == value) return;
    final removed = _selected.where((index) => index >= value).toList();
    _count = value;
    for (final index in removed) {
      _selected.remove(index);
    }
    if (_currentIndex >= value) {
      // The current item is gone, so the selection falls back to the last
      // item that is still there.
      _currentIndex =
          _selected.isEmpty ? -1 : _selected.reduce((a, b) => a > b ? a : b);
    }
    if (_anchorIndex != null && _anchorIndex! >= value) _anchorIndex = null;
    if (removed.isNotEmpty) _notify(removed: removed);
  }

  /// The index of the current item, -1 when nothing is selected.
  int get selectedIndex => _currentIndex;

  /// The index the range selection grows from.
  int? get anchorIndex => _anchorIndex;

  /// The selected indexes in ascending order.
  List<int> get selectedIndexes {
    final indexes = _selected.toList()..sort();
    return List<int>.unmodifiable(indexes);
  }

  /// The number of the selected items.
  int get selectedCount => _selected.length;

  /// Whether nothing is selected.
  bool get isEmpty => _selected.isEmpty;

  /// Whether the item at [index] is selected.
  bool isSelected(int index) => _selected.contains(index);

  void addSelectionChangedListener(SelectionChangedListener listener) {
    _listeners.add(listener);
  }

  void removeSelectionChangedListener(SelectionChangedListener listener) {
    _listeners.remove(listener);
  }

  /// Selects one item and drops the other selection.
  void select(int index) {
    _checkIndex(index);
    if (mode == SelectionMode.single) {
      final wasSelected = _selected.length == 1 && _selected.contains(index);
      final removed = _selected.where((item) => item != index).toList();
      _selected
        ..clear()
        ..add(index);
      _currentIndex = index;
      _anchorIndex = index;
      if (!wasSelected) _notify(added: [index], removed: removed);
      return;
    }
    final added = <int>[];
    if (_selected.add(index)) added.add(index);
    _currentIndex = index;
    _anchorIndex = index;
    if (added.isNotEmpty) _notify(added: added);
  }

  /// Adds the item to the selection or removes it from there.
  void toggle(int index) {
    _checkIndex(index);
    if (mode == SelectionMode.single) {
      if (isSelected(index)) {
        clear();
      } else {
        select(index);
      }
      return;
    }
    if (_selected.remove(index)) {
      if (_currentIndex == index) _currentIndex = -1;
      _notify(removed: [index]);
      return;
    }
    _selected.add(index);
    _currentIndex = index;
    _anchorIndex = index;
    _notify(added: [index]);
  }

  /// Selects every item between the anchor and [index].
  void extendTo(int index) {
    _checkIndex(index);
    final anchor = _anchorIndex ?? _currentIndex;
    if (anchor < 0 || mode == SelectionMode.single) {
      select(index);
      return;
    }
    final start = math.min(anchor, index);
    final end = math.max(anchor, index);
    final added = <int>[];
    for (var item = start; item <= end; item++) {
      if (_selected.add(item)) added.add(item);
    }
    _currentIndex = index;
    if (added.isNotEmpty) _notify(added: added);
  }

  /// Selects every item of the list.
  void selectAll() {
    if (mode == SelectionMode.single) {
      if (_count == 0) return;
      select(_currentIndex >= 0 ? _currentIndex : 0);
      return;
    }
    final added = <int>[];
    for (var index = 0; index < _count; index++) {
      if (_selected.add(index)) added.add(index);
    }
    if (added.isNotEmpty) _notify(added: added);
  }

  /// Drops the selection.
  void clear() {
    if (_selected.isEmpty) {
      _currentIndex = -1;
      _anchorIndex = null;
      return;
    }
    final removed = _selected.toList();
    _selected.clear();
    _currentIndex = -1;
    _anchorIndex = null;
    _notify(removed: removed);
  }

  /// Moves the current item by [delta] items and selects it.
  ///
  /// With [extend] the range from the anchor grows instead of the selection
  /// being replaced. The method reports whether the current item moved.
  bool moveSelection(int delta, {bool extend = false}) {
    if (_count == 0) return false;
    final current = _currentIndex;
    final int next;
    if (current < 0) {
      next = delta > 0 ? 0 : _count - 1;
    } else {
      next = (current + delta).clamp(0, _count - 1).toInt();
    }
    if (next == current) return false;
    if (extend) {
      extendTo(next);
    } else {
      select(next);
    }
    return true;
  }

  /// Selects the first item.
  bool selectFirst() {
    if (_count == 0) return false;
    if (_currentIndex == 0) return false;
    select(0);
    return true;
  }

  /// Selects the last item.
  bool selectLast() {
    if (_count == 0) return false;
    if (_currentIndex == _count - 1) return false;
    select(_count - 1);
    return true;
  }

  void _checkIndex(int index) {
    if (index < 0 || index >= _count) {
      throw RangeError.index(index, this, 'index', null, _count);
    }
  }

  void _notify({List<int> added = const [], List<int> removed = const []}) {
    if (added.isEmpty && removed.isEmpty) return;
    for (final listener in List<SelectionChangedListener>.of(_listeners)) {
      listener(this, added, removed);
    }
  }
}
