import 'window.dart';

/// Backend contract for system file dialogs.
abstract interface class FileDialogHandler {
  Future<String?> showOpenFileDialog(Window? parent, {String? title});
}

/// A reusable system file dialog, optionally owned by a [Window].
final class FileDialog {
  FileDialog(this._handler);

  final FileDialogHandler _handler;

  Future<String?> showOpen({Window? parent, String? title}) =>
      _handler.showOpenFileDialog(parent, title: title);
}
