import 'dart:typed_data';

import 'drawing.dart';
import 'events.dart';
import 'geometry.dart';
import 'properties.dart';
import 'styles.dart';
import 'text_layout.dart';

abstract interface class WindowHost {
  void requestFrame();
  bool requestFocus(Control control);
  void validateFocus() {}
  UIElement? get rootElement => null;
  Control? get focusedElement => null;
  TextLayoutFactory get textLayoutFactory;
  double get displayScale;
  bool capturePointer(Control control) => false;
  void releasePointer(Control control) {}
  bool hasPointerCapture(Control control) => false;
  void startTextInput(Control control) {}
  void stopTextInput(Control control) {}
  void updateTextInputArea(
    Control control,
    Rect area,
    double cursorX,
  ) {}
  String? readClipboardText() => null;
  bool writeClipboardText(String text) => false;
  bool hasClipboardData(String mimeType) => false;
  Uint8List? readClipboardData(String mimeType) => null;
  bool writeClipboardData(Map<String, List<int>> formats) => false;
}

abstract class UIElement extends PropertyOwner {
  static const dataContextProperty = DuiProperty<UIElement, Object?>(
    name: 'dataContext',
    defaultValue: null,
  );
  static const styleProperty = DuiProperty<UIElement, Style<dynamic>?>(
    name: 'style',
    defaultValue: null,
  );

  static const previewPointerDown = RoutedEvent<PointerEventArgs>(
    'previewPointerDown',
    RoutingStrategy.tunnel,
  );
  static const pointerDown = RoutedEvent<PointerEventArgs>(
    'pointerDown',
    RoutingStrategy.bubble,
  );
  static const pointerMove = RoutedEvent<PointerEventArgs>(
    'pointerMove',
    RoutingStrategy.bubble,
  );
  static const pointerUp = RoutedEvent<PointerEventArgs>(
    'pointerUp',
    RoutingStrategy.bubble,
  );
  static const mouseWheel = RoutedEvent<MouseWheelEventArgs>(
    'mouseWheel',
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
  Size _arrangedSize = Size.zero;
  Size? _previousAvailableSize;
  double _minWidth = 0;
  double _maxWidth = double.infinity;
  double _minHeight = 0;
  double _maxHeight = double.infinity;
  EdgeInsets _margin = EdgeInsets.zero;
  HorizontalAlignment _horizontalAlignment = HorizontalAlignment.stretch;
  VerticalAlignment _verticalAlignment = VerticalAlignment.stretch;
  bool _isMounted = false;
  bool _isVisible = true;
  bool _isEnabled = true;
  bool _isFocusScope = false;
  bool _measureValid = false;
  bool _arrangeValid = false;

  UIElement? get logicalParent => _logicalParent;
  WindowHost? get window => _window;

  /// Actual control bounds, excluding margin and alignment slot space.
  Rect get bounds => _bounds;

  /// Size requested during measure, including margin.
  Size get desiredSize => _desiredSize;

  /// Size of the slot supplied to arrange, including margin.
  Size get arrangedSize => _arrangedSize;
  bool get isMounted => _isMounted;

  double get minWidth => _minWidth;
  set minWidth(double value) {
    _validateMinimum(value, _maxWidth, 'minWidth');
    _setLayoutValue(
      'minWidth',
      _minWidth,
      value,
      (value) => _minWidth = value,
    );
  }

  double get maxWidth => _maxWidth;
  set maxWidth(double value) {
    _validateMaximum(value, _minWidth, 'maxWidth');
    _setLayoutValue(
      'maxWidth',
      _maxWidth,
      value,
      (value) => _maxWidth = value,
    );
  }

  double get minHeight => _minHeight;
  set minHeight(double value) {
    _validateMinimum(value, _maxHeight, 'minHeight');
    _setLayoutValue(
      'minHeight',
      _minHeight,
      value,
      (value) => _minHeight = value,
    );
  }

  double get maxHeight => _maxHeight;
  set maxHeight(double value) {
    _validateMaximum(value, _minHeight, 'maxHeight');
    _setLayoutValue(
      'maxHeight',
      _maxHeight,
      value,
      (value) => _maxHeight = value,
    );
  }

  EdgeInsets get margin => _margin;
  set margin(EdgeInsets value) {
    for (final component in [
      value.left,
      value.top,
      value.right,
      value.bottom
    ]) {
      if (component < 0 || !component.isFinite) {
        throw ArgumentError.value(
            value, 'margin', 'Must be finite and non-negative.');
      }
    }
    _setLayoutValue(
      'margin',
      _margin,
      value,
      (value) => _margin = value,
    );
  }

  HorizontalAlignment get horizontalAlignment => _horizontalAlignment;
  set horizontalAlignment(HorizontalAlignment value) {
    if (_horizontalAlignment == value) return;
    final oldValue = _horizontalAlignment;
    _horizontalAlignment = value;
    invalidateArrange();
    notifyPropertyChanged('horizontalAlignment', oldValue, value);
  }

  VerticalAlignment get verticalAlignment => _verticalAlignment;
  set verticalAlignment(VerticalAlignment value) {
    if (_verticalAlignment == value) return;
    final oldValue = _verticalAlignment;
    _verticalAlignment = value;
    invalidateArrange();
    notifyPropertyChanged('verticalAlignment', oldValue, value);
  }

  bool get isVisible => _isVisible;
  set isVisible(bool value) {
    if (_isVisible == value) return;
    final oldValue = _isVisible;
    _isVisible = value;
    invalidateMeasure();
    _window?.validateFocus();
    notifyPropertyChanged('isVisible', oldValue, value);
  }

  bool get isEnabled => _isEnabled;
  set isEnabled(bool value) {
    if (_isEnabled == value) return;
    final oldValue = _isEnabled;
    _isEnabled = value;
    invalidatePaint();
    _window?.validateFocus();
    notifyPropertyChanged('isEnabled', oldValue, value);
  }

  /// Limits Tab traversal to this element's descendants.
  bool get isFocusScope => _isFocusScope;
  set isFocusScope(bool value) {
    if (_isFocusScope == value) return;
    final oldValue = _isFocusScope;
    _isFocusScope = value;
    notifyPropertyChanged('isFocusScope', oldValue, value);
  }

  Style<dynamic>? get style => getValue(styleProperty);
  set style(Style<dynamic>? value) => setValue(styleProperty, value);

  Object? get dataContext => getValue(dataContextProperty);
  set dataContext(Object? value) => setValue(dataContextProperty, value);

  /// Compatibility alias for the effective local or inherited context.
  Object? get effectiveDataContext => dataContext;

  /// Returns the context when it has type [T], otherwise returns null.
  T? dataContextAs<T>() {
    final value = dataContext;
    return value is T ? value : null;
  }

  /// Returns the context as [T] or throws when it is absent or has another type.
  T requireDataContext<T>() {
    final value = dataContext;
    if (value is! T) {
      throw StateError(
        'Expected data context of type $T, but got ${value.runtimeType}.',
      );
    }
    return value;
  }

  Size measure(Size availableSize) {
    _validateAvailableSize(availableSize);
    if (!_isVisible) {
      _desiredSize = Size.zero;
      _previousAvailableSize = availableSize;
      _measureValid = true;
      return _desiredSize;
    }
    if (_measureValid && _previousAvailableSize == availableSize) {
      return _desiredSize;
    }

    final innerAvailable = Size(
      (availableSize.width - margin.horizontal).clamp(0, double.infinity),
      (availableSize.height - margin.vertical).clamp(0, double.infinity),
    );
    final coreConstraints = Size(
      innerAvailable.width < maxWidth ? innerAvailable.width : maxWidth,
      innerAvailable.height < maxHeight ? innerAvailable.height : maxHeight,
    );
    final measured = measureCore(coreConstraints).constrain(coreConstraints);
    if (!measured.width.isFinite || !measured.height.isFinite) {
      throw StateError('An element must report a finite desired size.');
    }
    final constrained = Size(
      measured.width.clamp(minWidth, maxWidth),
      measured.height.clamp(minHeight, maxHeight),
    );
    _desiredSize = margin.inflateSize(constrained);
    _previousAvailableSize = availableSize;
    _measureValid = true;
    return _desiredSize;
  }

  void arrange(Rect finalRect) {
    if (!finalRect.width.isFinite ||
        !finalRect.height.isFinite ||
        finalRect.width < 0 ||
        finalRect.height < 0) {
      throw ArgumentError.value(
          finalRect, 'finalRect', 'Must be finite and non-negative.');
    }

    final contentRect = finalRect.deflate(margin);
    final desiredContent = Size(
      (desiredSize.width - margin.horizontal).clamp(0, double.infinity),
      (desiredSize.height - margin.vertical).clamp(0, double.infinity),
    );
    final width = horizontalAlignment == HorizontalAlignment.stretch
        ? contentRect.width
        : (desiredContent.width < contentRect.width
            ? desiredContent.width
            : contentRect.width);
    final height = verticalAlignment == VerticalAlignment.stretch
        ? contentRect.height
        : (desiredContent.height < contentRect.height
            ? desiredContent.height
            : contentRect.height);
    final left = switch (horizontalAlignment) {
      HorizontalAlignment.center =>
        contentRect.left + (contentRect.width - width) / 2,
      HorizontalAlignment.right => contentRect.right - width,
      _ => contentRect.left,
    };
    final top = switch (verticalAlignment) {
      VerticalAlignment.center =>
        contentRect.top + (contentRect.height - height) / 2,
      VerticalAlignment.bottom => contentRect.bottom - height,
      _ => contentRect.top,
    };
    final actualBounds = Rect.fromLTWH(left, top, width, height);

    if (!_arrangeValid ||
        _bounds != actualBounds ||
        _arrangedSize != finalRect.size) {
      _bounds = actualBounds;
      _arrangedSize = finalRect.size;
      arrangeCore(actualBounds);
      _arrangeValid = true;
    }
  }

  void _setLayoutValue<T>(
    String name,
    T oldValue,
    T newValue,
    void Function(T value) assign,
  ) {
    if (oldValue == newValue) return;
    assign(newValue);
    invalidateMeasure();
    notifyPropertyChanged(name, oldValue, newValue);
  }

  static void _validateAvailableSize(Size value) {
    if (value.width < 0 ||
        value.height < 0 ||
        value.width.isNaN ||
        value.height.isNaN) {
      throw ArgumentError.value(value, 'availableSize');
    }
  }

  static void _validateMinimum(double value, double maximum, String name) {
    if (value < 0 || !value.isFinite || value > maximum) {
      throw ArgumentError.value(value, name);
    }
  }

  static void _validateMaximum(double value, double minimum, String name) {
    if (value < 0 || value.isNaN || value < minimum) {
      throw ArgumentError.value(value, name);
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
    _logicalParent?.invalidateArrange();
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
    if (identical(property, styleProperty)) {
      _updateStyle(oldValue as Style<dynamic>?, newValue as Style<dynamic>?);
    }
    if (identical(property, dataContextProperty)) {
      for (final child in logicalChildren) {
        child._inheritDataContext(dataContext);
      }
    }
  }

  void _updateStyle(Style<dynamic>? oldStyle, Style<dynamic>? newStyle) {
    final newProperties = <DuiProperty<dynamic, dynamic>>{
      for (final setter in newStyle?.setters ?? const []) setter.property,
    };
    for (final setter in oldStyle?.setters ?? const []) {
      if (!newProperties.contains(setter.property)) setter.clearFrom(this);
    }
    for (final setter in newStyle?.setters ?? const []) {
      setter.applyTo(this);
    }
  }

  void attachToParent(UIElement? parent) {
    if (identical(parent, this)) {
      throw ArgumentError('An element cannot be its own parent.');
    }
    if (identical(_logicalParent, parent)) return;
    _logicalParent = parent;
    _inheritDataContext(parent?.dataContext);
  }

  void _inheritDataContext(Object? value) {
    if (value == null) {
      clearInheritedValue(dataContextProperty);
    } else {
      setInheritedValue(dataContextProperty, value);
    }
  }

  void mountTo(WindowHost? window) {
    if (_isMounted && identical(_window, window)) return;
    final previousWindow = _window;
    _window = window;
    _isMounted = window != null;
    if (!_isMounted) previousWindow?.validateFocus();
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
  static const isPointerOverProperty = DuiProperty<Control, bool>(
    name: 'isPointerOver',
    defaultValue: false,
    affectsPaint: true,
  );

  bool _isFocused = false;

  bool get isFocusable => true;
  bool get isFocused => _isFocused;
  bool get isPointerOver => getValue(isPointerOverProperty);

  bool focus() => _window?.requestFocus(this) ?? false;
  bool capturePointer() => _window?.capturePointer(this) ?? false;
  void releasePointer() => _window?.releasePointer(this);
  bool get hasPointerCapture => _window?.hasPointerCapture(this) ?? false;

  void updateFocus(bool value) {
    if (_isFocused == value) return;
    _isFocused = value;
    invalidatePaint();
    onFocusChanged(value);
  }

  void onFocusChanged(bool value) {}
  void onTextInputActivated() {}

  void updatePointerOver(bool value) => setValue(isPointerOverProperty, value);
}
