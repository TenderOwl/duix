import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('Recursive dispose', () {
    test('releases the text layouts owned by the disposed subtree', () async {
      final factory = _CountingTextLayoutFactory();
      final label = Label(text: 'dispose me');
      final panel = StackPanel(children: [label]);
      final window = Window(
        width: 200,
        height: 100,
        textLayoutFactory: factory,
        content: panel,
      );
      await window.show();
      window.renderFrame(RecordingDrawingContext());
      expect(factory.created, isNotEmpty);

      panel.dispose();

      expect(label.isDisposed, isTrue);
      expect(
        factory.created.every((layout) => layout.isDisposed),
        isTrue,
        reason: 'Every layout of the subtree must be released.',
      );
    });

    test('detaches the disposed element from its parent', () {
      final label = Label(text: 'child');
      final panel = StackPanel(children: [label]);
      expect(panel.children, hasLength(1));

      label.dispose();

      expect(panel.children, isEmpty);
      expect(label.logicalParent, isNull);
      expect(label.isDisposed, isTrue);
    });

    test('disposes every descendant of the subtree', () {
      final label = Label(text: 'leaf');
      final inner = StackPanel(children: [label]);
      final outer = StackPanel(children: [inner]);

      outer.dispose();

      expect(outer.isDisposed, isTrue);
      expect(inner.isDisposed, isTrue);
      expect(label.isDisposed, isTrue);
      expect(outer.children, isEmpty);
      expect(inner.children, isEmpty);
    });

    test('is idempotent and releases the resources once', () async {
      final factory = _CountingTextLayoutFactory();
      final label = Label(text: 'once');
      final window = Window(
        width: 200,
        height: 100,
        textLayoutFactory: factory,
        content: label,
      );
      await window.show();
      window.renderFrame(RecordingDrawingContext());
      final layout = factory.created.single;

      label.dispose();
      label.dispose();

      expect(label.isDisposed, isTrue);
      expect(layout.isDisposed, isTrue);
      expect(factory.created, hasLength(1));
    });

    test('unmounts the disposed element and clears the focus', () async {
      final box = TextBox(text: 'focused');
      final button = Button();
      final window = Window(
        width: 200,
        height: 100,
        content: StackPanel(children: [box, button]),
      );
      await window.show();
      box.focus();
      expect(window.focusedElement, same(box));

      box.dispose();

      expect(box.isMounted, isFalse);
      expect(window.focusedElement, isNull);
    });

    test('a disposed element cannot join a tree again', () {
      final label = Label(text: 'gone');
      label.dispose();
      final panel = StackPanel();

      expect(() => panel.children.add(label), throwsStateError);
    });

    test('a disposed element rejects further mutation', () {
      final label = Label(text: 'frozen');

      label.dispose();

      expect(() => label.text = 'changed', throwsStateError);
      expect(label.text, 'frozen');
    });

    test('window dispose releases the content tree', () async {
      final label = Label(text: 'content');
      final window = Window(width: 200, height: 100, content: label);
      await window.show();

      window.dispose();

      expect(window.content, isNull);
      expect(label.isDisposed, isTrue);
    });

    test('closing a window keeps the content alive', () async {
      final label = Label(text: 'reopen');
      final window = Window(width: 200, height: 100, content: label);
      await window.show();

      window.close();

      expect(label.isDisposed, isFalse);
      expect(window.content, same(label));
    });

    test('disposing a content control content detaches it', () {
      final content = Label(text: 'content');
      final control = Border(content: content);

      content.dispose();

      expect(control.content, isNull);
      expect(content.logicalParent, isNull);
      expect(content.isDisposed, isTrue);
    });

    test('disposing an items control releases its containers', () {
      final control = ItemsControl<String>(
        itemsSource: ObservableCollection<String>(['a', 'b', 'c']),
        itemTemplate: (item) => Label(text: item),
      );
      final element = control.elementAt(0)!;
      expect(control.containerCount, 3);

      control.dispose();

      expect(control.containerCount, 0);
      expect(element.isDisposed, isTrue);
      expect(control.isDisposed, isTrue);
    });

    test('disposing a control keeps its template subtree released', () {
      final button = Button();
      final panel = StackPanel(children: [button]);

      button.dispose();

      expect(button.isDisposed, isTrue);
      expect(panel.children, isEmpty);
    });
  });
}

final class _CountingTextLayoutFactory implements TextLayoutFactory {
  static const _headless = HeadlessTextLayoutFactory();

  final created = <TextLayout>[];

  @override
  TextLayout create(TextLayoutOptions options) {
    final layout = _headless.create(options);
    created.add(layout);
    return layout;
  }
}
