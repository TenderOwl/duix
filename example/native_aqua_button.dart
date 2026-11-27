import 'dart:async';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';

const _aquaNormal = Color(0xFF087FDB);
const _aquaHover = Color(0xFF1698EE);
const _aquaPressed = Color(0xFF0064B4);
const _aquaBorder = Color(0xFF07558F);
const _aquaGloss = Color(0x88FFFFFF);
const _aquaInnerHighlight = Color(0x66C9EEFF);

Future<void> main(List<String> args) async {
  final host = await SdlSkiaHost.initialize(
    diagnosticsEnabled: args.contains('--diagnostics'),
  );
  final clicks = ObservableValue<int>(0);
  late _AquaSurface aquaSurface;

  final aquaTemplate = ControlTemplate<Button>((control) {
    aquaSurface = _AquaSurface(content: ContentPresenter(control))
      ..bind(
        _AquaSurface.colorProperty,
        _combine2(
          control.propertyBinding<bool>(Control.isPressedProperty),
          control.propertyBinding<bool>(Control.isPointerOverProperty),
          (bool pressed, bool hovered) => pressed
              ? _aquaPressed
              : hovered
                  ? _aquaHover
                  : _aquaNormal,
        ),
      );
    return aquaSurface;
  }, focusRingShape: FocusRingShape.capsule);

  final button = Button(
    content: Label(
      text: 'Продолжить',
      fontSize: 16,
      color: Color.white,
      alignment: TextAlignment.center,
    ),
    onClick: () => clicks.value++,
  )
    ..style = Style<Button>(
      name: 'Aqua',
      setters: [DuiSetter(Button.templateProperty, aquaTemplate)],
    )
    ..horizontalAlignment = HorizontalAlignment.center;
  final status = Label(fontSize: 16)
    ..bind(
      Label.textProperty,
      clicks.map((value) => 'Нажатий: $value').asBinding(),
    );
  final window = Window(
    title: 'DUI — Aqua Button',
    width: 520,
    height: 320,
    background: const Color(0xFFF5F5F7),
    content: StackPanel(
      spacing: 18,
      padding: const EdgeInsets.all(32),
      children: [
        Label(text: 'Aqua', fontSize: 30),
        Label(
          text:
              'Persistent ControlTemplate с hover, pressed и focus-состояниями.',
        ),
        button,
        status,
        Label(
          text: 'Tab — фокус, Space/Enter — активация.',
          color: const Color(0xFF666666),
        ),
      ],
    ),
  );

  final application = Application(host: host);
  try {
    if (args.contains('--smoke')) {
      await host.showWindow(window);
      window.updateLayout();
      final templateRoot = button.templateRoot;
      final position = Point(
        button.bounds.left + button.bounds.width / 2,
        button.bounds.top + button.bounds.height / 2,
      );

      window.dispatchPointerMove(position);
      if (!button.isPointerOver || aquaSurface.color != _aquaHover) {
        throw StateError('Aqua hover state was not applied.');
      }
      window.dispatchPointerDown(position);
      if (!button.isPressed || aquaSurface.color != _aquaPressed) {
        throw StateError('Aqua pressed state was not applied.');
      }
      window.dispatchPointerUp(position);
      if (clicks.value != 1 || aquaSurface.color != _aquaHover) {
        throw StateError('Aqua button did not activate correctly.');
      }
      window.dispatchPointerMove(const Point(4, 4));
      if (button.isPointerOver || aquaSurface.color != _aquaNormal) {
        throw StateError('Aqua hover state was not cleared.');
      }
      window.dispatchKeyDown('space');
      if (clicks.value != 2 || !identical(templateRoot, button.templateRoot)) {
        throw StateError('Aqua template lost identity or keyboard activation.');
      }

      for (var frame = 0; frame < 3 && host.isOpen(window); frame++) {
        host.pumpEvents();
        host.presentWindow(window);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      final diagnostics = host.diagnosticsFor(window);
      if (diagnostics != null) print(diagnostics);
      print('Native Aqua button smoke passed: 3 frames rendered.');
    } else {
      await application.run(window);
    }
  } finally {
    host.dispose();
  }
}

final class _AquaSurface extends ContentControl {
  _AquaSurface({super.content});

  static const colorProperty = DuiProperty<_AquaSurface, Color>(
    name: 'color',
    defaultValue: _aquaNormal,
    affectsPaint: true,
  );
  static const _padding = EdgeInsets.symmetric(horizontal: 20, vertical: 10);

  Color get color => getValue(colorProperty);

  @override
  bool get isFocusable => false;

  @override
  Size measureContentCore(Size availableSize) {
    final inner = Size(
      (availableSize.width - _padding.horizontal).clamp(0, double.infinity),
      (availableSize.height - _padding.vertical).clamp(0, double.infinity),
    );
    return _padding.inflateSize(super.measureContentCore(inner));
  }

  @override
  void arrangeContentCore(Rect finalRect) {
    content?.arrange(finalRect.deflate(_padding));
  }

  @override
  void renderContentCore(DrawingContext context) {
    final outerRadius = _capsuleRadius(bounds);
    context.drawRoundedRect(
        bounds, outerRadius, outerRadius, Paint(_aquaBorder));

    final highlightRect = bounds.deflate(const EdgeInsets.all(1));
    final highlightRadius = _capsuleRadius(highlightRect);
    context.drawRoundedRect(
      highlightRect,
      highlightRadius,
      highlightRadius,
      Paint(_aquaInnerHighlight),
    );

    final bodyRect = bounds.deflate(const EdgeInsets.all(2));
    final bodyRadius = _capsuleRadius(bodyRect);
    context.drawRoundedRect(bodyRect, bodyRadius, bodyRadius, Paint(color));

    final glossHeight = bodyRect.height * 0.46;
    final glossRect = Rect.fromLTWH(
      bodyRect.left + 2,
      bodyRect.top + 1,
      (bodyRect.width - 4).clamp(0, double.infinity),
      glossHeight,
    );
    final glossRadius = _capsuleRadius(glossRect);
    context.drawRoundedRect(
      glossRect,
      glossRadius,
      glossRadius,
      Paint(_aquaGloss),
    );

    super.renderContentCore(context);
  }

  double _capsuleRadius(Rect rect) {
    final horizontal = rect.width / 2;
    final vertical = rect.height / 2;
    return horizontal < vertical ? horizontal : vertical;
  }
}

Binding<R> _combine2<A, B, R>(
  Binding<A> first,
  Binding<B> second,
  R Function(A first, B second) combine,
) =>
    _CombinedBinding<A, B, R>(first, second, combine);

final class _CombinedBinding<A, B, R> implements Binding<R> {
  _CombinedBinding(this.first, this.second, this.combine);

  final Binding<A> first;
  final Binding<B> second;
  final R Function(A first, B second) combine;

  @override
  R read() => combine(first.read(), second.read());

  @override
  void addListener(VoidListener listener) {
    first.addListener(listener);
    second.addListener(listener);
  }

  @override
  void removeListener(VoidListener listener) {
    first.removeListener(listener);
    second.removeListener(listener);
  }

  @override
  bool get canWrite => false;

  @override
  void write(R value) => throw StateError('A combined binding is read-only.');
}
