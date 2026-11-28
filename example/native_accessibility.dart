import 'dart:async';
import 'dart:io' show pid;

import 'package:duix/dui.dart';
import 'package:duix/native.dart';

/// Shows a window with a semantics tree and serves it to UI Automation.
///
/// The assistive technologies of Windows see the widgets of the window as
/// elements of a tree, so the example is a good target for the inspection
/// tools of the system, for example the Inspect.exe of the Windows SDK.
///
/// The window stays open until it is closed, or for the number of seconds
/// given on the command line.
Future<void> main(List<String> args) async {
  final seconds = _secondsArgument(args);
  SdlSkiaHost? host;

  try {
    host = await SdlSkiaHost.initialize();
    final button = Button(
      content: Label(text: 'Press me'),
      onClick: () {},
    );
    final textBox = TextBox(text: 'Editable value');
    final window = Window(
      title: 'DUI accessibility',
      width: 360,
      height: 240,
      content: StackPanel(
        spacing: 12,
        padding: const EdgeInsets.all(20),
        children: [
          Label(text: 'Accessibility bridge', fontSize: 18),
          button,
          textBox,
        ],
      ),
    );

    button.focus();
    await host.showWindow(window);
    print('pid: $pid');
    print('window: ${window.title}');

    if (seconds > 0) {
      Timer(Duration(seconds: seconds), window.close);
    }
    await host.runWindow(window);
  } finally {
    host?.dispose();
  }
}

int _secondsArgument(List<String> args) {
  for (final argument in args) {
    if (argument.startsWith('--seconds=')) {
      return int.tryParse(argument.substring('--seconds='.length)) ?? 0;
    }
  }
  return 0;
}
