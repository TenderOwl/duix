import 'dart:typed_data';

/// Well-known MIME types used by the formatted clipboard API.
abstract final class ClipboardMimeTypes {
  static const plainText = 'text/plain';
  static const html = 'text/html';
}

/// Backend contract for plain and formatted clipboard access.
abstract interface class ClipboardHandler {
  String? readClipboardText();
  bool writeClipboardText(String text);

  bool hasClipboardData(String mimeType) => false;
  Uint8List? readClipboardData(String mimeType) => null;
  bool writeClipboardData(Map<String, List<int>> formats) => false;
}
