import 'dart:ffi';

import 'package:duix/dui.dart';
import 'package:duix/src/native/native_bindings.dart';
import 'package:duix/src/native/sdl_skia_host.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

void main() {
  late NativeBindings bindings;

  setUpAll(() {
    bindings = NativeBindings.open();
  });

  test('ABI version is supported', () {
    expect(bindings.abiVersion(), 1);
  });

  test('host can be created and destroyed repeatedly', () {
    for (var iteration = 0; iteration < 2; iteration++) {
      final host = bindings.hostCreate();
      expect(host, isNot(nullptr), reason: bindings.lastError);
      bindings.hostDestroy(host);
    }
  });

  test('null event arguments return an error', () {
    using((arena) {
      final event = arena<DuiEventStruct>();
      expect(bindings.hostNextEvent(nullptr, event), -1);
      expect(bindings.lastError, contains('Invalid event arguments'));
      expect(bindings.hostWaitEvent(nullptr, event, -1), -1);
      expect(bindings.lastError, contains('Invalid event arguments'));
    });
  });

  test('null frame and metrics arguments return errors', () {
    expect(bindings.windowBeginFrame(nullptr), 0);
    expect(bindings.lastError, isNotEmpty);
    expect(
      () => bindings.pushClipRect(nullptr, 0, 0, 10, 10),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Invalid clip rectangle'),
        ),
      ),
    );
    expect(
      () => bindings.popClip(nullptr),
      throwsA(isA<StateError>()),
    );
    expect(bindings.windowPresent(nullptr), 0);
    expect(bindings.lastError, contains('No active frame'));

    using((arena) {
      expect(
        () => bindings.windowMetrics(nullptr, arena),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Invalid window metrics arguments'),
          ),
        ),
      );
    });
  });

  test('text layout measures Unicode and returns UTF-16 geometry', () {
    using((arena) {
      const text = 'A😀Б';
      final layout = bindings.textLayoutCreate(
        text: text,
        fontSize: 16,
        maxWidth: 240,
        scale: 1.5,
        arena: arena,
      );
      try {
        final metrics = bindings.textLayoutMeasure(layout, arena);
        expect(metrics.width, greaterThan(0));
        expect(metrics.height, greaterThan(0));
        expect(metrics.baseline, greaterThan(0));

        expect(
          bindings.textLayoutHitTest(
            layout,
            metrics.width + 10,
            metrics.height / 2,
            arena,
          ),
          text.length,
        );

        final caret = bindings.textLayoutCaretRect(
          layout,
          text.length,
          arena,
        );
        expect(caret.left, greaterThanOrEqualTo(0));
        expect(caret.height, greaterThan(0));

        final selection = bindings.textLayoutSelectionRects(
          layout,
          1,
          text.length,
          arena,
        );
        expect(selection, isNotEmpty);
        expect(selection.every((rect) => rect.width >= 0), isTrue);
      } finally {
        bindings.textLayoutDestroy(layout);
      }
    });
  });

  test('text layout rejects invalid handles and UTF-16 offsets', () {
    using((arena) {
      expect(
        () => bindings.textLayoutMeasure(nullptr, arena),
        throwsA(isA<StateError>()),
      );
      final layout = bindings.textLayoutCreate(
        text: 'A😀',
        fontSize: 16,
        maxWidth: 240,
        scale: 1,
        arena: arena,
      );
      try {
        expect(
          () => bindings.textLayoutCaretRect(layout, 2, arena),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('UTF-16'),
            ),
          ),
        );
      } finally {
        bindings.textLayoutDestroy(layout);
      }
    });
  });

  test('text layout draws into an active window frame', () {
    final host = bindings.hostCreate();
    expect(host, isNot(nullptr), reason: bindings.lastError);
    if (host == nullptr) return;
    var window = nullptr.cast<DuiWindowOpaque>();
    var layout = nullptr.cast<DuiTextLayoutOpaque>();
    try {
      using((arena) {
        final title = 'Text ABI'.toNativeUtf8(allocator: arena);
        window = bindings.windowCreate(host, title, 160, 80);
        expect(window, isNot(nullptr), reason: bindings.lastError);
        if (window == nullptr) return;
        layout = bindings.textLayoutCreate(
          text: 'ASCII, кириллица',
          fontSize: 16,
          maxWidth: 150,
          scale: 1,
          arena: arena,
        );
        expect(bindings.windowBeginFrame(window), 1,
            reason: bindings.lastError);
        bindings.pushClipRect(window, 4, 4, 40, 24);
        bindings.drawRect(window, 0, 0, 160, 80, 0x5580CFFF);
        bindings.textLayoutDraw(window, layout, 4, 4, 0xFF000000);
        bindings.popClip(window);
        expect(bindings.windowPresent(window), 1, reason: bindings.lastError);
      });
    } finally {
      bindings.textLayoutDestroy(layout);
      bindings.windowDestroy(host, window);
      bindings.hostDestroy(host);
    }
  });

  test('TextBlock uses native measurement, wrapping and drawing', () async {
    final host = await SdlSkiaHost.initialize();
    final text = TextBlock(
      text: 'Native measurement',
      fontSize: 16,
    );
    final window = Window(
      width: 320,
      height: 200,
      content: text,
    );
    try {
      await host.showWindow(window);
      final initialHeight = text.desiredSize.height;
      expect(text.desiredSize.width, greaterThan(0));
      expect(initialHeight, greaterThan(0));

      text.text = 'A much longer native text layout that must wrap';
      window.resize(100, 200);
      host.presentWindow(window);

      expect(text.desiredSize.width, lessThanOrEqualTo(100));
      expect(text.desiredSize.height, greaterThan(initialHeight));
    } finally {
      await host.closeWindow(window);
      host.dispose();
    }
  });

  test('unchanged windows skip render and present until invalidated', () async {
    final host = await SdlSkiaHost.initialize(diagnosticsEnabled: true);
    final text = TextBlock(text: 'Initial');
    final window = Window(width: 320, height: 200, content: text);
    try {
      await host.showWindow(window);
      var diagnostics = host.diagnosticsFor(window)!;
      expect(diagnostics.renderFrameCount, 1);
      expect(diagnostics.presentCount, 1);

      for (var iteration = 0; iteration < 3; iteration++) {
        host.presentWindow(window);
      }
      diagnostics = host.diagnosticsFor(window)!;
      expect(diagnostics.renderFrameCount, 1);
      expect(diagnostics.presentCount, 1);

      text.text = 'Changed';
      host.presentWindow(window);
      diagnostics = host.diagnosticsFor(window)!;
      expect(diagnostics.renderFrameCount, 2);
      expect(diagnostics.presentCount, 2);

      host.presentWindow(window);
      diagnostics = host.diagnosticsFor(window)!;
      expect(diagnostics.renderFrameCount, 2);
      expect(diagnostics.presentCount, 2);
    } finally {
      await host.closeWindow(window);
      host.dispose();
    }
  });

  test('text input ABI rejects null handles and invalid areas', () {
    expect(bindings.windowStartTextInput(nullptr), 0);
    expect(bindings.lastError, contains('Invalid text input window'));
    expect(bindings.windowStopTextInput(nullptr), 0);
    expect(bindings.windowTextInputActive(nullptr), -1);
    expect(bindings.windowSetTextInputArea(nullptr, 0, 0, 10, 20, 0), 0);
    expect(bindings.lastError, contains('Invalid text input area'));
  });

  test('native text input starts, accepts an area and stops', () {
    final host = bindings.hostCreate();
    expect(host, isNot(nullptr), reason: bindings.lastError);
    if (host == nullptr) return;
    var window = nullptr.cast<DuiWindowOpaque>();
    try {
      using((arena) {
        final title = 'Text input ABI'.toNativeUtf8(allocator: arena);
        window = bindings.windowCreate(host, title, 200, 100);
        expect(window, isNot(nullptr), reason: bindings.lastError);
        if (window == nullptr) return;
        expect(bindings.windowTextInputActive(window), 0);
        expect(bindings.windowStartTextInput(window), 1,
            reason: bindings.lastError);
        expect(bindings.windowTextInputActive(window), 1);
        expect(
          bindings.windowSetTextInputArea(window, 8, 7, 120, 20, 24),
          1,
          reason: bindings.lastError,
        );
        expect(bindings.windowStopTextInput(window), 1,
            reason: bindings.lastError);
        expect(bindings.windowTextInputActive(window), 0);
      });
    } finally {
      bindings.windowDestroy(host, window);
      bindings.hostDestroy(host);
    }
  });

  test('TextBox focus and close control real SDL text input', () async {
    final host = await SdlSkiaHost.initialize();
    final box = TextBox(text: 'abc');
    final button = Button();
    final window = Window(
      content: StackPanel(children: [box, button]),
    );
    try {
      await host.showWindow(window);
      expect(host.isTextInputActive(window), isFalse);

      box.focus();
      expect(host.isTextInputActive(window), isTrue);
      box.moveCaret(0);

      button.focus();
      expect(host.isTextInputActive(window), isFalse);
      box.focus();
      expect(host.isTextInputActive(window), isTrue);
    } finally {
      await host.closeWindow(window);
      expect(host.isTextInputActive(window), isFalse);
      host.dispose();
    }
  });

  test('clipboard round-trips Unicode and restores the previous value', () {
    final host = bindings.hostCreate();
    expect(host, isNot(nullptr), reason: bindings.lastError);
    if (host == nullptr) return;
    final previous = bindings.readClipboardText();
    const value = 'Clipboard: ASCII, кириллица, 😀';
    try {
      expect(bindings.writeClipboardText(value), isTrue);
      expect(bindings.readClipboardText(), value);
    } finally {
      if (previous != null) {
        bindings.writeClipboardText(previous);
      } else {
        bindings.writeClipboardText('');
      }
      bindings.hostDestroy(host);
    }
  });

  test('null destruction arguments are ignored', () {
    expect(() => bindings.hostDestroy(nullptr), returnsNormally);
    expect(() => bindings.windowDestroy(nullptr, nullptr), returnsNormally);
    expect(() => bindings.textLayoutDestroy(nullptr), returnsNormally);
  });
}
