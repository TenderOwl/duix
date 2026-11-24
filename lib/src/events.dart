import 'geometry.dart';

enum RoutingStrategy { direct, bubble, tunnel }

final class RoutedEvent<T extends RoutedEventArgs> {
  const RoutedEvent(this.name, this.strategy);

  final String name;
  final RoutingStrategy strategy;
}

abstract class RoutedEventArgs {
  Object? originalSource;
  Object? source;
  bool handled = false;
}

typedef RoutedEventHandler<T extends RoutedEventArgs> = void Function(
  Object sender,
  T args,
);

final class PointerEventArgs extends RoutedEventArgs {
  PointerEventArgs({
    required this.pointerId,
    required this.position,
    this.button = PointerButton.primary,
  });

  final int pointerId;
  final Point position;
  final PointerButton button;
}

enum PointerButton { primary, secondary, middle }

final class KeyEventArgs extends RoutedEventArgs {
  KeyEventArgs(this.key);

  final String key;
}

final class TextInputEventArgs extends RoutedEventArgs {
  TextInputEventArgs(this.text);

  final String text;
}
