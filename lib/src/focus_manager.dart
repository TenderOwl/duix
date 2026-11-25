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

  /// Moves focus through the logical tree, wrapping at either end.
  bool moveFocus({bool reverse = false}) {
    validate();
    final focused = _focused;
    final scope = focused == null ? null : _nearestFocusScope(focused);
    final root = scope ?? _host.rootElement;
    if (root == null) return false;

    final candidates = <Control>[];
    _collectFocusable(root, candidates, includeRoot: scope == null);
    if (candidates.isEmpty) return false;

    final currentIndex = focused == null
        ? -1
        : candidates.indexWhere((control) => identical(control, focused));
    final nextIndex = currentIndex < 0
        ? (reverse ? candidates.length - 1 : 0)
        : (currentIndex + (reverse ? -1 : 1)) % candidates.length;
    return requestFocus(candidates[nextIndex]);
  }

  /// Drops focus if mount, visibility or enabled state no longer permits it.
  void validate() {
    final focused = _focused;
    if (focused != null && !_canFocus(focused)) clearFocus(focused);
  }

  UIElement? _nearestFocusScope(Control control) {
    UIElement? current = control;
    while (current != null) {
      if (current.isFocusScope) return current;
      current = current.logicalParent;
    }
    return null;
  }

  void _collectFocusable(
    UIElement element,
    List<Control> controls, {
    bool includeRoot = true,
  }) {
    if (!element.isVisible || !element.isEnabled) return;
    if (includeRoot && element is Control && _canFocus(element)) {
      controls.add(element);
    }
    for (final child in element.logicalChildren) {
      _collectFocusable(child, controls);
    }
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
