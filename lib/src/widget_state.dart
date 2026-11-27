/// The state of a control, the way the widget states of GTK describe it.
///
/// A control knows whether it is enabled, whether the pointer is over it,
/// whether it is pressed and whether it holds the keyboard focus. A template
/// or a style reads the state as a whole instead of a set of separate flags,
/// and the platform bridges of assistive technologies publish the same state.
final class WidgetState {
  const WidgetState({
    this.enabled = true,
    this.hovered = false,
    this.pressed = false,
    this.focused = false,
  });

  /// The control can be used.
  final bool enabled;

  /// The pointer is over the control.
  final bool hovered;

  /// The pointer is pressed on the control.
  final bool pressed;

  /// The control holds the keyboard focus.
  final bool focused;

  WidgetState copyWith({
    bool? enabled,
    bool? hovered,
    bool? pressed,
    bool? focused,
  }) {
    return WidgetState(
      enabled: enabled ?? this.enabled,
      hovered: hovered ?? this.hovered,
      pressed: pressed ?? this.pressed,
      focused: focused ?? this.focused,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetState &&
      other.enabled == enabled &&
      other.hovered == hovered &&
      other.pressed == pressed &&
      other.focused == focused;

  @override
  int get hashCode => Object.hash(enabled, hovered, pressed, focused);

  @override
  String toString() => 'WidgetState(enabled: $enabled, hovered: $hovered, '
      'pressed: $pressed, focused: $focused)';
}
