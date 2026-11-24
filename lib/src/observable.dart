typedef VoidListener = void Function();

final class PropertyChangedEvent {
  const PropertyChangedEvent(
      this.source, this.property, this.oldValue, this.newValue);

  final Object source;
  final Object property;
  final Object? oldValue;
  final Object? newValue;
}

typedef PropertyChangedListener = void Function(PropertyChangedEvent event);

abstract class ObservableObject {
  final _propertyListeners = <PropertyChangedListener>[];

  void addPropertyListener(PropertyChangedListener listener) {
    _propertyListeners.add(listener);
  }

  void removePropertyListener(PropertyChangedListener listener) {
    _propertyListeners.remove(listener);
  }

  void notifyPropertyChanged(
    Object property,
    Object? oldValue,
    Object? newValue,
  ) {
    final event = PropertyChangedEvent(this, property, oldValue, newValue);
    for (final listener in List.of(_propertyListeners)) {
      listener(event);
    }
  }
}

abstract interface class ObservableListenable {
  void addListener(VoidListener listener);
  void removeListener(VoidListener listener);
}

class ObservableValue<T> implements ObservableListenable {
  ObservableValue(T initialValue) : _value = initialValue;

  T _value;
  final _listeners = <VoidListener>[];

  T get value => _value;

  set value(T newValue) {
    if (_value == newValue) return;
    _value = newValue;
    for (final listener in List<VoidListener>.of(_listeners)) {
      listener();
    }
  }

  @override
  void addListener(VoidListener listener) => _listeners.add(listener);

  @override
  void removeListener(VoidListener listener) => _listeners.remove(listener);

  ObservableValue<R> map<R>(R Function(T value) convert) =>
      MappedObservableValue<T, R>(this, convert);
}

final class MappedObservableValue<T, R> extends ObservableValue<R> {
  MappedObservableValue(this.source, R Function(T value) convert)
      : _convert = convert,
        super(convert(source.value)) {
    source.addListener(_sourceChanged);
  }

  final ObservableValue<T> source;
  final R Function(T value) _convert;

  void _sourceChanged() {
    value = _convert(source.value);
  }

  void dispose() {
    source.removeListener(_sourceChanged);
  }
}
