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
    final quality = ObservableValue<String>('normal');
    final group = RadioGroup<String>(
      selectedValue: 'normal',
      content: StackPanel(
        spacing: 8,
        children: [
          RadioButton<String>(value: 'low', text: 'Low'),
          RadioButton<String>(value: 'normal', text: 'Normal'),
          RadioButton<String>(value: 'high', text: 'High'),
        ],
      ),
    )..bind(
        RadioGroup.selectedValueProperty,
        quality.asBinding(),
        mode: BindingMode.twoWay,
      );
    final state = Label(fontSize: 14, color: const Color(0xFF555555));
    void showState() {
      state.text = 'The model of the binding holds "${quality.value}".';
    }

    showState();
    quality.addListener(showState);

    application = Application(host: host);
    window = Window(
      title: 'DUI — RadioButton',
      width: 640,
      height: 420,
      content: StackPanel(
        spacing: 16,
        padding: const EdgeInsets.all(24),
        children: [
          Label(text: 'RadioButton', fontSize: 28),
          Label(
            text: 'One button of a group is checked at a time. A click checks '
                'a button, and the arrows walk over the buttons of the group.',
            fontSize: 16,
            color: const Color(0xFF555555),
          ),
          _fieldLabel('Quality'),
          group,
          state,
          _fieldLabel('Disabled group'),
          RadioGroup<String>(
            content: StackPanel(
              spacing: 8,
              children: [
                RadioButton<String>(value: 'a', text: 'First'),
                RadioButton<String>(value: 'b', text: 'Second'),
              ],
            ),
          )..isEnabled = false,
        ],
      ),
    );

    if (smoke) {
      await host.showWindow(window);
      window.updateLayout();

      final buttons = group.radioButtons;
      if (buttons.length != 3) {
        throw StateError('The smoke did not find the buttons of the group.');
      }

      // A click checks the button and the group carries the value.
      final position = Point(
        buttons[2].bounds.left + 8,
        buttons[2].bounds.top + buttons[2].bounds.height / 2,
      );
      window.dispatchPointerDown(position);
      window.dispatchPointerUp(position);
      if (!buttons[2].isChecked || quality.value != 'high') {
        throw StateError('The click did not check the button.');
      }
      if (buttons[1].isChecked) {
        throw StateError('The button of the group stayed checked.');
      }

      // The arrows walk over the buttons of the group.
      buttons[2].focus();
      window.dispatchKeyDown('up');
      if (!buttons[1].isChecked || quality.value != 'normal') {
        throw StateError('The arrow did not move the selection.');
      }

      for (var frame = 0; frame < 1 && host.isOpen(window); frame++) {
        host.pumpEvents();
        host.presentWindow(window);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      if (!host.isOpen(window)) {
        throw StateError(
          'The native window closed before the RadioButton smoke ended.',
        );
      }
      print('Native RadioButton smoke passed: 1 frame rendered.');
    } else {
      await application.run(window);
    }
    final diagnostics = host.diagnosticsFor(window);
    if (diagnostics != null) print(diagnostics);
  } finally {
    host?.dispose();
  }
}

Label _fieldLabel(String text) => Label(
      text: text,
      fontSize: 14,
      color: const Color(0xFF555555),
    );
