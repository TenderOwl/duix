@Tags(['native'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:duix/dui.dart';
import 'package:duix/src/native/native_bindings.dart';
import 'package:duix/src/native/sdl_skia_host.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

late NativeBindings bindings;

/// Tag for tests that drive the real system clipboard.
///
/// These tests fail when another process holds the Windows clipboard, so they
/// are excluded with `dart test --exclude-tags clipboard`.
const _nativeClipboardTag = 'clipboard';

/// The event type of a resized window in the native ABI.
const _windowResizedEvent = 3;

/// Allocates a native paint for the drawing calls of the ABI.
Pointer<DuiPaintStruct> _paint(
  int rgba, {
  double strokeWidth = 0,
  double opacity = 1,
  int blendMode = 0,
  int shadowRgba = 0,
  double shadowBlur = 0,
  double shadowDx = 0,
  double shadowDy = 0,
}) {
  final paint = calloc<DuiPaintStruct>();
  paint.ref
    ..structSize = sizeOf<DuiPaintStruct>()
    ..rgba = rgba
    ..strokeWidth = strokeWidth
    ..opacity = opacity
    ..blendMode = blendMode
    ..shadowRgba = shadowRgba
    ..shadowBlur = shadowBlur
    ..shadowDx = shadowDx
    ..shadowDy = shadowDy;
  return paint;
}

void main() {
  setUpAll(() {
    bindings = NativeBindings.open();
  });

  test('ABI version is supported', () {
    expect(bindings.abiVersion(), 5);
  });

  test('host can be created and destroyed repeatedly', () {
    for (var iteration = 0; iteration < 2; iteration++) {
      final host = bindings.hostCreate();
      expect(host, isNot(nullptr), reason: bindings.lastError);
      bindings.hostDestroy(host);
    }
  });

  test('live resize callback can render while the window is resized', () async {
    final host = bindings.hostCreate();
    expect(host, isNot(nullptr), reason: bindings.lastError);
    if (host == nullptr) return;

    var window = nullptr.cast<DuiWindowOpaque>();
    NativeCallable<LiveResizeCallbackNative>? callback;
    var callbackCount = 0;
    final frameResults = <int>[];
    final callbackSizes = <Size>[];
    try {
      using((arena) {
        window = bindings.windowCreate(
          host,
          'Live resize'.toNativeUtf8(allocator: arena),
          160,
          80,
        );
      });
      expect(window, isNot(nullptr), reason: bindings.lastError);
      if (window == nullptr) return;

      callback = NativeCallable<LiveResizeCallbackNative>.isolateLocal((
        Pointer<Void> userData,
        int windowId,
        double width,
        double height,
      ) {
        callbackCount++;
        callbackSizes.add(Size(width, height));
        frameResults.add(bindings.windowBeginFrame(window));
        frameResults.add(bindings.windowPresent(window));
      });
      expect(
        bindings.hostSetLiveResizeCallback(
          host,
          callback.nativeFunction,
          nullptr,
        ),
        1,
      );

      final initialMetrics = using(
        (arena) => bindings.windowMetrics(window, arena),
      );
      expect(bindings.windowSetSize(window, 240, 120), 1);
      // On Windows the resize event is delivered inside the call, on the other
      // systems the window system delivers it later, so the event queue is
      // pumped until the resize arrives.
      var resizeEvents = 0;
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (callbackCount == 0 &&
          resizeEvents == 0 &&
          DateTime.now().isBefore(deadline)) {
        using((arena) {
          final event = bindings.nextEvent(host, arena);
          if (event != null && event.type == _windowResizedEvent) {
            resizeEvents++;
          }
        });
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      if (callbackCount == 0 && resizeEvents == 0) {
        markTestSkipped(
          'The window system did not deliver a resize event.',
        );
        return;
      }
      expect(
        callbackCount,
        greaterThan(0),
        reason: 'The callback must run when the window is resized.',
      );
      expect(
        callbackSizes.every((size) => size.width > 0 && size.height > 0),
        isTrue,
      );
      expect(
        callbackSizes.any(
          (size) =>
              (size.width - 240).abs() < 0.01 &&
              (size.height - 120).abs() < 0.01,
        ),
        isTrue,
        reason: 'Pixel-size events must report logical window units.',
      );
      final resizedMetrics = using(
        (arena) => bindings.windowMetrics(window, arena),
      );
      expect(resizedMetrics.physicalWidth,
          greaterThan(initialMetrics.physicalWidth));
      expect(resizedMetrics.physicalHeight,
          greaterThan(initialMetrics.physicalHeight));
      expect(frameResults, everyElement(1), reason: bindings.lastError);
      expect(bindings.hostSetLiveResizeCallback(nullptr, nullptr, nullptr), 0);
    } finally {
      if (host != nullptr) {
        bindings.hostSetLiveResizeCallback(host, nullptr, nullptr);
      }
      callback?.close();
      bindings.windowDestroy(host, window);
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
      expect(bindings.hostWakeUp(nullptr), 0);
      expect(bindings.lastError, contains('Invalid host'));
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
        final fill = _paint(0x5580CFFF);
        final stroke = _paint(0x880087DB, strokeWidth: 2);
        final line = _paint(0xFF00FF00, strokeWidth: 3);
        try {
          bindings.drawRect(window, 0, 0, 160, 80, fill);
          bindings.drawRoundedRect(
            window,
            4,
            4,
            80,
            32,
            16,
            16,
            stroke,
          );
          bindings.drawLine(window, 4, 40, 84, 40, line);
        } finally {
          calloc.free(fill);
          calloc.free(stroke);
          calloc.free(line);
        }
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

  test('text drawing uses the same shaped metrics as the text layout', () {
    final host = bindings.hostCreate();
    expect(host, isNot(nullptr), reason: bindings.lastError);
    if (host == nullptr) return;
    var window = nullptr.cast<DuiWindowOpaque>();
    try {
      using((arena) {
        const text = 'Native measurement';
        const fontSize = 16.0;
        final title = 'Text draw'.toNativeUtf8(allocator: arena);
        window = bindings.windowCreate(host, title, 160, 80);
        expect(window, isNot(nullptr), reason: bindings.lastError);
        if (window == nullptr) return;
        expect(bindings.windowBeginFrame(window), 1,
            reason: bindings.lastError);

        final scale = bindings.windowGetContentScale(window);
        expect(scale, greaterThan(0));
        final nativeText = text.toNativeUtf8(allocator: arena);
        final drawnWidth = bindings.drawText(
          window,
          nativeText,
          8,
          8,
          fontSize,
          0xFF000000,
          0,
        );
        expect(drawnWidth, greaterThan(0));

        final layout = bindings.textLayoutCreate(
          text: text,
          fontSize: fontSize,
          maxWidth: 100000,
          scale: scale,
          arena: arena,
        );
        try {
          final metrics = bindings.textLayoutMeasure(layout, arena);
          expect(drawnWidth, closeTo(metrics.width, 0.001));
        } finally {
          bindings.textLayoutDestroy(layout);
        }
        expect(bindings.windowPresent(window), 1, reason: bindings.lastError);
      });
    } finally {
      bindings.windowDestroy(host, window);
      bindings.hostDestroy(host);
    }
  });

  test('text drawing accepts Unicode and every alignment', () {
    final host = bindings.hostCreate();
    expect(host, isNot(nullptr), reason: bindings.lastError);
    if (host == nullptr) return;
    var window = nullptr.cast<DuiWindowOpaque>();
    try {
      using((arena) {
        const texts = ['ASCII', 'Кириллица', '😀 emoji', 'مرحبا'];
        final title = 'Text draw'.toNativeUtf8(allocator: arena);
        window = bindings.windowCreate(host, title, 160, 80);
        expect(window, isNot(nullptr), reason: bindings.lastError);
        if (window == nullptr) return;
        expect(bindings.windowBeginFrame(window), 1,
            reason: bindings.lastError);

        for (final alignment in [0, 1, 2]) {
          for (final text in texts) {
            final nativeText = text.toNativeUtf8(allocator: arena);
            final width = bindings.drawText(
              window,
              nativeText,
              80,
              8,
              14,
              0xFFFFFFFF,
              alignment,
            );
            expect(width, greaterThan(0), reason: 'Failed to draw "$text".');
          }
        }
        expect(bindings.windowPresent(window), 1, reason: bindings.lastError);
      });
    } finally {
      bindings.windowDestroy(host, window);
      bindings.hostDestroy(host);
    }
  });

  test('Label uses native measurement, wrapping and drawing', () async {
    final host = await SdlSkiaHost.initialize();
    final text = Label(
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

  test('TextBox measures with native text metrics', () async {
    final host = await SdlSkiaHost.initialize();
    final box = TextBox(text: 'Native measurement', fontSize: 16);
    final label = Label(text: 'Native measurement', fontSize: 16);
    final window = Window(
      width: 320,
      height: 200,
      content: StackPanel(children: [box, label]),
    );
    try {
      await host.showWindow(window);

      expect(label.desiredSize.width, greaterThan(0));
      expect(
        box.desiredSize.width,
        closeTo(label.desiredSize.width + 16, 0.001),
      );
      expect(box.desiredSize.height, greaterThan(label.desiredSize.height));

      box.text = 'A much longer native text layout';
      window.updateLayout();
      expect(box.desiredSize.width, greaterThan(label.desiredSize.width + 16));
    } finally {
      await host.closeWindow(window);
      host.dispose();
    }
  });

  test('unchanged windows skip render and present until invalidated', () async {
    final host = await SdlSkiaHost.initialize(diagnosticsEnabled: true);
    final text = Label(text: 'Initial');
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

  test('diagnostics FPS follows presented frames without extra rendering',
      () async {
    final host = await SdlSkiaHost.initialize(diagnosticsEnabled: true);
    final text = Label(text: 'Initial');
    final window = Window(width: 320, height: 200, content: text);
    try {
      await host.showWindow(window);
      var diagnostics = host.diagnosticsFor(window)!;
      expect(diagnostics.presentCount, 1);
      expect(diagnostics.framesPerSecond, isNull);

      await Future<void>.delayed(const Duration(milliseconds: 550));
      host.presentWindow(window);
      diagnostics = host.diagnosticsFor(window)!;
      expect(diagnostics.presentCount, 1);
      expect(diagnostics.framesPerSecond, isNull);

      text.text = 'Changed';
      host.presentWindow(window);
      diagnostics = host.diagnosticsFor(window)!;
      expect(diagnostics.presentCount, 2);
      expect(diagnostics.framesPerSecond, greaterThan(0));

      final sampledFps = diagnostics.framesPerSecond;
      host.presentWindow(window);
      diagnostics = host.diagnosticsFor(window)!;
      expect(diagnostics.presentCount, 2);
      expect(diagnostics.framesPerSecond, sampledFps);
    } finally {
      await host.closeWindow(window);
      host.dispose();
    }
  });

  test('async Dart invalidation wakes the scheduler and renders one frame',
      () async {
    final host = await SdlSkiaHost.initialize(diagnosticsEnabled: true);
    final text = Label(text: 'Initial');
    final window = Window(width: 320, height: 200, content: text);
    try {
      await host.showWindow(window);
      host.pumpEvents();
      host.presentWindow(window);
      var diagnostics = host.diagnosticsFor(window)!;
      final scheduledBaseline = diagnostics.scheduledFrameCount;
      final layoutBaseline = diagnostics.layoutPassCount;
      final paintBaseline = diagnostics.paintPassCount;
      final presentBaseline = diagnostics.presentCount;

      Timer(const Duration(milliseconds: 10), () => text.text = 'Async');
      // The timer needs real time to fire, so the loop waits for the clock
      // instead of counting iterations: on a platform without a window
      // manager the event wait returns at once, and a count of iterations
      // would finish before the timer is due.
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (text.text == 'Initial' && DateTime.now().isBefore(deadline)) {
        host.waitForEvent(
          window,
          timeout: const Duration(milliseconds: 2),
        );
        host.presentWindow(window);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final frameDeadline = DateTime.now().add(const Duration(seconds: 5));
      while (window.frameScheduled && DateTime.now().isBefore(frameDeadline)) {
        host.presentWindow(window);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(text.text, 'Async');
      diagnostics = host.diagnosticsFor(window)!;
      expect(diagnostics.scheduledFrameCount, scheduledBaseline + 1);
      expect(diagnostics.layoutPassCount, layoutBaseline + 1);
      expect(diagnostics.paintPassCount, paintBaseline + 1);
      expect(diagnostics.presentCount, presentBaseline + 1);
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
    final previous = _captureNativeClipboard();
    const value = 'Clipboard: ASCII, кириллица, 😀';
    try {
      expect(bindings.writeClipboardText(value), isTrue);
      expect(bindings.readClipboardText(), value);
    } finally {
      // The host is destroyed first: a failing clipboard restore must
      // not leak it, because the process allows only one host at a time.
      bindings.hostDestroy(host);
      _restoreNativeClipboard(previous);
    }
  }, tags: _nativeClipboardTag);

  test('formatted clipboard round-trips text, HTML and binary data', () {
    final host = bindings.hostCreate();
    expect(host, isNot(nullptr), reason: bindings.lastError);
    if (host == nullptr) return;
    final previous = _captureNativeClipboard();
    const text = 'Formatted: кириллица, 😀';
    const html = '<strong>Привет, 😀</strong>';
    const binary = <int>[0, 1, 2, 0, 127, 128, 255];
    try {
      expect(
        bindings.writeClipboardData({
          'text/plain': utf8.encode(text),
          'text/html': utf8.encode(html),
          'application/xhtml+xml': utf8.encode(html),
          'application/x-duix-binary': binary,
          'application/x-duix-empty': const <int>[],
        }),
        isTrue,
      );

      expect(bindings.hasClipboardData('text/html'), isTrue);
      expect(bindings.hasClipboardData('application/xhtml+xml'), isTrue);
      expect(bindings.hasClipboardData('image/png'), isFalse);
      expect(utf8.decode(bindings.readClipboardData('text/plain')!), text);
      expect(utf8.decode(bindings.readClipboardData('text/html')!), html);
      expect(utf8.decode(bindings.readClipboardData('application/xhtml+xml')!),
          html);
      expect(bindings.readClipboardData('application/x-duix-binary'), binary);
      expect(bindings.readClipboardData('application/x-duix-empty'), isEmpty);
      expect(bindings.readClipboardData('image/png'), isNull);
      expect(bindings.readClipboardText(), text);

      expect(
        bindings.writeClipboardData({'text/html': utf8.encode(html)}),
        isTrue,
      );
      expect(bindings.hasClipboardData('text/html'), isTrue);
      expect(utf8.decode(bindings.readClipboardData('text/html')!), html);

      expect(
        bindings.writeClipboardData({'text/html': const <int>[]}),
        isTrue,
      );
      expect(bindings.hasClipboardData('text/html'), isTrue);
      expect(bindings.readClipboardData('text/html'), isEmpty);
    } finally {
      // The host is destroyed first: a failing clipboard restore must
      // not leak it, because the process allows only one host at a time.
      bindings.hostDestroy(host);
      _restoreNativeClipboard(previous);
    }
  }, tags: _nativeClipboardTag);

  test('clipboard snapshot restores all MIME formats and empty state', () {
    final host = bindings.hostCreate();
    expect(host, isNot(nullptr), reason: bindings.lastError);
    if (host == nullptr) return;
    final previous = _captureNativeClipboard();
    final seed = <String, List<int>>{
      ClipboardMimeTypes.plainText: utf8.encode('Original text 😀'),
      ClipboardMimeTypes.html: utf8.encode('<b>Original HTML 😀</b>'),
      'application/xhtml+xml': utf8.encode('<b>Original XHTML</b>'),
      'application/x-duix-binary': const <int>[0, 4, 0, 255],
      'application/x-duix-empty': const <int>[],
    };
    try {
      bindings.writeClipboardData(seed);
      expect(bindings.readClipboardMimeTypes().toSet(), seed.keys.toSet());
      final snapshot = _captureNativeClipboard();
      expect(snapshot, seed);

      bindings.writeClipboardText('Replacement');
      _restoreNativeClipboard(snapshot);
      expect(_captureNativeClipboard(), snapshot);

      expect(bindings.clearClipboard(), isTrue);
      expect(bindings.readClipboardMimeTypes(), isEmpty);
      _restoreNativeClipboard(snapshot);
      expect(_captureNativeClipboard(), snapshot);
    } finally {
      // The host is destroyed first: a failing clipboard restore must
      // not leak it, because the process allows only one host at a time.
      bindings.hostDestroy(host);
      _restoreNativeClipboard(previous);
    }
  }, tags: _nativeClipboardTag);

  test('native backend works through the public Window clipboard API',
      () async {
    final host = await SdlSkiaHost.initialize();
    final window = Window()..clipboardHandler = host;
    final previous = _capturePublicClipboard(host);
    const text = 'Public API: кириллица, 😀';
    const html = '<em>Public API: кириллица, 😀</em>';
    try {
      expect(
        window.writeClipboardData(<String, List<int>>{
          ClipboardMimeTypes.plainText: utf8.encode(text),
          ClipboardMimeTypes.html: utf8.encode(html),
        }),
        isTrue,
      );
      expect(window.hasClipboardData(ClipboardMimeTypes.html), isTrue);
      expect(
        utf8.decode(window.readClipboardData(ClipboardMimeTypes.html)!),
        html,
      );
      expect(window.readClipboardText(), text);
    } finally {
      try {
        _restorePublicClipboard(host, previous);
      } finally {
        host.dispose();
      }
    }
  }, tags: _nativeClipboardTag);

  test('null destruction arguments are ignored', () {
    expect(() => bindings.hostDestroy(nullptr), returnsNormally);
    expect(() => bindings.windowDestroy(nullptr, nullptr), returnsNormally);
    expect(() => bindings.textLayoutDestroy(nullptr), returnsNormally);
  });
}

Map<String, List<int>> _captureNativeClipboard() {
  final snapshot = <String, List<int>>{};
  for (final mimeType in bindings.readClipboardMimeTypes()) {
    final data = bindings.readClipboardData(mimeType);
    if (data == null) {
      throw StateError(
          'Clipboard format disappeared during capture: $mimeType');
    }
    snapshot[mimeType] = data;
  }
  return snapshot;
}

void _restoreNativeClipboard(Map<String, List<int>> snapshot) {
  if (snapshot.isEmpty) {
    bindings.clearClipboard();
  } else {
    bindings.writeClipboardData(snapshot);
  }
}

Map<String, List<int>> _capturePublicClipboard(ClipboardHandler clipboard) {
  final snapshot = <String, List<int>>{};
  for (final mimeType in clipboard.readClipboardMimeTypes()) {
    final data = clipboard.readClipboardData(mimeType);
    if (data == null) {
      throw StateError(
          'Clipboard format disappeared during capture: $mimeType');
    }
    snapshot[mimeType] = data;
  }
  return snapshot;
}

void _restorePublicClipboard(
  ClipboardHandler clipboard,
  Map<String, List<int>> snapshot,
) {
  if (snapshot.isEmpty) {
    clipboard.clearClipboard();
  } else {
    clipboard.writeClipboardData(snapshot);
  }
}
