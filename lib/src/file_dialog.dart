import 'window.dart';

final class FileDialogFilter {
  const FileDialogFilter({required this.name, required this.extensions});

  final String name;
  final List<String> extensions;
}

/// Backend contract for system file dialogs.
abstract interface class FileDialogHandler {
  Future<String?> showOpenFileDialog(
    Window? parent, {
    String? title,
    String? initialDirectory,
    List<FileDialogFilter> filters,
  });
}

/// A reusable system file dialog, optionally owned by a [Window].
final class FileDialog {
  FileDialog(this._handler);

  final FileDialogHandler _handler;
  String? title;
  String? initialDirectory;
  List<FileDialogFilter> filters = const [];

  Future<String?> showOpen([Window? parent]) => _handler.showOpenFileDialog(
        parent,
        title: title,
        initialDirectory: initialDirectory,
        filters: filters,
      );
}
