import 'properties.dart';

/// A typed property assignment applied through the style value layer.
final class DuiSetter<TOwner, T> {
  const DuiSetter(this.property, this.value);

  final DuiProperty<TOwner, T> property;
  final T value;

  void applyTo(PropertyOwner target) {
    if (target is! TOwner) {
      throw StateError(
        'Setter for ${property.name} cannot be applied to '
        '${target.runtimeType}; expected $TOwner.',
      );
    }
    target.setStyleValue<T>(property, value);
  }

  void clearFrom(PropertyOwner target) {
    if (target is TOwner) target.clearStyleValue<T>(property);
  }
}

/// A reusable collection of setters for a particular control type.
final class Style<TOwner> {
  const Style({this.name, this.setters = const []});

  final String? name;
  final List<DuiSetter<TOwner, dynamic>> setters;

  Type get targetType => TOwner;

  @override
  String toString() => name ?? 'Style<$targetType>';
}
