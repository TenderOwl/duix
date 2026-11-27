import 'geometry.dart';

/// The size an element asks for.
///
/// An element reports the smallest size it can work with and the size it
/// would like to have. The size it really gets is the allocated size, which
/// the parent decides between the two. The model follows the widget sizes of
/// GTK, where a widget has a minimum, a natural and an allocated size.
final class SizeRequest {
  const SizeRequest({required this.minimum, required this.natural});

  /// A request without a minimum, so the element can be squeezed to nothing.
  const SizeRequest.natural(this.natural) : minimum = Size.zero;

  /// The smallest size the element can work with.
  ///
  /// A parent reserves this space for the element, as long as the space it
  /// has is enough.
  final Size minimum;

  /// The size the element would like to have.
  final Size natural;

  SizeRequest copyWith({Size? minimum, Size? natural}) {
    return SizeRequest(
      minimum: minimum ?? this.minimum,
      natural: natural ?? this.natural,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SizeRequest &&
      other.minimum == minimum &&
      other.natural == natural;

  @override
  int get hashCode => Object.hash(minimum, natural);

  @override
  String toString() => 'SizeRequest(minimum: $minimum, natural: $natural)';
}
