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

final class BindingException implements Exception {
  BindingException(this.property, this.operation, this.cause);

  final DuiProperty<dynamic, dynamic> property;
  final String operation;
  final Object cause;

  @override
  String toString() => 'BindingException: $operation failed for property '
      '"${property.name}": $cause';
}

abstract interface class BindingSubscription {
  DuiProperty<dynamic, dynamic> get property;
  BindingMode get mode;
  bool get isCancelled;
  void cancel();
}

abstract class PropertyOwner extends ObservableObject {
  final _localValues = <DuiProperty<dynamic, dynamic>, Object?>{};
  final _bindingSubscriptions =
      <DuiProperty<dynamic, dynamic>, _ActiveBinding<dynamic>>{};
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;

  T getValue<T>(DuiProperty<dynamic, T> property) {
    final active = _bindingSubscriptions[property];
    if (active != null) return active.read() as T;
    return (_localValues[property] ?? property.defaultValue) as T;
  }

  void setValue<T>(DuiProperty<dynamic, T> property, T value) {
    _checkNotDisposed();
    final active = _bindingSubscriptions[property];
    if (active != null && active.mode == BindingMode.twoWay) {
      if (active.lastValue == value) return;
      active.write(value);
      return;
    }

    active?.cancel();
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
    _checkNotDisposed();
    if (mode == BindingMode.twoWay && !binding.canWrite) {
      throw ArgumentError('A two-way binding must support writes.');
    }

    late final T newValue;
    try {
      newValue = binding.read();
    } catch (error) {
      throw BindingException(property, 'Initial read', error);
    }

    _bindingSubscriptions[property]?.cancel();
    final oldValue = getValue(property);
    late final _ActiveBinding<T> active;
    active = _ActiveBinding<T>(
      property,
      binding,
      mode,
      (previous, current) => onDuiPropertyChanged(property, previous, current),
      () => _bindingCancelled(active),
    )..lastValue = oldValue;
    _bindingSubscriptions[property] = active;
    try {
      binding.addListener(active.sourceChanged);
    } catch (error) {
      active.cancel();
      throw BindingException(property, 'Listener subscription', error);
    }

    active.lastValue = newValue;
    if (oldValue != newValue) {
      onDuiPropertyChanged(property, oldValue, newValue);
    }
    return active;
  }

  /// Detaches every binding and keeps its latest synchronized value as local.
  /// The owner cannot be bound or mutated through [setValue] after disposal.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final binding in List.of(_bindingSubscriptions.values)) {
      binding.cancel();
    }
    _bindingSubscriptions.clear();
  }

  void _bindingCancelled<T>(_ActiveBinding<T> binding) {
    final current = _bindingSubscriptions[binding.property];
    if (!identical(current, binding)) return;
    _bindingSubscriptions.remove(binding.property);
    _localValues[binding.property] = binding.lastValue;
  }

  void _checkNotDisposed() {
    if (_isDisposed) throw StateError('The property owner is disposed.');
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
    this.onCancelled,
  );

  @override
  final DuiProperty<dynamic, T> property;
  final Binding<T> binding;
  @override
  final BindingMode mode;
  final void Function(T oldValue, T newValue) onChanged;
  final void Function() onCancelled;
  late T lastValue;
  bool _cancelled = false;
  bool _isWriting = false;
  bool _isSynchronizing = false;

  @override
  bool get isCancelled => _cancelled;

  T read() {
    try {
      return binding.read();
    } catch (error) {
      throw BindingException(property, 'Read', error);
    }
  }

  void write(T value) {
    if (_cancelled) throw StateError('The binding subscription is cancelled.');
    if (_isWriting) return;
    _isWriting = true;
    try {
      binding.write(value);
    } catch (error) {
      throw BindingException(property, 'Write', error);
    } finally {
      _isWriting = false;
    }
    _synchronize();
  }

  void sourceChanged() {
    if (!_cancelled && !_isWriting) _synchronize();
  }

  void _synchronize() {
    if (_cancelled || _isSynchronizing) return;
    _isSynchronizing = true;
    try {
      final previousValue = lastValue;
      final newValue = read();
      if (previousValue == newValue) return;
      lastValue = newValue;
      onChanged(previousValue, newValue);
    } finally {
      _isSynchronizing = false;
    }
  }

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    binding.removeListener(sourceChanged);
    onCancelled();
  }

  @override
  String toString() =>
      'BindingSubscription(property: ${property.name}, mode: $mode, '
      'cancelled: $_cancelled)';
}
