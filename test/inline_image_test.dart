import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turbonotes/services/preferences.dart';
import 'package:turbonotes/widgets/note_editor.dart';
import 'package:turbonotes/widgets/note_image.dart';

import 'support/memory_note_store.dart';

// A 1x1 PNG.
final Uint8List kPng = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0xF0,
  0x1F,
  0x00,
  0x05,
  0x00,
  0x01,
  0xFF,
  0x89,
  0x99,
  0x3D,
  0x1D,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

void main() {
  testWidgets('WYSIWYG shows an image from the notes folder inline', (
    tester,
  ) async {
    final store = MemoryNoteStore({
      'a/note.md': 'Before\n\n![shot](attachments/x.png)\n\nAfter\n',
    });
    store.files['a/attachments/x.png'] = kPng;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteEditor(
            store: store,
            path: 'a/note.md',
            initialMode: EditorMode.wysiwyg,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NoteImage), findsOneWidget);
    // Decoding runs outside the fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsOneWidget);
  });
}
