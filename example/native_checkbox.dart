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
    final weeklyReport = ObservableValue<bool>(false);
    final notifications =
        CheckBox(text: 'Enable notifications', isChecked: true);
    final rememberSize = CheckBox(text: 'Remember the window size');
    final boundBox = CheckBox(text: 'Send a weekly report')
      ..bind(
        CheckBox.isCheckedProperty,
        weeklyReport.asBinding(),
        mode: BindingMode.twoWay,
      );
    final state = Label(fontSize: 14, color: const Color(0xFF555555));
    void showState() {
      state.text = 'The model of the binding holds '
          '${weeklyReport.value ? 'true' : 'false'}.';
    }

    showState();
    weeklyReport.addListener(showState);

    application = Application(host: host);
    window = Window(
      title: 'DUI — CheckBox',
      width: 640,
      height: 420,
      content: StackPanel(
        spacing: 16,
        padding: const EdgeInsets.all(24),
        children: [
          Label(text: 'CheckBox', fontSize: 28),
          Label(
            text: 'A click checks the box, and the space bar does the same '
                'for a focused box.',
            fontSize: 16,
            color: const Color(0xFF555555),
          ),
          notifications,
          rememberSize,
          boundBox,
          state,
          CheckBox(text: 'Disabled option')..isEnabled = false,
        ],
      ),
    );

    if (smoke) {
      await host.showWindow(window);
      window.updateLayout();

      final position = rememberSize.bounds.left + 8;
      final height = rememberSize.bounds.top + rememberSize.bounds.height / 2;
      window.dispatchPointerDown(Point(position, height));
      window.dispatchPointerUp(Point(position, height));
      if (!rememberSize.isChecked) {
        throw StateError('The check box did not check itself.');
      }
      rememberSize.focus();
      window.dispatchKeyDown('space');
      if (rememberSize.isChecked) {
        throw StateError('The space bar did not check the box back.');
      }

      // The two-way binding carries the state of the box into the model.
      final boundPosition = boundBox.bounds.left + 8;
      final boundHeight = boundBox.bounds.top + boundBox.bounds.height / 2;
      window.dispatchPointerDown(Point(boundPosition, boundHeight));
      window.dispatchPointerUp(Point(boundPosition, boundHeight));
      if (!boundBox.isChecked || !weeklyReport.value) {
        throw StateError('The two-way binding did not carry the state.');
      }

      for (var frame = 0; frame < 1 && host.isOpen(window); frame++) {
        host.pumpEvents();
        host.presentWindow(window);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      if (!host.isOpen(window)) {
        throw StateError(
          'The native window closed before the CheckBox smoke ended.',
        );
      }
      print('Native CheckBox smoke passed: 1 frame rendered.');
    } else {
      await application.run(window);
    }
    final diagnostics = host.diagnosticsFor(window);
    if (diagnostics != null) print(diagnostics);
  } finally {
    host?.dispose();
  }
}
