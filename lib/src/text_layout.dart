import 'drawing.dart';
import 'geometry.dart';

/// A position in a text string, expressed as a UTF-16 code unit offset.
final class TextPosition {
  const TextPosition(this.offset);

  final int offset;

  @override
  bool operator ==(Object other) =>
      other is TextPosition && other.offset == offset;

  @override
  int get hashCode => offset.hashCode;
}

/// Immutable inputs that uniquely identify a cached text layout.
final class TextLayoutOptions {
  const TextLayoutOptions({
    required this.text,
    required this.fontSize,
    required this.maxWidth,
    required this.scale,
    this.fontFamily,
    this.alignment = TextAlignment.start,
    this.direction = FlowDirection.leftToRight,
  });

  final String text;
  final String? fontFamily;
  final double fontSize;
  final double maxWidth;
  final double scale;
  final TextAlignment alignment;

  /// The direction the layout of the text follows.
  ///
  /// The direction decides where the start of the text is, so the logical
  /// alignment follows it.
  final FlowDirection direction;

  @override
  bool operator ==(Object other) =>
      other is TextLayoutOptions &&
      other.text == text &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.maxWidth == maxWidth &&
      other.scale == scale &&
      other.alignment == alignment &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(
        text,
        fontFamily,
        fontSize,
        maxWidth,
        scale,
        alignment,
        direction,
      );
}

/// The alignment of the text as the backend expects it.
///
/// The backends draw the text with an absolute alignment, so the logical
/// alignment is resolved for the direction of the layout: left is 0, center
/// is 1 and right is 2.
int resolveTextAlignment(TextAlignment alignment, FlowDirection direction) {
  return switch (alignment) {
    TextAlignment.start => direction == FlowDirection.rightToLeft ? 2 : 0,
    TextAlignment.center => 1,
    TextAlignment.end => direction == FlowDirection.rightToLeft ? 0 : 2,
  };
}

/// Backend-independent text measurement, drawing and editing geometry.
///
/// Implementations own their native resources. Calling [dispose] releases
/// those resources; all other members throw [StateError] after disposal.
abstract interface class TextLayout {
  double get width;
  double get height;
  double get baseline;
  bool get isDisposed;

  void draw(
    DrawingContext context,
    Point position, {
    Paint paint = const Paint(Color(0xFF000000)),
  });
  TextPosition hitTest(Point position);
  Rect caretRect(int offset);
  List<Rect> selectionRects(int start, int end);

  /// Releases the layout. Safe to call more than once.
  void dispose();
}

abstract interface class TextLayoutFactory {
  /// Creates a layout with a single, explicit owner.
  TextLayout create(TextLayoutOptions options);
}
