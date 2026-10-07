import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/note_store.dart';

/// Images read from a [NoteStore] and decoded, kept so the editor can
/// repaint its inline images on every keystroke without reading them again.
///
/// Images arrive asynchronously; [onLoaded] fires once one is ready so the
/// editor can lay its text out again. Changing the size of a placeholder
/// behind the text field's back leaves it painted in the wrong place.
class AttachmentCache {
  AttachmentCache(this.store, {this.onLoaded});

  final NoteStore store;
  final VoidCallback? onLoaded;
  final Map<String, ui.Image> _images = {};
  final Map<String, Future<ui.Image>> _pending = {};
  bool _disposed = false;

  ui.Image? peek(String path) => _images[path];

  Future<ui.Image> load(String path) {
    final cached = _images[path];
    if (cached != null) return Future.value(cached);
    return _pending[path] ??= _decode(path, store.readBytes(path));
  }

  /// Adds an image just written, so it shows without a read.
  Future<void> put(String path, Uint8List bytes) async {
    _pending[path] = _decode(path, Future.value(bytes));
    await _pending[path];
  }

  Future<ui.Image> _decode(String path, Future<Uint8List> bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(await bytes);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      if (_disposed) {
        image.dispose();
        throw StateError('closed');
      }
      _images.remove(path)?.dispose();
      _images[path] = image;
      onLoaded?.call();
      return image;
    } finally {
      _pending.remove(path);
    }
  }

  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
  }
}

/// An image from the notes folder, shown inline in the WYSIWYG editor.
class NoteImage extends StatefulWidget {
  const NoteImage({
    super.key,
    required this.cache,
    required this.path,
    required this.alt,
    this.maxHeight = 320,
  });

  final AttachmentCache cache;
  final String path;
  final String alt;
  final double maxHeight;

  @override
  State<NoteImage> createState() => _NoteImageState();
}

class _NoteImageState extends State<NoteImage> {
  ui.Image? _image;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.cache != widget.cache) {
      _load();
    }
  }

  void _load() {
    _image = widget.cache.peek(widget.path);
    _error = null;
    if (_image != null) return;
    final path = widget.path;
    widget.cache
        .load(path)
        .then(
          (b) {
            if (mounted && path == widget.path) setState(() => _image = b);
          },
          onError: (Object e) {
            if (mounted && path == widget.path) setState(() => _error = e);
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image != null) {
      // Sized from the decoded image right away, never re-laid out later.
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: image.width.toDouble(),
          maxHeight: image.height < widget.maxHeight
              ? image.height.toDouble()
              : widget.maxHeight,
        ),
        child: AspectRatio(
          aspectRatio: image.width / image.height,
          child: RawImage(
            image: image,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
      );
    }
    return _label(context, broken: _error != null);
  }

  Widget _label(BuildContext context, {required bool broken}) {
    final color = Theme.of(context).colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            broken ? Icons.broken_image_outlined : Icons.image_outlined,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              widget.alt.isEmpty ? widget.path : widget.alt,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
