import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turbonotes/services/preferences.dart';
import 'package:turbonotes/widgets/note_editor.dart';

import 'support/memory_note_store.dart';

/// A store whose reads wait until [release], like a slow folder.
class _SlowStore extends MemoryNoteStore {
  _SlowStore(super.notes);

  Completer<void> gate = Completer();
  int reads = 0;

  void release() {
    if (!gate.isCompleted) gate.complete();
  }

  @override
  Future<String> read(String path) async {
    reads++;
    await gate.future;
    return super.read(path);
  }
}

Widget _editor(
  _SlowStore store,
  GlobalKey<NoteEditorState> key, {
  String? cached,
}) => MaterialApp(
  home: Scaffold(
    body: NoteEditor(
      key: key,
      store: store,
      path: 'a.md',
      initialMode: EditorMode.raw,
      cachedText: cached == null ? null : (_) => cached,
    ),
  ),
);

void main() {
  testWidgets('a cached note shows before the disk read returns', (
    tester,
  ) async {
    final store = _SlowStore({'a.md': 'hello'});
    final key = GlobalKey<NoteEditorState>();
    await tester.pumpWidget(_editor(store, key, cached: 'hello'));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(key.currentState!.text, 'hello');
    expect(store.reads, 1, reason: 'the disk is still checked');

    store.release();
    await tester.pumpAndSettle();
    expect(key.currentState!.text, 'hello');
    expect(key.currentState!.dirty, isFalse);
  });

  testWidgets('without a cache the note waits for the disk', (tester) async {
    final store = _SlowStore({'a.md': 'hello'});
    final key = GlobalKey<NoteEditorState>();
    await tester.pumpWidget(_editor(store, key));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    store.release();
    await tester.pumpAndSettle();
    expect(key.currentState!.text, 'hello');
  });

  testWidgets('a stale cache is replaced by the text on disk', (tester) async {
    final store = _SlowStore({'a.md': 'new on disk'});
    final key = GlobalKey<NoteEditorState>();
    await tester.pumpWidget(_editor(store, key, cached: 'old'));
    expect(key.currentState!.text, 'old');

    store.release();
    await tester.pumpAndSettle();
    expect(key.currentState!.text, 'new on disk');
    expect(key.currentState!.dirty, isFalse);
  });

  testWidgets('edits typed over a stale cache ask before overwriting', (
    tester,
  ) async {
    final store = _SlowStore({'a.md': 'new on disk'});
    final key = GlobalKey<NoteEditorState>();
    await tester.pumpWidget(_editor(store, key, cached: 'old'));
    await tester.enterText(find.byType(TextField), 'old, edited');

    store.release();
    await tester.pump(const Duration(milliseconds: 500));
    // The edits stay; the disk's version is not silently taken or lost.
    expect(key.currentState!.text, 'old, edited');

    final saved = key.currentState!.save();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Changed on disk'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(await saved, isFalse);
    expect(store.notes['a.md'], 'new on disk');
  });
}
