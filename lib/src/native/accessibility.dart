import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../semantics.dart';
import 'native_bindings.dart';

/// The state flags of an accessible node.
///
/// The values match the `DuiAccessibleFlags` of the native ABI.
const _focused = 1 << 0;
const _disabled = 1 << 1;
const _readOnly = 1 << 2;
const _editable = 1 << 3;
const _multiline = 1 << 4;
const _selected = 1 << 5;
const _checked = 1 << 6;
const _indeterminate = 1 << 7;
const _expanded = 1 << 8;
const _pressed = 1 << 9;

/// Publishes the semantics tree of a window to the native layer.
///
/// The native layer keeps the tree, so a platform bridge can serve it to the
/// assistive technologies of the system. The nodes are sent in the order of
/// the tree, and every node points at the index of its parent.
void publishAccessibilityTree(
  NativeBindings bindings,
  Pointer<DuiWindowOpaque> window,
  SemanticsTree tree,
) {
  final entries = _flatten(tree.root);
  if (entries.isEmpty) {
    bindings.windowSetAccessibilityTree(window, nullptr, 0);
    return;
  }
  using((arena) {
    final array = arena<DuiAccessibleNodeStruct>(entries.length);
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final node = entry.node;
      final value = array[index];
      value.structSize = sizeOf<DuiAccessibleNodeStruct>();
      value.role = node.role.index;
      value.parent = entry.parent;
      value.flags = _flags(node.state);
      value.left = node.bounds.left;
      value.top = node.bounds.top;
      value.width = node.bounds.width;
      value.height = node.bounds.height;
      value.nameUtf8 = node.name.toNativeUtf8(allocator: arena);
      value.valueUtf8 = node.value.toNativeUtf8(allocator: arena);
    }
    bindings.windowSetAccessibilityTree(window, array, entries.length);
  });
}

List<({SemanticsNode node, int parent})> _flatten(SemanticsNode root) {
  final result = <({SemanticsNode node, int parent})>[];
  void visit(SemanticsNode node, int parent) {
    final index = result.length;
    result.add((node: node, parent: parent));
    for (final child in node.children) {
      visit(child, index);
    }
  }

  visit(root, -1);
  return result;
}

int _flags(SemanticsState state) {
  var flags = 0;
  if (state.focused) flags |= _focused;
  if (state.disabled) flags |= _disabled;
  if (state.readOnly) flags |= _readOnly;
  if (state.editable) flags |= _editable;
  if (state.multiline) flags |= _multiline;
  if (state.selected) flags |= _selected;
  if (state.checked) flags |= _checked;
  if (state.indeterminate) flags |= _indeterminate;
  if (state.expanded) flags |= _expanded;
  if (state.pressed) flags |= _pressed;
  return flags;
}
