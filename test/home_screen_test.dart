import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quicknote/screens/home_screen.dart';
import 'package:quicknote/services/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_note_store.dart';

void main() {
  late MemoryNoteStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = MemoryNoteStore({
      'inbox.md': '# Inbox\n',
      'projects/quicknote/ideas.md': '# Ideas\n\n- one\n',
      'projects/plan.md': 'plan',
    });
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    Size size = const Size(1200, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          preferences: PreferencesService(),
          storeFactory: () async => store,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field() => find.byKey(const ValueKey('note-editor-field'));

  testWidgets('the tree shows folders first and expands on tap', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.byKey(const ValueKey('folder:projects')), findsOneWidget);
    expect(find.byKey(const ValueKey('note:inbox.md')), findsOneWidget);
    expect(find.byKey(const ValueKey('note:projects/plan.md')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('folder:projects')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note:projects/plan.md')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('folder:projects/quicknote')),
      findsOneWidget,
    );
  });

  testWidgets('opening, editing and saving a note writes it back', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    expect(find.text('# Inbox\n'), findsOneWidget);

    await tester.enterText(field(), '# Inbox\n\nnew line\n');
    await tester.pump();
    expect(find.text('Unsaved'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('note-save')));
    await tester.pumpAndSettle();
    expect(store.notes['inbox.md'], '# Inbox\n\nnew line\n');
    expect(find.text('Unsaved'), findsNothing);
  });

  testWidgets('switching editors keeps the exact text', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WYSIWYG'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Bold (Ctrl+B)'), findsOneWidget);
    await tester.tap(find.text('Raw'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Bold (Ctrl+B)'), findsNothing);
    expect(tester.widget<TextField>(field()).controller!.text, '# Inbox\n');
    expect(await PreferencesService().editorMode(), EditorMode.raw);
  });

  testWidgets('leaving a note with edits asks first', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    await tester.enterText(field(), 'changed');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('folder:projects')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note:projects/plan.md')));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field()).controller!.text, 'changed');

    await tester.tap(find.byKey(const ValueKey('note:projects/plan.md')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field()).controller!.text, 'plan');
    expect(store.notes['inbox.md'], '# Inbox\n');
  });

  testWidgets('a changed file on disk is not overwritten silently', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    await tester.enterText(field(), 'mine');
    await tester.pump();
    store.notes['inbox.md'] = 'theirs';
    await tester.tap(find.byKey(const ValueKey('note-save')));
    // Not pumpAndSettle: the save button spins while the dialog is open.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Changed on disk'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.notes['inbox.md'], 'theirs');
  });

  testWidgets('Ctrl+P finds and opens a note', (tester) async {
    await pumpHome(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('fuzzy-query')), 'qnid');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field()).controller!.text,
      '# Ideas\n\n- one\n',
    );
    // The tree reveals the opened note.
    expect(
      find.byKey(const ValueKey('note:projects/quicknote/ideas.md')),
      findsOneWidget,
    );
  });

  testWidgets('new notes are created in the open note\'s folder', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('folder:projects')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note:projects/plan.md')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-note')));
    await tester.pumpAndSettle();
    final path = tester.widget<TextField>(
      find.byKey(const ValueKey('path-field')),
    );
    expect(path.controller!.text, 'projects/');
    await tester.enterText(
      find.byKey(const ValueKey('path-field')),
      'projects/later',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(store.notes['projects/later.md'], '# later\n\n');
    expect(tester.widget<TextField>(field()).controller!.text, '# later\n\n');
  });

  testWidgets('on a phone a note opens on its own screen', (tester) async {
    await pumpHome(tester, size: const Size(400, 800));
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    await tester.enterText(field(), 'edited');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Save'),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.notes['inbox.md'], 'edited');
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('Reload in the conflict dialog shows the version on disk', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    await tester.enterText(field(), 'mine');
    await tester.pump();
    store.notes['inbox.md'] = 'theirs';
    await tester.tap(find.byKey(const ValueKey('note-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field()).controller!.text, 'theirs');
    expect(find.text('Unsaved'), findsNothing);
    expect(store.notes['inbox.md'], 'theirs');
  });

  testWidgets('a renamed note stays visible in the tree', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename / move note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('path-field')),
      'archive/old/inbox',
    );
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(store.notes.keys, contains('archive/old/inbox.md'));
    expect(
      find.byKey(const ValueKey('note:archive/old/inbox.md')),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(field()).controller!.text, '# Inbox\n');
  });

  testWidgets('a new note opens focused with the caret at the end', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('new-note')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('path-field')), 'fresh');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    final editor = tester.widget<TextField>(field());
    expect(editor.focusNode!.hasFocus, isTrue);
    expect(editor.controller!.selection.baseOffset, '# fresh\n\n'.length);
  });
}
