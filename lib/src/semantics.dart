import 'geometry.dart';
import 'ui_element.dart';

/// The role of an element for assistive technologies.
enum SemanticsRole {
  /// The element carries no meaning of its own and is flattened away.
  none,

  button,
  textBox,
  label,
  group,
  list,
  image,
  window,

  /// The element is a box that can be checked.
  ///
  /// The role stands at the end of the enum, because the index of a role
  /// crosses the native ABI: the numbers of the roles that are already in the
  /// tree must not change.
  checkBox,

  /// The element is a button of a group, where one button is checked at a
  /// time.
  radioButton,
}

/// The state of an element for assistive technologies.
final class SemanticsState {
  const SemanticsState({
    this.focused = false,
    this.disabled = false,
    this.readOnly = false,
    this.editable = false,
    this.multiline = false,
    this.selected = false,
    this.checked = false,
    this.indeterminate = false,
    this.expanded = false,
    this.pressed = false,
  });

  /// The element holds the keyboard focus.
  final bool focused;

  /// The element cannot be used.
  final bool disabled;

  /// The value of the element cannot be changed.
  final bool readOnly;

  /// The value of the element can be changed.
  final bool editable;

  /// The element edits multiple lines.
  final bool multiline;

  /// The element is selected.
  final bool selected;

  /// The element is checked.
  final bool checked;

  /// The element is in an indeterminate check state.
  final bool indeterminate;

  /// The element is expanded.
  final bool expanded;

  /// The element is pressed.
  final bool pressed;

  @override
  bool operator ==(Object other) =>
      other is SemanticsState &&
      other.focused == focused &&
      other.disabled == disabled &&
      other.readOnly == readOnly &&
      other.editable == editable &&
      other.multiline == multiline &&
      other.selected == selected &&
      other.checked == checked &&
      other.indeterminate == indeterminate &&
      other.expanded == expanded &&
      other.pressed == pressed;

  @override
  int get hashCode => Object.hash(
        focused,
        disabled,
        readOnly,
        editable,
        multiline,
        selected,
        checked,
        indeterminate,
        expanded,
        pressed,
      );
}

/// A snapshot of one element for assistive technologies.
///
/// The node keeps a reference to the element it was built from, so a platform
/// bridge can map a native accessibility object back to the control.
final class SemanticsNode {
  SemanticsNode({
    required this.element,
    required this.role,
    required this.name,
    required this.value,
    required this.state,
    required this.bounds,
    required this.children,
    this.selectionStart,
    this.selectionEnd,
  });

  /// The element the node was built from.
  final UIElement element;

  /// The role of the element.
  final SemanticsRole role;

  /// The accessible name of the element.
  final String name;

  /// The accessible value of the element.
  final String value;

  /// The accessible state of the element.
  final SemanticsState state;

  /// The bounds of the element in logical units.
  final Rect bounds;

  /// The child nodes.
  final List<SemanticsNode> children;

  /// The start of the selected range, if the element has a selection.
  final int? selectionStart;

  /// The end of the selected range, if the element has a selection.
  final int? selectionEnd;

  /// Whether the element holds a non empty selection.
  bool get hasSelection =>
      selectionStart != null &&
      selectionEnd != null &&
      selectionStart != selectionEnd;

  @override
  String toString() => 'SemanticsNode(${role.name}, name: "$name", '
      'value: "$value", children: ${children.length})';
}

/// A snapshot of the semantics of a UI tree.
///
/// The tree is built on demand: every element contributes its role, name,
/// value, state and bounds, and the focus and the selection are read at the
/// moment of the build. Platform bridges rebuild the tree when they need a
/// fresh snapshot.
final class SemanticsTree {
  SemanticsTree._(this.root);

  /// Builds a snapshot of the semantics of [element] and its descendants.
  factory SemanticsTree.fromElement(UIElement element) =>
      SemanticsTree._(_build(element));

  /// Builds an empty tree.
  factory SemanticsTree.empty() => SemanticsTree._(
        SemanticsNode(
          element: _NullElement.instance,
          role: SemanticsRole.none,
          name: '',
          value: '',
          state: const SemanticsState(),
          bounds: Rect.zero,
          children: const [],
        ),
      );

  /// The root node of the tree.
  final SemanticsNode root;

  /// All nodes of the tree, the root first.
  List<SemanticsNode> get nodes => _flatten(root);

  /// The node of [element], if the element is part of the tree.
  SemanticsNode? nodeFor(UIElement element) {
    for (final node in nodes) {
      if (identical(node.element, element)) return node;
    }
    return null;
  }

  static List<SemanticsNode> _flatten(SemanticsNode node) {
    final result = <SemanticsNode>[node];
    for (final child in node.children) {
      result.addAll(_flatten(child));
    }
    return result;
  }

  static SemanticsNode _build(UIElement element) {
    final children = <SemanticsNode>[];
    for (final child in element.logicalChildren) {
      final node = _build(child);
      if (node.role == SemanticsRole.none) {
        // An element without a meaning of its own is flattened away and its
        // children move up to the parent.
        children.addAll(node.children);
        continue;
      }
      final parentRole = element.semanticsRole;
      if (node.role == SemanticsRole.label &&
          parentRole != SemanticsRole.none &&
          element.semanticsName.isNotEmpty) {
        // The parent already exposes this label as its accessible name.
        continue;
      }
      children.add(node);
    }
    final selection = element.semanticsSelection;
    return SemanticsNode(
      element: element,
      role: element.semanticsRole,
      name: element.semanticsName,
      value: element.semanticsValue,
      state: element.semanticsState,
      bounds: element.bounds,
      children: children,
      selectionStart: selection?.$1,
      selectionEnd: selection?.$2,
    );
  }
}

/// Placeholder element for an empty semantics tree.
final class _NullElement extends UIElement {
  static final _NullElement instance = _NullElement();

  @override
  Size measureCore(Size availableSize) => Size.zero;
}
