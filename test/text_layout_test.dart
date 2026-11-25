import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('TextLayoutOptions', () {
    const base = TextLayoutOptions(
      text: 'Text',
      fontFamily: 'Arial',
      fontSize: 14,
      maxWidth: 200,
      scale: 1.5,
    );

    test('equal inputs have equal cache keys', () {
      const other = TextLayoutOptions(
        text: 'Text',
        fontFamily: 'Arial',
        fontSize: 14,
        maxWidth: 200,
        scale: 1.5,
      );

      expect(other, equals(base));
      expect(other.hashCode, base.hashCode);
    });

    test('every layout input participates in the cache key', () {
      const variants = [
        TextLayoutOptions(
          text: 'Changed',
          fontFamily: 'Arial',
          fontSize: 14,
          maxWidth: 200,
          scale: 1.5,
        ),
        TextLayoutOptions(
          text: 'Text',
          fontSize: 14,
          maxWidth: 200,
          scale: 1.5,
        ),
        TextLayoutOptions(
          text: 'Text',
          fontFamily: 'Arial',
          fontSize: 16,
          maxWidth: 200,
          scale: 1.5,
        ),
        TextLayoutOptions(
          text: 'Text',
          fontFamily: 'Arial',
          fontSize: 14,
          maxWidth: 300,
          scale: 1.5,
        ),
        TextLayoutOptions(
          text: 'Text',
          fontFamily: 'Arial',
          fontSize: 14,
          maxWidth: 200,
          scale: 2,
        ),
        TextLayoutOptions(
          text: 'Text',
          fontFamily: 'Arial',
          fontSize: 14,
          maxWidth: 200,
          scale: 1.5,
          alignment: TextAlignment.center,
        ),
      ];

      for (final variant in variants) {
        expect(variant, isNot(equals(base)));
      }
    });
  });

  test('TextPosition compares UTF-16 offsets', () {
    expect(const TextPosition(3), const TextPosition(3));
    expect(const TextPosition(3), isNot(const TextPosition(4)));
  });
}
