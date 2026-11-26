import 'package:duix/dui.dart';
import 'package:test/test.dart';

void main() {
  group('Semantics tree', () {
    test('mirrors the UI tree with roles, names and values', () async {
      final label = Label(text: 'Hello');
      final box = TextBox(text: 'typed');
      final button = Button(content: Label(text: 'OK'));
      final window = Window(
        width: 300,
        height: 200,
        content: StackPanel(children: [label, box, button]),
      );
      await window.show();
      window.updateLayout();

      final tree = window.semanticsTree;
      final roles = tree.nodes.map((node) => node.role).toList();

      expect(roles, contains(SemanticsRole.label));
      expect(roles, contains(SemanticsRole.textBox));
      expect(roles, contains(SemanticsRole.button));
      expect(tree.nodeFor(label)!.name, 'Hello');
      expect(tree.nodeFor(box)!.value, 'typed');
      expect(tree.nodeFor(button)!.name, 'OK');
    });

    test('flattens elements without a role of their own', () async {
      final label = Label(text: 'Hello');
      final window = Window(
        width: 300,
        height: 200,
        content: StackPanel(children: [label]),
      );
      await window.show();
      window.updateLayout();

      final tree = window.semanticsTree;

      expect(
        tree.nodes.where(
          (node) =>
              node.role == SemanticsRole.none && !identical(node, tree.root),
        ),
        isEmpty,
        reason: 'The panel carries no meaning of its own.',
      );
      expect(tree.nodeFor(label), isNotNull);
      expect(tree.root.children, hasLength(1));
    });

    test('reports the focus of the focused control', () async {
      final first = TextBox(text: 'first');
      final second = TextBox(text: 'second');
      final window = Window(
        width: 300,
        height: 200,
        content: StackPanel(children: [first, second]),
      );
      await window.show();
      first.focus();

      final tree = window.semanticsTree;

      expect(tree.nodeFor(first)!.state.focused, isTrue);
      expect(tree.nodeFor(second)!.state.focused, isFalse);

      second.focus();

      final updated = window.semanticsTree;
      expect(updated.nodeFor(first)!.state.focused, isFalse);
      expect(updated.nodeFor(second)!.state.focused, isTrue);
    });

    test('reports the selection of a text control', () async {
      final box = TextBox(text: 'abcdef')
        ..selection = const TextSelection(baseOffset: 1, extentOffset: 4);
      final window = Window(width: 300, height: 200, content: box);
      await window.show();

      final node = window.semanticsTree.nodeFor(box)!;

      expect(node.selectionStart, 1);
      expect(node.selectionEnd, 4);
      expect(node.hasSelection, isTrue);
      expect(node.state.editable, isTrue);
    });

    test('reports a collapsed selection as no selection', () async {
      final box = TextBox(text: 'abcdef')..moveCaret(2);
      final window = Window(width: 300, height: 200, content: box);
      await window.show();

      final node = window.semanticsTree.nodeFor(box)!;

      expect(node.selectionStart, 2);
      expect(node.selectionEnd, 2);
      expect(node.hasSelection, isFalse);
    });

    test('reports the disabled state', () async {
      final button = Button(content: Label(text: 'OK'))..isEnabled = false;
      final window = Window(width: 300, height: 200, content: button);
      await window.show();

      expect(window.semanticsTree.nodeFor(button)!.state.disabled, isTrue);
    });

    test('reports the bounds of the element', () async {
      final label = Label(text: 'Hello');
      final window = Window(
        width: 300,
        height: 200,
        content: StackPanel(children: [label]),
      );
      await window.show();
      window.updateLayout();

      final node = window.semanticsTree.nodeFor(label)!;

      expect(node.bounds, label.bounds);
      expect(node.bounds.width, greaterThan(0));
    });

    test('a control absorbs the label of its content', () async {
      final content = Label(text: 'Save');
      final button = Button(content: content);
      final window = Window(width: 300, height: 200, content: button);
      await window.show();
      window.updateLayout();

      final tree = window.semanticsTree;
      final buttonNode = tree.nodeFor(button)!;

      expect(buttonNode.name, 'Save');
      expect(
        buttonNode.children.where((node) => node.role == SemanticsRole.label),
        isEmpty,
        reason: 'The button already exposes the label as its name.',
      );
    });

    test('reports an items control as a list', () {
      final control = ItemsControl<String>(
        itemsSource: ObservableCollection<String>(['a', 'b']),
        itemTemplate: (item) => Label(text: item),
      );

      final tree = SemanticsTree.fromElement(control);

      expect(tree.nodeFor(control)!.role, SemanticsRole.list);
      expect(tree.nodeFor(control)!.children, hasLength(2));
      expect(
        tree.nodeFor(control)!.children.map((node) => node.name),
        ['a', 'b'],
      );
    });

    test('an empty window has an empty tree', () {
      final window = Window();

      final tree = window.semanticsTree;

      expect(tree.nodes, hasLength(1));
      expect(tree.root.role, SemanticsRole.none);
      expect(tree.root.children, isEmpty);
    });

    test('a disposed control is not part of the tree', () async {
      final label = Label(text: 'Hello');
      final window = Window(
        width: 300,
        height: 200,
        content: StackPanel(children: [label]),
      );
      await window.show();

      label.dispose();

      expect(window.semanticsTree.nodeFor(label), isNull);
    });
  });
}
