import 'dart:typed_data';
import 'dart:ui' as ui;

/// The longest side, in pixels, an image from the notes folder is decoded
/// at. Notes show images at most a screen wide, while a phone photo is
/// 4000 px and 64 MB decoded.
const int kMaxImageSide = 2048;

/// Decodes [bytes] (PNG, JPEG, GIF, WebP) to its first frame, scaled down
/// to [maxSide] on its longest side if larger.
Future<ui.Image> decodeImage(
  Uint8List bytes, {
  int maxSide = kMaxImageSide,
}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width, h = descriptor.height;
    final scale = w > h ? maxSide / w : maxSide / h;
    codec = scale < 1
        ? await descriptor.instantiateCodec(
            targetWidth: (w * scale).round().clamp(1, maxSide),
            targetHeight: (h * scale).round().clamp(1, maxSide),
          )
        : await descriptor.instantiateCodec();
    return (await codec.getNextFrame()).image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
