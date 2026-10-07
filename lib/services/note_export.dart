import 'dart:convert' show latin1;
import 'dart:io' show zlib;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../editor/markdown_styler.dart';
import 'note_store.dart';

/// A4 in PDF points.
const double kA4Width = 595.28;
const double kA4Height = 841.89;

final RegExp _imageLink = RegExp(r'!\[([^\]\n]*)\]\(([^)\n]*)\)');

/// Renders a note the way the WYSIWYG editor shows it (with its images,
/// without any markdown syntax) to a PNG or a PDF, for sharing. Rendering
/// goes through Flutter itself, so the output matches the app exactly.
class NoteExporter {
  NoteExporter({
    required this.store,
    required this.path,
    required this.text,
    ThemeData? theme,
  }) : theme =
           theme ??
           ThemeData(
             colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
             useMaterial3: true,
           );

  final NoteStore store;
  final String path;
  final String text;

  /// Always a light theme: shared pages are printed or viewed on white.
  final ThemeData theme;

  /// The whole note as one PNG, [width] logical pixels wide.
  Future<Uint8List> png({double width = 720, double pixelRatio = 2}) async {
    final images = await _loadImages();
    try {
      const margin = 32.0;
      final content = _content(images, maxImageHeight: 480);
      final height =
          await _measure(content, width - 2 * margin, (p) => p.size.height) +
          2 * margin;
      // Very long notes get a lower resolution rather than an image too large
      // to allocate.
      final ratio = height * pixelRatio > 24000 ? 24000 / height : pixelRatio;
      final image = await _render(
        _page(content, width: width, height: height, margin: margin),
        Size(width, height),
        ratio,
      );
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      for (final i in images.values) {
        i.dispose();
      }
    }
  }

  /// The note as an A4 PDF. Pages break between lines, never through one
  /// (unless a single line or image is taller than a page).
  Future<Uint8List> pdf({double pixelRatio = 2.5, String? title}) async {
    final images = await _loadImages();
    try {
      const margin = 40.0;
      const contentWidth = kA4Width - 2 * margin;
      const contentHeight = kA4Height - 2 * margin;
      final content = _content(
        images,
        maxImageHeight: contentHeight * 0.5,
        fontSize: 11.5,
      );
      final lines = await _measure(content, contentWidth, _lineBreaks);
      final pages = paginate(lines.$1, lines.$2, contentHeight);
      final writer = PdfImageWriter(title: title);
      for (final (top, bottom) in pages) {
        final image = await _render(
          _page(
            content,
            width: kA4Width,
            height: kA4Height,
            margin: margin,
            top: top,
            visible: bottom - top,
          ),
          const Size(kA4Width, kA4Height),
          pixelRatio,
        );
        try {
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          writer.addPage(image.width, image.height, data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      }
      return writer.close();
    } finally {
      for (final i in images.values) {
        i.dispose();
      }
    }
  }

  /// Decodes every image the note embeds from the notes folder; ones that
  /// cannot be read stay text labels.
  Future<Map<String, ui.Image>> _loadImages() async {
    final images = <String, ui.Image>{};
    for (final m in _imageLink.allMatches(text)) {
      final target = resolveNoteLink(path, m.group(2)!);
      if (target == null || !isImagePath(target)) continue;
      if (images.containsKey(target)) continue;
      try {
        final bytes = await store.readBytes(target);
        final codec = await ui.instantiateImageCodec(bytes);
        images[target] = (await codec.getNextFrame()).image;
        codec.dispose();
      } catch (_) {
        // Left as its alt text.
      }
    }
    return images;
  }

  Widget _content(
    Map<String, ui.Image> images, {
    required double maxImageHeight,
    double fontSize = 15,
  }) {
    final scheme = theme.colorScheme;
    final styler = MarkdownStyler(
      base: TextStyle(
        fontSize: fontSize,
        height: 1.45,
        color: scheme.onSurface,
      ),
      scheme: scheme,
      imageBuilder: (target, alt) {
        final resolved = resolveNoteLink(path, target);
        final image = resolved == null ? null : images[resolved];
        if (image == null) return null;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxImageHeight),
          child: RawImage(
            image: image,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            filterQuality: FilterQuality.medium,
          ),
        );
      },
    );
    return RichText(
      text: styler.build(text, const TextSelection.collapsed(offset: -1)),
    );
  }

  /// A white page of [width] x [height] showing [content] from [top] down,
  /// [visible] high (all of it when null), inside [margin].
  Widget _page(
    Widget content, {
    required double width,
    required double height,
    required double margin,
    double top = 0,
    double? visible,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: Colors.white,
        child: Padding(
          padding: EdgeInsets.all(margin),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: visible,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: Transform.translate(
                    offset: Offset(0, -top),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Lays [content] out [width] wide and hands its paragraph to [read].
  Future<T> _measure<T>(
    Widget content,
    double width,
    T Function(RenderParagraph) read,
  ) async {
    late T result;
    await _withTree(
      SizedBox(width: width, child: content),
      Size(width, double.infinity),
      (boundary) async {
        result = read(_findParagraph(boundary)!);
      },
    );
    return result;
  }

  /// The first [RenderParagraph] below [node]. (A GlobalKey would not do:
  /// keys only resolve in the app's own widget tree.)
  static RenderParagraph? _findParagraph(RenderObject node) {
    if (node is RenderParagraph) return node;
    RenderParagraph? found;
    node.visitChildren((child) => found ??= _findParagraph(child));
    return found;
  }

  Future<ui.Image> _render(Widget widget, Size size, double pixelRatio) async {
    late ui.Image image;
    await _withTree(widget, size, (boundary) async {
      image = await boundary.toImage(pixelRatio: pixelRatio);
    });
    return image;
  }

  /// Builds [widget] in a render tree of its own, off screen, lays it out
  /// and paints it, then runs [use] on it.
  Future<void> _withTree(
    Widget widget,
    Size size,
    Future<void> Function(RenderRepaintBoundary) use,
  ) async {
    final boundary = RenderRepaintBoundary();
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final renderView = RenderView(
      view: view,
      child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints(
          minWidth: size.width,
          maxWidth: size.width,
          maxHeight: size.height,
        ),
      ),
    );
    final pipeline = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();
    final buildOwner = BuildOwner(focusManager: FocusManager());
    final root = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Theme(
            data: theme,
            child: DefaultTextStyle(
              style: theme.textTheme.bodyLarge!,
              child: widget,
            ),
          ),
        ),
      ),
    ).attachToRenderTree(buildOwner);
    try {
      buildOwner.buildScope(root);
      buildOwner.finalizeTree();
      pipeline.flushLayout();
      pipeline.flushCompositingBits();
      pipeline.flushPaint();
      await use(boundary);
    } finally {
      // Unmount so the tree's elements and render objects are released.
      root.update(RenderObjectToWidgetAdapter<RenderBox>(container: boundary));
      buildOwner.finalizeTree();
      pipeline.rootNode = null;
      pipeline.dispose();
    }
  }
}

/// Top and bottom of every line of [p] (sorted by top), and its height.
(List<(double, double)>, double) _lineBreaks(RenderParagraph p) {
  final length = p.text.toPlainText().length;
  final boxes = p.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: length),
    boxHeightStyle: ui.BoxHeightStyle.max,
  );
  final lines = <(double, double)>{
    for (final b in boxes) (b.top, b.bottom),
  }.toList()..sort((a, b) => a.$1.compareTo(b.$1));
  return (lines, p.size.height);
}

/// Splits content [height] high into pages [pageHeight] high, breaking only
/// at the top of a line of [lines] (top, bottom). A line taller than a page
/// is cut where the page ends.
List<(double, double)> paginate(
  List<(double, double)> lines,
  double height,
  double pageHeight,
) {
  final pages = <(double, double)>[];
  var top = 0.0;
  while (top < height - 0.5) {
    final limit = top + pageHeight;
    if (height <= limit) {
      pages.add((top, height));
      break;
    }
    // The last line that starts on this page begins the next one.
    var cut = top;
    for (final (lineTop, _) in lines) {
      if (lineTop <= top) continue;
      if (lineTop > limit) break;
      cut = lineTop;
    }
    if (cut <= top) cut = limit;
    pages.add((top, cut));
    top = cut;
  }
  if (pages.isEmpty) pages.add((0, 0));
  return pages;
}

/// Writes a PDF whose pages are full-page RGB images, one per [addPage].
class PdfImageWriter {
  PdfImageWriter({this.title});

  final String? title;
  final BytesBuilder _out = BytesBuilder(copy: false);
  final List<int> _offsets = [];
  final List<int> _pageIds = [];

  // Objects 1 (catalog), 2 (page tree) and 3 (info) are written last but
  // numbered first; pages take three objects each from 4 on.
  int get _nextId => 4 + _pageIds.length * 3;

  void _object(int id, List<int> body) {
    while (_offsets.length < id) {
      _offsets.add(0);
    }
    _offsets[id - 1] = _out.length;
    _out.add(latin1.encode('$id 0 obj\n'));
    _out.add(body);
    _out.add(latin1.encode('\nendobj\n'));
  }

  List<int> _stream(String dict, List<int> data) => [
    ...latin1.encode('$dict\nstream\n'),
    ...data,
    ...latin1.encode('\nendstream'),
  ];

  /// Adds a page showing [rgba] ([width] x [height] pixels, RGBA) scaled to
  /// the full A4 page.
  void addPage(int width, int height, Uint8List rgba) {
    if (_out.isEmpty) _out.add(latin1.encode('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n'));
    final rgb = Uint8List(width * height * 3);
    for (var i = 0, j = 0; j < rgb.length; i += 4, j += 3) {
      rgb[j] = rgba[i];
      rgb[j + 1] = rgba[i + 1];
      rgb[j + 2] = rgba[i + 2];
    }
    final page = _nextId, contents = page + 1, image = page + 2;
    _pageIds.add(page);
    _object(
      page,
      latin1.encode(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $kA4Width $kA4Height] '
        '/Resources << /XObject << /Im0 $image 0 R >> >> '
        '/Contents $contents 0 R >>',
      ),
    );
    final draw = latin1.encode('q $kA4Width 0 0 $kA4Height 0 0 cm /Im0 Do Q');
    _object(contents, _stream('<< /Length ${draw.length} >>', draw));
    final packed = zlib.encode(rgb);
    _object(
      image,
      _stream(
        '<< /Type /XObject /Subtype /Image /Width $width /Height $height '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode '
        '/Length ${packed.length} >>',
        packed,
      ),
    );
  }

  Uint8List close() {
    if (_out.isEmpty) _out.add(latin1.encode('%PDF-1.4\n'));
    final kids = _pageIds.map((id) => '$id 0 R').join(' ');
    _object(1, latin1.encode('<< /Type /Catalog /Pages 2 0 R >>'));
    _object(
      2,
      latin1.encode(
        '<< /Type /Pages /Kids [$kids] /Count ${_pageIds.length} >>',
      ),
    );
    _object(
      3,
      latin1.encode(
        '<< /Producer (TurboNotes)'
        '${title == null ? '' : ' /Title ${_pdfString(title!)}'} >>',
      ),
    );
    final xref = _out.length;
    final b = StringBuffer('xref\n0 ${_offsets.length + 1}\n');
    b.write('0000000000 65535 f \n');
    for (final o in _offsets) {
      b.write('${o.toString().padLeft(10, '0')} 00000 n \n');
    }
    b.write(
      'trailer\n<< /Size ${_offsets.length + 1} /Root 1 0 R /Info 3 0 R >>\n'
      'startxref\n$xref\n%%EOF\n',
    );
    _out.add(latin1.encode(b.toString()));
    return _out.takeBytes();
  }
}

/// A PDF text string: UTF-16BE with a byte-order mark, as hex, so any
/// title survives.
String _pdfString(String s) {
  final b = StringBuffer('<FEFF');
  for (final unit in s.codeUnits) {
    b.write(unit.toRadixString(16).padLeft(4, '0').toUpperCase());
  }
  b.write('>');
  return b.toString();
}
