import 'package:flutter/services.dart';

/// An image read from the system clipboard.
typedef ClipboardImageData = ({Uint8List bytes, String extension});

const _channel = MethodChannel('org.buetow.turbonotes/clipboard');

/// File extension for an image MIME type, or null for one notes do not keep.
String? imageExtensionFor(String mime) => switch (mime.toLowerCase()) {
  'image/png' => '.png',
  'image/jpeg' || 'image/jpg' => '.jpg',
  'image/gif' => '.gif',
  'image/webp' => '.webp',
  _ => null,
};

/// The image on the clipboard, or null when it holds none. Flutter's own
/// clipboard API is text-only, so the platform runner reads it (GTK on Linux,
/// ClipboardManager on Android).
Future<ClipboardImageData?> readClipboardImage() async {
  try {
    final result = await _channel.invokeMapMethod<String, Object?>('readImage');
    final bytes = result?['bytes'];
    final ext = imageExtensionFor(result?['mime'] as String? ?? '');
    if (bytes is! Uint8List || bytes.isEmpty || ext == null) return null;
    return (bytes: bytes, extension: ext);
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
