import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('TextArea', () {
    test('the text is wrapped into the width of the area', () {
      final area = TextArea(text: 'one two three four', fontSize: 10);

      area.measure(const Size(100, 100));

      // The text does not fit into one line of 84 points, so it is wrapped
      // into two lines of 13 points plus the padding of the area. The widest
      // line holds 13 characters of 6 points.
      expect(area.naturalSize, const Size(94, 34));
      // The area keeps a minimum height, so an empty area stays visible.
      expect(area.desiredSize, const Size(94, 60));
    });

    test('the wrapped text fits into the width that the area shows', () {
      final area = TextArea(text: 'one two three four', fontSize: 10);
      final window = Window(width: 100, height: 200, content: area);
      window.updateLayout();

      // The area shows 84 points of text, so the text is wrapped into two
      // lines of 13 points.
      expect(area.textPart.bounds.width, 84);
      expect(area.layoutForRender(area.text).height, 26);
    });

    test('a long text grows the area down', () {
      final area = TextArea(text: 'one two three four', fontSize: 10);

      area.measure(const Size(100, 100));

      expect(area.naturalSize.height, greaterThan(13 + 8));
    });

    test('Shift+Enter starts a new line and Enter does not', () {
      final area = TextArea(text: 'one');
      final window = Window(width: 200, height: 100, content: area);
      window.updateLayout();
      area.focus();

      window.dispatchKeyDown('enter');
      expect(area.text, 'one');

      window.dispatchKeyDown('enter', shiftPressed: true);
      expect(area.text, 'one\n');
      expect(area.caretOffset, 4);
    });

    test('a click places the caret on the clicked line', () {
      final area = TextArea(text: 'one\ntwo\nthree');
      final window = Window(width: 200, height: 100, content: area);
      window.updateLayout();

      // The text starts at the top of the area, the second line is below it.
      window.dispatchPointerDown(const Point(20, 30));
      window.dispatchPointerUp(const Point(20, 30));

      expect(area.caretOffset, inInclusiveRange(4, 7));
    });

    test('the vertical scroll bar appears when the text does not fit', () {
      final area = TextArea(text: 'one\ntwo\nthree\nfour');
      final window = Window(width: 200, height: 40, content: area);
      window.updateLayout();

      expect(area.isScrollBarVisible, isTrue);
      expect(area.verticalScrollBar.bounds.left, greaterThan(0));
      expect(area.verticalScrollBar.isVisible, isTrue);
    });

    test('the scroll bar is hidden when the text fits', () {
      final area = TextArea(text: 'one');
      final window = Window(width: 200, height: 100, content: area);
      window.updateLayout();

      expect(area.isScrollBarVisible, isFalse);
      expect(area.verticalScrollBar.bounds.width, 0);
    });

    test('the arrows move the caret between the lines', () {
      final area = TextArea(text: 'one\ntwo');
      final window = Window(width: 200, height: 100, content: area);
      window.updateLayout();
      area.focus();
      area.moveCaret(1);

      window.dispatchKeyDown('down');
      expect(area.caretOffset, 5);

      window.dispatchKeyDown('up');
      expect(area.caretOffset, 1);
    });

    test('Home and End move the caret inside the line', () {
      final area = TextArea(text: 'one\ntwo');
      final window = Window(width: 200, height: 100, content: area);
      window.updateLayout();
      area.focus();
      area.moveCaret(5);

      window.dispatchKeyDown('home');
      expect(area.caretOffset, 4);

      window.dispatchKeyDown('end');
      expect(area.caretOffset, 7);
    });

    test('the wheel scrolls the text', () {
      final area = TextArea(text: 'one\ntwo\nthree\nfour');
      final window = Window(width: 200, height: 40, content: area);
      window.updateLayout();

      window.dispatchMouseWheel(const Point(20, 20), deltaY: 1);

      expect(area.verticalOffset, greaterThan(0));
      expect(area.verticalScrollBar.value, area.verticalOffset);
    });

    test('the scroll of the text is limited by the height of the text', () {
      final area = TextArea(text: 'one\ntwo\nthree\nfour');
      final window = Window(width: 200, height: 40, content: area);
      window.updateLayout();

      area.scrollTo(1000);

      expect(area.verticalOffset, lessThan(72.8));
      expect(area.verticalOffset, greaterThan(0));
    });

    test('the scroll follows the caret when it moves', () {
      final area = TextArea(text: 'one\ntwo\nthree\nfour');
      final window = Window(width: 200, height: 40, content: area);
      window.updateLayout();

      area.moveCaret(0);
      window.updateLayout();
      expect(area.verticalOffset, 0);

      area.moveCaret(area.text.length);
      window.updateLayout();
      expect(area.verticalOffset, greaterThan(0));
    });

    test('the scroll of the user is not taken back by the layout', () {
      final area = TextArea(text: 'one\ntwo\nthree\nfour');
      final window = Window(width: 200, height: 40, content: area);
      window.updateLayout();

      area.scrollTo(10);
      window.updateLayout();

      expect(area.verticalOffset, 10);
    });

    test('the text of the area is drawn inside the area', () async {
      final area = TextArea(text: 'one\ntwo');
      final window = Window(width: 200, height: 100, content: area);
      await window.show();
      final renderer = RecordingDrawingContext();

      window.renderFrame(renderer);

      final texts = renderer.commands.whereType<DrawTextCommand>().toList();
      expect(texts, hasLength(2));
      expect(texts.first.position.x, 8);
      expect(texts.last.position.y, greaterThan(texts.first.position.y));
    });

    test('the parts of the area are the text and the scroll bar', () {
      final area = TextArea(text: 'one');

      expect(area.part('text'), isNotNull);
      expect(area.part('verticalScrollBar'), isNotNull);
      expect(area.textPart.logicalParent, area);
    });
  });
}
