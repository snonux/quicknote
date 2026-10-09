import 'package:flutter/services.dart';

import 'clipboard_image.dart';

const _channel = MethodChannel('org.buetow.turbonotes/images');

/// Images the user picks from the gallery (Android's photo picker), in the
/// order picked; empty when they cancel. Formats notes do not keep (HEIC)
/// arrive converted to JPEG.
Future<List<ImageBytes>> pickGalleryImages() async {
  final result = await _channel.invokeListMethod<Object?>('pickImages');
  return [for (final item in result ?? const []) ?_image(item)];
}

/// A photo taken with the camera app, or null when the user backs out.
Future<ImageBytes?> takeCameraPhoto() async =>
    _image(await _channel.invokeMethod<Object?>('takePhoto'));

ImageBytes? _image(Object? item) {
  if (item is! Map) return null;
  final bytes = item['bytes'];
  final ext = imageExtensionFor(item['mime'] as String? ?? '');
  if (bytes is! Uint8List || bytes.isEmpty || ext == null) return null;
  return (bytes: bytes, extension: ext);
}
