import 'ui_element.dart';

/// Owns keyboard focus for controls mounted to a single [WindowHost].
final class FocusManager {
  FocusManager(this._host);

  final WindowHost _host;
  Control? _focused;

  Control? get focusedElement => _focused;

  bool requestFocus(Control control) {
    validate();
    if (!_canFocus(control)) return false;
    if (identical(_focused, control)) return true;

    final previous = _focused;
    _focused = control;
    previous?.updateFocus(false);
    if (identical(_focused, control)) control.updateFocus(true);
    return true;
  }

  void clearFocus([Control? control]) {
    if (control != null && !identical(_focused, control)) return;
    final previous = _focused;
    if (previous == null) return;
    _focused = null;
    previous.updateFocus(false);
  }

  /// Drops focus if mount, visibility or enabled state no longer permits it.
  void validate() {
    final focused = _focused;
    if (focused != null && !_canFocus(focused)) clearFocus(focused);
  }

  bool _canFocus(Control control) {
    if (!control.isMounted ||
        !identical(control.window, _host) ||
        !control.isFocusable) {
      return false;
    }
    UIElement? current = control;
    while (current != null) {
      if (!current.isVisible || !current.isEnabled) return false;
      current = current.logicalParent;
    }
    return true;
  }
}
