import 'drawing.dart';
import 'events.dart';
import 'geometry.dart';
import 'properties.dart';
import 'text_layout.dart';

abstract interface class WindowHost {
  void requestFrame();
  bool requestFocus(Control control);
  TextLayoutFactory get textLayoutFactory;
  double get displayScale;
  void startTextInput(Control control) {}
  void stopTextInput(Control control) {}
  void updateTextInputArea(
    Control control,
    Rect area,
    double cursorX,
  ) {}
  String? readClipboardText() => null;
  bool writeClipboardText(String text) => false;
}

abstract class UIElement extends PropertyOwner {
  static const previewPointerDown = RoutedEvent<PointerEventArgs>(
    'previewPointerDown',
    RoutingStrategy.tunnel,
  );
  static const pointerDown = RoutedEvent<PointerEventArgs>(
    'pointerDown',
    RoutingStrategy.bubble,
  );
  static const pointerUp = RoutedEvent<PointerEventArgs>(
    'pointerUp',
    RoutingStrategy.bubble,
  );
  static const keyDown = RoutedEvent<KeyEventArgs>(
    'keyDown',
    RoutingStrategy.bubble,
  );
  static const textInput = RoutedEvent<TextInputEventArgs>(
    'textInput',
    RoutingStrategy.bubble,
  );
  static const textEditing = RoutedEvent<TextEditingEventArgs>(
    'textEditing',
    RoutingStrategy.bubble,
  );

  final _handlers = <RoutedEvent<dynamic>, List<Object>>{};

  UIElement? _logicalParent;
  WindowHost? _window;
  Rect _bounds = Rect.zero;
  Size _desiredSize = Size.zero;
  bool _isMounted = false;
  bool _isVisible = true;
  bool _isEnabled = true;
  Object? _dataContext;
  bool _measureValid = false;
  bool _arrangeValid = false;

  UIElement? get logicalParent => _logicalParent;
  WindowHost? get window => _window;
  Rect get bounds => _bounds;
  Size get desiredSize => _desiredSize;
  bool get isMounted => _isMounted;

  bool get isVisible => _isVisible;
  set isVisible(bool value) {
    if (_isVisible == value) return;
    final oldValue = _isVisible;
    _isVisible = value;
    invalidateMeasure();
    notifyPropertyChanged('isVisible', oldValue, value);
  }

  bool get isEnabled => _isEnabled;
  set isEnabled(bool value) {
    if (_isEnabled == value) return;
    final oldValue = _isEnabled;
    _isEnabled = value;
    invalidatePaint();
    notifyPropertyChanged('isEnabled', oldValue, value);
  }

  Object? get dataContext => _dataContext;
  set dataContext(Object? value) {
    if (_dataContext == value) return;
    final oldValue = _dataContext;
    _dataContext = value;
    notifyPropertyChanged('dataContext', oldValue, value);
  }

  Object? get effectiveDataContext =>
      _dataContext ?? _logicalParent?.effectiveDataContext;

  Size measure(Size availableSize) {
    if (!_isVisible) {
      _desiredSize = Size.zero;
      _measureValid = true;
      return _desiredSize;
    }
    if (!_measureValid) {
      _desiredSize = measureCore(availableSize).constrain(availableSize);
      _measureValid = true;
    }
    return _desiredSize;
  }

  void arrange(Rect finalRect) {
    if (!_arrangeValid || _bounds != finalRect) {
      _bounds = finalRect;
      arrangeCore(finalRect);
      _arrangeValid = true;
    }
  }

  void render(DrawingContext context) {
    if (_isVisible) renderCore(context);
  }

  UIElement? hitTest(Point position) {
    if (!_isVisible || !_isEnabled || !_bounds.contains(position)) return null;
    return hitTestCore(position) ?? this;
  }

  void addHandler<T extends RoutedEventArgs>(
    RoutedEvent<T> event,
    RoutedEventHandler<T> handler,
  ) {
    _handlers.putIfAbsent(event, () => <Object>[]).add(handler);
  }

  void removeHandler<T extends RoutedEventArgs>(
    RoutedEvent<T> event,
    RoutedEventHandler<T> handler,
  ) {
    _handlers[event]?.remove(handler);
  }

  void raiseEvent<T extends RoutedEventArgs>(
    RoutedEvent<T> event,
    T args,
  ) {
    final path = <UIElement>[];
    UIElement? current = this;
    while (current != null) {
      path.add(current);
      current = current._logicalParent;
    }
    final route =
        event.strategy == RoutingStrategy.tunnel ? path.reversed : path;
    args.originalSource ??= this;

    for (final element in route) {
      if (args.handled) break;
      args.source = element;
      final handlers = element._handlers[event];
      if (handlers == null) continue;
      for (final handler in List<Object>.of(handlers)) {
        (handler as RoutedEventHandler<T>)(element, args);
        if (args.handled) break;
      }
    }
  }

  void invalidateMeasure() {
    _measureValid = false;
    _arrangeValid = false;
    _logicalParent?.invalidateMeasure();
    _window?.requestFrame();
  }

  void invalidateArrange() {
    _arrangeValid = false;
    _window?.requestFrame();
  }

  void invalidatePaint() {
    _window?.requestFrame();
  }

  @override
  void onDuiPropertyChanged<T>(
    DuiProperty<dynamic, T> property,
    T oldValue,
    T newValue,
  ) {
    if (property.affectsMeasure) invalidateMeasure();
    if (property.affectsArrange) invalidateArrange();
    if (property.affectsPaint) invalidatePaint();
    super.onDuiPropertyChanged(property, oldValue, newValue);
  }

  void attachToParent(UIElement? parent) {
    if (identical(parent, this)) {
      throw ArgumentError('An element cannot be its own parent.');
    }
    _logicalParent = parent;
  }

  void mountTo(WindowHost? window) {
    if (_isMounted && identical(_window, window)) return;
    _window = window;
    _isMounted = window != null;
    if (_isMounted) {
      onMounted();
    } else {
      onUnmounted();
    }
    for (final child in logicalChildren) {
      child.mountTo(window);
    }
  }

  Iterable<UIElement> get logicalChildren => const [];

  Size measureCore(Size availableSize);
  void arrangeCore(Rect finalRect) {}
  void renderCore(DrawingContext context) {}
  UIElement? hitTestCore(Point position) => null;
  void onMounted() {}
  void onUnmounted() {}
}

abstract class Control extends UIElement {
  bool _isFocused = false;
  bool _isPointerOver = false;

  bool get isFocusable => true;
  bool get isFocused => _isFocused;
  bool get isPointerOver => _isPointerOver;

  bool focus() => _window?.requestFocus(this) ?? false;

  void updateFocus(bool value) {
    if (_isFocused == value) return;
    _isFocused = value;
    invalidatePaint();
    onFocusChanged(value);
  }

  void onFocusChanged(bool value) {}
  void onTextInputActivated() {}

  void updatePointerOver(bool value) {
    if (_isPointerOver == value) return;
    _isPointerOver = value;
    invalidatePaint();
  }
}
