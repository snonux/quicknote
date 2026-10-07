import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:turbonotes/services/note_export.dart';

import 'support/memory_note_store.dart';

void main() {
  group('paginate', () {
    test('breaks at line starts and keeps lines whole', () {
      final lines = [for (var i = 0; i < 10; i++) (i * 30.0, i * 30.0 + 30)];
      expect(paginate(lines, 300, 100), [
        (0.0, 90.0),
        (90.0, 180.0),
        (180.0, 270.0),
        (270.0, 300.0),
      ]);
    });

    test('cuts a line taller than a page', () {
      expect(paginate([(0, 250), (250, 260)], 260, 100), [
        (0.0, 100.0),
        (100.0, 200.0),
        (200.0, 260.0),
      ]);
    });

    test('an empty note is one empty page', () {
      expect(paginate(const [], 0, 100), [(0.0, 0.0)]);
    });
  });

  test('PdfImageWriter writes a well-formed PDF', () {
    final writer = PdfImageWriter(title: 'Grüße (1)');
    writer.addPage(2, 2, Uint8List.fromList(List.filled(16, 255)));
    writer.addPage(2, 2, Uint8List.fromList(List.filled(16, 0)));
    final pdf = latin1.decode(writer.close());
    expect(pdf, startsWith('%PDF-1.4'));
    expect(pdf, contains('/Type /Pages /Kids [4 0 R 7 0 R] /Count 2'));
    expect(pdf, contains('/Title <FEFF'));
    expect(pdf.trimRight(), endsWith('%%EOF'));
    // Every xref offset points at its object.
    final xref = pdf.substring(pdf.indexOf('\nxref\n'));
    final offsets = RegExp(
      r'^(\d{10}) 00000 n',
      multiLine: true,
    ).allMatches(xref).map((m) => int.parse(m[1]!)).toList();
    expect(offsets, hasLength(9));
    for (var i = 0; i < offsets.length; i++) {
      expect(pdf.substring(offsets[i]), startsWith('${i + 1} 0 obj'));
    }
  });

  testWidgets('a note renders to a PNG and a PDF', (tester) async {
    final store = MemoryNoteStore({
      'a/n.md': '# Title\n\nSome **bold** text #tag\n\n${'- item\n' * 200}',
    });
    await tester.runAsync(() async {
      final exporter = NoteExporter(
        store: store,
        path: 'a/n.md',
        text: store.notes['a/n.md']!,
      );
      final png = await exporter.png();
      expect(png.sublist(1, 4), 'PNG'.codeUnits);
      final pdf = await exporter.pdf(pixelRatio: 1);
      final text = latin1.decode(pdf);
      final pages = RegExp(r'/Count (\d+)').firstMatch(text)!.group(1);
      expect(int.parse(pages!), greaterThan(1));
      if (Platform.environment['QUICKNOTE_EXPORT_DIR'] case final dir?) {
        File('$dir/test.pdf').writeAsBytesSync(pdf);
        File('$dir/test.png').writeAsBytesSync(png);
      }
    });
  });
}
