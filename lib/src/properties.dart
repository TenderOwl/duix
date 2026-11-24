import 'observable.dart';

final class DuiProperty<TOwner, T> {
  const DuiProperty({
    required this.name,
    required this.defaultValue,
    this.affectsMeasure = false,
    this.affectsArrange = false,
    this.affectsPaint = false,
  });

  final String name;
  final T defaultValue;
  final bool affectsMeasure;
  final bool affectsArrange;
  final bool affectsPaint;

  @override
  String toString() => name;
}

enum BindingMode { oneWay, twoWay }

abstract interface class Binding<T> {
  T read();
  void addListener(VoidListener listener);
  void removeListener(VoidListener listener);

  bool get canWrite;
  void write(T value);
}

final class ObservableBinding<T> implements Binding<T> {
  ObservableBinding(this.source);

  final ObservableValue<T> source;

  @override
  T read() => source.value;

  @override
  void addListener(VoidListener listener) => source.addListener(listener);

  @override
  void removeListener(VoidListener listener) => source.removeListener(listener);

  @override
  bool get canWrite => true;

  @override
  void write(T value) => source.value = value;
}

extension ObservableBindingExtension<T> on ObservableValue<T> {
  Binding<T> asBinding() => ObservableBinding<T>(this);
}

final class CallbackBinding<T> implements Binding<T> {
  CallbackBinding({required T Function() read, T Function(T value)? write})
      : _read = read,
        _write = write;

  final T Function() _read;
  final T Function(T value)? _write;
  final _listeners = <VoidListener>[];

  @override
  T read() => _read();

  @override
  void addListener(VoidListener listener) => _listeners.add(listener);

  @override
  void removeListener(VoidListener listener) => _listeners.remove(listener);

  void notifyChanged() {
    for (final listener in List<VoidListener>.of(_listeners)) {
      listener();
    }
  }

  @override
  bool get canWrite => _write != null;

  @override
  void write(T value) {
    final write = _write;
    if (write == null) {
      throw StateError('This binding is read-only.');
    }
    write(value);
  }
}

abstract interface class BindingSubscription {
  void cancel();
}

abstract class PropertyOwner extends ObservableObject {
  final _localValues = <DuiProperty<dynamic, dynamic>, Object?>{};
  final _bindingSubscriptions =
      <DuiProperty<dynamic, dynamic>, _ActiveBinding<dynamic>>{};

  T getValue<T>(DuiProperty<dynamic, T> property) {
    final active = _bindingSubscriptions[property];
    if (active != null) return active.read() as T;
    return (_localValues[property] ?? property.defaultValue) as T;
  }

  void setValue<T>(DuiProperty<dynamic, T> property, T value) {
    final active = _bindingSubscriptions[property];
    if (active != null && active.mode == BindingMode.twoWay) {
      active.write(value);
      return;
    }

    _bindingSubscriptions.remove(property)?.cancel();
    final oldValue = getValue(property);
    _localValues[property] = value;
    if (oldValue != value) {
      onDuiPropertyChanged(property, oldValue, value);
    }
  }

  BindingSubscription bind<T>(
    DuiProperty<dynamic, T> property,
    Binding<T> binding, {
    BindingMode mode = BindingMode.oneWay,
  }) {
    if (mode == BindingMode.twoWay && !binding.canWrite) {
      throw ArgumentError('A two-way binding must support writes.');
    }

    _bindingSubscriptions.remove(property)?.cancel();
    final oldValue = getValue(property);
    late final _ActiveBinding<T> active;
    active = _ActiveBinding<T>(property, binding, mode, () {
      final previousValue = active.lastValue;
      final newValue = binding.read();
      active.lastValue = newValue;
      if (previousValue != newValue) {
        onDuiPropertyChanged(property, previousValue, newValue);
      }
    });
    active.lastValue = oldValue;
    _bindingSubscriptions[property] = active;
    binding.addListener(active.sourceChanged);

    final newValue = binding.read();
    active.lastValue = newValue;
    if (oldValue != newValue) {
      onDuiPropertyChanged(property, oldValue, newValue);
    }
    return active;
  }

  void onDuiPropertyChanged<T>(
    DuiProperty<dynamic, T> property,
    T oldValue,
    T newValue,
  ) {
    notifyPropertyChanged(property, oldValue, newValue);
  }
}

final class _ActiveBinding<T> implements BindingSubscription {
  _ActiveBinding(
    this.property,
    this.binding,
    this.mode,
    this.onChanged,
  );

  final DuiProperty<dynamic, T> property;
  final Binding<T> binding;
  final BindingMode mode;
  final void Function() onChanged;
  late T lastValue;
  bool _cancelled = false;

  T read() => binding.read();
  void write(T value) => binding.write(value);

  void sourceChanged() {
    if (!_cancelled) onChanged();
  }

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    binding.removeListener(sourceChanged);
  }
}
