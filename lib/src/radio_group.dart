import 'content_control.dart';
import 'geometry.dart';
import 'properties.dart';
import 'radio_button.dart';
import 'semantics.dart';
import 'ui_element.dart';

/// A group of radio buttons.
///
/// The group owns the selection: only one button of the group is checked at
/// a time. The group is a focus scope, so the keyboard stays inside it, and
/// the arrows walk over the buttons of the group and move the focus with the
/// selection.
///
/// The value of the checked button lives in the group, so the group can carry
/// it in a property and bind it to a model:
///
/// ```dart
/// RadioGroup<String>(
///   selectedValue: 'auto',
///   content: StackPanel(
///     children: [
///       RadioButton<String>(value: 'auto', text: 'Automatic'),
///       RadioButton<String>(value: 'manual', text: 'Manual'),
///     ],
///   ),
/// );
/// ```
final class RadioGroup<T> extends ContentControl {
  RadioGroup({
    super.content,
    T? selectedValue,
    Orientation orientation = Orientation.vertical,
    void Function(T? value)? onChanged,
  }) : _orientation = orientation {
    if (onChanged != null) addChangedHandler(onChanged);
    setValue(selectedValueProperty, selectedValue);
  }

  /// The value of the checked button of the group.
  static const selectedValueProperty =
      DuiProperty<RadioGroup<dynamic>, dynamic>(
    name: 'selectedValue',
    defaultValue: null,
    affectsPaint: true,
  );

  /// The direction the buttons of the group stand in.
  ///
  /// The direction decides the keys that walk over the buttons: the vertical
  /// arrows in a vertical group and the horizontal arrows in a horizontal one.
  Orientation _orientation;

  final _changedHandlers = <void Function(T? value)>[];
  bool _isApplyingSelection = false;

  /// The direction the buttons of the group stand in.
  Orientation get orientation => _orientation;
  set orientation(Orientation value) {
    if (_orientation == value) return;
    _orientation = value;
  }

  /// The value of the checked button of the group.
  T? get selectedValue => getValue<dynamic>(selectedValueProperty) as T?;
  set selectedValue(T? value) =>
      setValue<dynamic>(selectedValueProperty, value);

  /// Adds a handler that is called when the selection of the group changes.
  void addChangedHandler(void Function(T? value) handler) =>
      _changedHandlers.add(handler);

  /// Removes a handler that is called when the selection changes.
  void removeChangedHandler(void Function(T? value) handler) =>
      _changedHandlers.remove(handler);

  /// The buttons of the group, in the order of the tree.
  ///
  /// The buttons of a nested group belong to that group, so they are not part
  /// of this group.
  List<RadioButton<T>> get radioButtons {
    final result = <RadioButton<T>>[];
    void visit(UIElement element) {
      if (element is RadioButton<T>) {
        result.add(element);
        return;
      }
      if (element is RadioGroup<T>) return;
      for (final child in element.logicalChildren) {
        visit(child);
      }
    }

    for (final child in logicalChildren) {
      visit(child);
    }
    return result;
  }

  /// Checks the button of the group that holds the value.
  ///
  /// The method reports whether the selection changed.
  bool selectValue(T? value) {
    if (_isApplyingSelection) return false;
    if (selectedValue == value) {
      // The value is already selected, but the buttons of the group may be
      // out of sync with it.
      _applySelection();
      return false;
    }
    selectedValue = value;
    return true;
  }

  /// Drops the selection of the button that holds the value.
  void clearValue(T? value) {
    if (_isApplyingSelection) return;
    if (selectedValue != value) return;
    selectedValue = null;
  }

  /// Moves the selection to the next or the previous button of the group.
  ///
  /// The focus follows the selection, and the method reports whether the
  /// selection moved.
  bool moveSelection(int delta) {
    final buttons = radioButtons;
    if (buttons.isEmpty) return false;
    var index = buttons.indexWhere((button) => button.isChecked);
    if (index < 0) {
      index = delta > 0 ? 0 : buttons.length - 1;
    } else {
      index = (index + delta) % buttons.length;
      if (index < 0) index += buttons.length;
    }
    final button = buttons[index];
    final changed = button.select();
    button.focus();
    return changed;
  }

  /// The step the selection makes for a key.
  ///
  /// The method answers null when the key does not walk over the buttons.
  int? selectionStepFor(String key) {
    final vertical = _orientation == Orientation.vertical;
    return switch (key) {
      'up' => vertical ? -1 : null,
      'down' => vertical ? 1 : null,
      'left' => vertical
          ? null
          : isRightToLeft
              ? 1
              : -1,
      'right' => vertical
          ? null
          : isRightToLeft
              ? -1
              : 1,
      _ => null,
    };
  }

  @override
  bool get isFocusScope => true;

  @override
  SemanticsRole get semanticsRole => SemanticsRole.group;

  @override
  void onDuiPropertyChanged<V>(
    DuiProperty<dynamic, V> property,
    V oldValue,
    V newValue,
  ) {
    super.onDuiPropertyChanged(property, oldValue, newValue);
    if (!identical(property, selectedValueProperty)) return;
    _applySelection();
    final value = newValue as Object?;
    for (final handler in List<void Function(T? value)>.of(_changedHandlers)) {
      handler(value as T?);
    }
  }

  @override
  Size measureContentCore(Size availableSize) {
    // The buttons of the group follow the selection of the group, and the
    // buttons can appear after the group was made.
    _applySelection();
    return super.measureContentCore(availableSize);
  }

  /// Checks the button of the group that holds the value of the selection.
  void _applySelection() {
    if (_isApplyingSelection) return;
    _isApplyingSelection = true;
    try {
      final value = selectedValue;
      for (final button in radioButtons) {
        final shouldCheck = value != null && button.value == value;
        if (button.isChecked != shouldCheck) {
          button.isChecked = shouldCheck;
        }
      }
    } finally {
      _isApplyingSelection = false;
    }
  }
}
