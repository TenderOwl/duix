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

/// Effective value precedence, from lowest to highest.
enum DuiValueSource {
  defaultValue,
  inherited,
  style,
  binding,
  local,
  animation
}

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

/// Binds directly to a typed property without string paths or reflection.
final class PropertyBinding<T> implements Binding<T> {
  PropertyBinding(this.source, this.property);

  final PropertyOwner source;
  final DuiProperty<dynamic, T> property;
  final _listeners = <VoidListener, PropertyChangedListener>{};

  @override
  T read() => source.getValue(property);

  @override
  void addListener(VoidListener listener) {
    if (_listeners.containsKey(listener)) return;
    void propertyChanged(PropertyChangedEvent event) {
      if (identical(event.property, property)) listener();
    }

    _listeners[listener] = propertyChanged;
    source.addPropertyListener(propertyChanged);
  }

  @override
  void removeListener(VoidListener listener) {
    final propertyChanged = _listeners.remove(listener);
    if (propertyChanged != null) {
      source.removePropertyListener(propertyChanged);
    }
  }

  @override
  bool get canWrite => true;

  @override
  void write(T value) => source.setValue(property, value);
}

extension PropertyBindingExtension on PropertyOwner {
  Binding<T> propertyBinding<T>(DuiProperty<dynamic, T> property) =>
      PropertyBinding<T>(this, property);
}

final class MappedBinding<T, R> implements Binding<R> {
  MappedBinding(this.source, this.convert);

  final Binding<T> source;
  final R Function(T value) convert;

  @override
  R read() => convert(source.read());

  @override
  void addListener(VoidListener listener) => source.addListener(listener);

  @override
  void removeListener(VoidListener listener) => source.removeListener(listener);

  @override
  bool get canWrite => false;

  @override
  void write(R value) => throw StateError('A mapped binding is read-only.');
}

extension BindingMapExtension<T> on Binding<T> {
  Binding<R> map<R>(R Function(T value) convert) =>
      MappedBinding<T, R>(this, convert);
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
  final _inheritedValues = <DuiProperty<dynamic, dynamic>, Object?>{};
  final _styleValues = <DuiProperty<dynamic, dynamic>, Object?>{};
  final _localValues = <DuiProperty<dynamic, dynamic>, Object?>{};
  final _animationValues = <DuiProperty<dynamic, dynamic>, Object?>{};
  final _bindingSubscriptions =
      <DuiProperty<dynamic, dynamic>, _ActiveBinding<dynamic>>{};
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;

  DuiValueSource getValueSource<T>(DuiProperty<dynamic, T> property) {
    if (_animationValues.containsKey(property)) return DuiValueSource.animation;
    if (_localValues.containsKey(property)) return DuiValueSource.local;
    if (_bindingSubscriptions.containsKey(property)) {
      return DuiValueSource.binding;
    }
    if (_styleValues.containsKey(property)) return DuiValueSource.style;
    if (_inheritedValues.containsKey(property)) return DuiValueSource.inherited;
    return DuiValueSource.defaultValue;
  }

  T getValue<T>(DuiProperty<dynamic, T> property) =>
      _effectiveValue(property) as T;

  void setValue<T>(DuiProperty<dynamic, T> property, T value) {
    _checkNotDisposed();
    final active = _bindingSubscriptions[property];
    if (active != null && active.mode == BindingMode.twoWay) {
      if (active.lastValue == value) return;
      active.write(value);
      return;
    }
    if (active == null && value == property.defaultValue) {
      clearLocalValue(property);
      return;
    }
    _setLayerValue(_localValues, property, value);
  }

  void setInheritedValue<T>(DuiProperty<dynamic, T> property, T value) =>
      _setLayerValue(_inheritedValues, property, value);

  void setStyleValue<T>(DuiProperty<dynamic, T> property, T value) =>
      _setLayerValue(_styleValues, property, value);

  void setAnimationValue<T>(DuiProperty<dynamic, T> property, T value) =>
      _setLayerValue(_animationValues, property, value);

  void clearLocalValue<T>(DuiProperty<dynamic, T> property) =>
      _clearLayerValue(_localValues, property);

  void clearInheritedValue<T>(DuiProperty<dynamic, T> property) =>
      _clearLayerValue(_inheritedValues, property);

  void clearStyleValue<T>(DuiProperty<dynamic, T> property) =>
      _clearLayerValue(_styleValues, property);

  void clearAnimationValue<T>(DuiProperty<dynamic, T> property) =>
      _clearLayerValue(_animationValues, property);

  void _setLayerValue<T>(
    Map<DuiProperty<dynamic, dynamic>, Object?> values,
    DuiProperty<dynamic, T> property,
    T value,
  ) {
    _checkNotDisposed();
    if (values.containsKey(property) && values[property] == value) return;
    final oldValue = getValue(property);
    values[property] = value;
    _notifyEffectiveChange(property, oldValue);
  }

  void _clearLayerValue<T>(
    Map<DuiProperty<dynamic, dynamic>, Object?> values,
    DuiProperty<dynamic, T> property,
  ) {
    _checkNotDisposed();
    if (!values.containsKey(property)) return;
    final oldValue = getValue(property);
    values.remove(property);
    _notifyEffectiveChange(property, oldValue);
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

    final oldValue = getValue(property);
    _bindingSubscriptions[property]?.cancel(preserveLocal: false);
    _localValues.remove(property);
    late final _ActiveBinding<T> active;
    active = _ActiveBinding<T>(
      property,
      binding,
      mode,
      (previous, current) => _bindingValueChanged(active, previous, current),
      (preserveLocal) => _bindingCancelled(active, preserveLocal),
    )..lastValue = newValue;
    _bindingSubscriptions[property] = active;
    try {
      binding.addListener(active.sourceChanged);
    } catch (error) {
      active.cancel(preserveLocal: false);
      throw BindingException(property, 'Listener subscription', error);
    }

    _notifyEffectiveChange(
      property,
      oldValue,
      bindingOverride: newValue,
      hasBindingOverride: true,
    );
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

  Object? _effectiveValue<T>(
    DuiProperty<dynamic, T> property, {
    Object? bindingOverride,
    bool hasBindingOverride = false,
  }) {
    if (_animationValues.containsKey(property)) {
      return _animationValues[property];
    }
    if (_localValues.containsKey(property)) return _localValues[property];
    final active = _bindingSubscriptions[property];
    if (active != null) {
      return hasBindingOverride ? bindingOverride : active.read();
    }
    if (_styleValues.containsKey(property)) return _styleValues[property];
    if (_inheritedValues.containsKey(property)) {
      return _inheritedValues[property];
    }
    return property.defaultValue;
  }

  void _bindingValueChanged<T>(
    _ActiveBinding<T> active,
    T previous,
    T current,
  ) {
    final oldValue = _effectiveValue(
      active.property,
      bindingOverride: previous,
      hasBindingOverride: true,
    );
    _notifyEffectiveChange(
      active.property,
      oldValue,
      bindingOverride: current,
      hasBindingOverride: true,
    );
  }

  void _notifyEffectiveChange<T>(
    DuiProperty<dynamic, T> property,
    Object? oldValue, {
    Object? bindingOverride,
    bool hasBindingOverride = false,
  }) {
    final newValue = _effectiveValue(
      property,
      bindingOverride: bindingOverride,
      hasBindingOverride: hasBindingOverride,
    );
    if (oldValue != newValue) {
      onDuiPropertyChanged(property, oldValue as T, newValue as T);
    }
  }

  void _bindingCancelled<T>(
    _ActiveBinding<T> binding,
    bool preserveLocal,
  ) {
    final current = _bindingSubscriptions[binding.property];
    if (!identical(current, binding)) return;
    _bindingSubscriptions.remove(binding.property);
    if (preserveLocal && !_localValues.containsKey(binding.property)) {
      _localValues[binding.property] = binding.lastValue;
    }
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
  final void Function(bool preserveLocal) onCancelled;
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
  void cancel({bool preserveLocal = true}) {
    if (_cancelled) return;
    _cancelled = true;
    binding.removeListener(sourceChanged);
    onCancelled(preserveLocal);
  }

  @override
  String toString() =>
      'BindingSubscription(property: ${property.name}, mode: $mode, '
      'cancelled: $_cancelled)';
}
