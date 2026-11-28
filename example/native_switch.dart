import 'dart:async';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';

Future<void> main(List<String> args) async {
  SdlSkiaHost? host;
  Application? application;
  Window? window;
  final smoke = args.contains('--smoke');

  try {
    host = await SdlSkiaHost.initialize(
      diagnosticsEnabled: args.contains('--diagnostics'),
    );
    final notifications = ObservableValue<bool>(true);
    final wifi = Switch(
      text: 'Wi-Fi',
      isChecked: true,
    )..bind(
        Switch.isCheckedProperty,
        notifications.asBinding(),
        mode: BindingMode.twoWay,
      );
    final bluetooth = Switch(text: 'Bluetooth');
    final airplane = Switch(text: 'Airplane mode')..isEnabled = false;
    final state = Label(fontSize: 14, color: const Color(0xFF555555));
    void showState() {
      state.text = 'The model of the binding holds '
          '${notifications.value ? 'true' : 'false'}.';
    }

    showState();
    notifications.addListener(showState);

    application = Application(host: host);
    window = Window(
      title: 'DUI — Switch',
      width: 640,
      height: 420,
      content: StackPanel(
        spacing: 16,
        padding: const EdgeInsets.all(24),
        children: [
          Label(text: 'Switch', fontSize: 28),
          Label(
            text: 'A click turns the switch, and the space bar does the same '
                'for a focused switch. The thumb slides to its new place.',
            fontSize: 16,
            color: const Color(0xFF555555),
          ),
          wifi,
          bluetooth,
          airplane,
          state,
        ],
      ),
    );

    if (smoke) {
      await host.showWindow(window);
      window.updateLayout();

      final position = bluetooth.bounds.left + Switch.trackWidth / 2;
      final height = bluetooth.bounds.top + bluetooth.bounds.height / 2;
      window.dispatchPointerDown(Point(position, height));
      window.dispatchPointerUp(Point(position, height));
      if (!bluetooth.isChecked) {
        throw StateError('The switch did not turn itself on.');
      }

      // The thumb slides to the end of the track.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (bluetooth.progress != 1) {
        throw StateError('The thumb of the switch did not come to its end.');
      }

      // The space bar turns the switch back.
      bluetooth.focus();
      window.dispatchKeyDown('space');
      if (bluetooth.isChecked) {
        throw StateError('The space bar did not turn the switch back.');
      }

      // The two-way binding carries the state of the switch into the model.
      wifi.toggle();
      if (notifications.value) {
        throw StateError('The two-way binding did not carry the state.');
      }

      for (var frame = 0; frame < 1 && host.isOpen(window); frame++) {
        host.pumpEvents();
        host.presentWindow(window);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      if (!host.isOpen(window)) {
        throw StateError(
          'The native window closed before the Switch smoke ended.',
        );
      }
      print('Native Switch smoke passed: 1 frame rendered.');
    } else {
      await application.run(window);
    }
    final diagnostics = host.diagnosticsFor(window);
    if (diagnostics != null) print(diagnostics);
  } finally {
    host?.dispose();
  }
}
