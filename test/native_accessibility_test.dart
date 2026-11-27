@Tags(['native'])
library;

import 'package:duix/dui.dart';
import 'package:duix/src/native/native_bindings.dart';
import 'package:duix/src/native/sdl_skia_host.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

const _disabled = 1 << 1;

void main() {
  late NativeBindings bindings;

  setUpAll(() {
    bindings = NativeBindings.open();
  });

  test('the semantics tree is published to the native window', () async {
    final host = await SdlSkiaHost.initialize();
    final button = Button(content: Label(text: 'Action'));
    final window = Window(width: 200, height: 100, content: button);
    try {
      await host.showWindow(window);
      window.updateLayout();
      host.presentWindow(window);

      final pointer = host.nativeHandle(window);
      expect(bindings.windowGetAccessibilityNodeCount(pointer), 1);

      final info = using(
        (arena) => bindings.windowGetAccessibilityNodeInfo(pointer, 0, arena),
      );
      expect(info.role, SemanticsRole.button.index);
      expect(info.parent, -1);
      expect(info.left, closeTo(button.bounds.left, 0.001));
      expect(info.width, closeTo(button.bounds.width, 0.001));
      expect(
        bindings.windowGetAccessibilityNodeName(pointer, 0).toDartString(),
        'Action',
      );
    } finally {
      await host.closeWindow(window);
      host.dispose();
    }
  });

  test('a tree with several nodes keeps the parents', () async {
    final host = await SdlSkiaHost.initialize();
    final window = Window(
      width: 200,
      height: 100,
      content: StackPanel(
        children: [
          Label(text: 'First'),
          Label(text: 'Second'),
        ],
      ),
    );
    try {
      await host.showWindow(window);
      window.updateLayout();
      host.presentWindow(window);

      final pointer = host.nativeHandle(window);
      expect(bindings.windowGetAccessibilityNodeCount(pointer), 3);

      final first = using(
        (arena) => bindings.windowGetAccessibilityNodeInfo(pointer, 1, arena),
      );
      final second = using(
        (arena) => bindings.windowGetAccessibilityNodeInfo(pointer, 2, arena),
      );
      expect(first.role, SemanticsRole.label.index);
      expect(first.parent, 0);
      expect(second.role, SemanticsRole.label.index);
      expect(second.parent, 0);
      expect(
        bindings.windowGetAccessibilityNodeName(pointer, 1).toDartString(),
        'First',
      );
      expect(
        bindings.windowGetAccessibilityNodeName(pointer, 2).toDartString(),
        'Second',
      );
    } finally {
      await host.closeWindow(window);
      host.dispose();
    }
  });

  test('the published tree follows the state of the controls', () async {
    final host = await SdlSkiaHost.initialize();
    final button = Button(content: Label(text: 'Action'))..isEnabled = false;
    final window = Window(width: 200, height: 100, content: button);
    try {
      await host.showWindow(window);
      window.updateLayout();
      host.presentWindow(window);

      final pointer = host.nativeHandle(window);
      final info = using(
        (arena) => bindings.windowGetAccessibilityNodeInfo(pointer, 0, arena),
      );
      expect(info.flags & _disabled, _disabled);
    } finally {
      await host.closeWindow(window);
      host.dispose();
    }
  });
}
