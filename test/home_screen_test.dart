import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turbonotes/screens/home_screen.dart';
import 'package:turbonotes/services/directory_note_store.dart';
import 'package:turbonotes/services/preferences.dart';
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

  testWidgets('a shared folder without All files access says so', (
    tester,
  ) async {
    // Android 11+ would list such a folder as empty instead of failing.
    const channel = MethodChannel('org.buetow.turbonotes/storage');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'needsAllFilesAccess',
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final dir = Directory.systemTemp.createTempSync('turbonotes-shared');
    addTearDown(() => dir.deleteSync(recursive: true));
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          preferences: PreferencesService(),
          storeFactory: () async => DirectoryNoteStore(dir.path),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('needs All files access'), findsOneWidget);
    expect(find.text('Choose notes folder'), findsOneWidget);
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

  testWidgets('a refresh keeps unsaved edits in the open note', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    await tester.enterText(field(), '# Inbox\nunsaved\n');
    await tester.pump();
    store.listDelay = const Duration(milliseconds: 100);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field()).controller!.text,
      '# Inbox\nunsaved\n',
    );
    expect(find.text('Unsaved'), findsOneWidget);
  });

  testWidgets('narrowing the window saves the open note', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    await tester.enterText(field(), '# Inbox\nkept\n');
    await tester.pump();

    // Below two-pane width the editor goes away without a save path.
    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    expect(field(), findsNothing);
    expect(store.notes['inbox.md'], '# Inbox\nkept\n');
  });

  testWidgets('a note page keeps the wide editor away', (tester) async {
    await pumpHome(tester, size: const Size(400, 800));
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    // Only the note page's editor: two would fight over the same file.
    expect(field(), findsOneWidget);
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

  testWidgets('switching notes saves the edits first', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    await tester.enterText(field(), 'changed');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('folder:projects')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note:projects/plan.md')));
    await tester.pumpAndSettle();
    expect(store.notes['inbox.md'], 'changed');
    expect(tester.widget<TextField>(field()).controller!.text, 'plan');
    expect(find.text('Saved inbox.md'), findsNothing); // autosave is quiet
  });

  testWidgets('a conflict on switching keeps the note open on Cancel', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    await tester.enterText(field(), 'mine');
    await tester.pump();
    store.notes['inbox.md'] = 'theirs';
    await tester.tap(find.byKey(const ValueKey('folder:projects')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note:projects/plan.md')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Changed on disk'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field()).controller!.text, 'mine');
    expect(store.notes['inbox.md'], 'theirs');
  });

  testWidgets('going to the background saves the open note', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    await tester.enterText(field(), 'typed');
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.notes['inbox.md'], 'typed');
    expect(find.text('Unsaved'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  });

  testWidgets('a background save never overwrites a change on disk', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    await tester.enterText(field(), 'mine');
    await tester.pump();
    store.notes['inbox.md'] = 'theirs';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.notes['inbox.md'], 'theirs');
    final copies = store.notes.keys
        .where((k) => k.startsWith('inbox (conflict '))
        .toList();
    expect(copies, hasLength(1)); // not one per lifecycle event
    expect(store.notes[copies.single], 'mine');
    expect(find.text('Unsaved'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  });

  testWidgets('the home button creates and opens TurboNote.md', (tester) async {
    await pumpHome(tester);
    expect(find.byTooltip('Open TurboNote.md (Ctrl+D)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('default-note')));
    await tester.pumpAndSettle();
    expect(store.notes['TurboNote.md'], '# TurboNote\n\n');
    expect(
      tester.widget<TextField>(field()).controller!.text,
      '# TurboNote\n\n',
    );

    // Existing content is opened, never replaced.
    await tester.enterText(field(), '# TurboNotes\n\nkeep me\n');
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final editor = tester.widget<TextField>(field());
    expect(editor.controller!.text, '# TurboNotes\n\nkeep me\n');
    // Ready for typing: focused, caret at the end.
    expect(editor.focusNode!.hasFocus, isTrue);
    expect(
      editor.controller!.selection.baseOffset,
      editor.controller!.text.length,
    );

    // Pressed again while open, it still lands at the end.
    editor.controller!.selection = const TextSelection.collapsed(offset: 0);
    await tester.tap(find.byKey(const ValueKey('default-note')));
    await tester.pumpAndSettle();
    expect(editor.focusNode!.hasFocus, isTrue);
    expect(
      editor.controller!.selection.baseOffset,
      editor.controller!.text.length,
    );
  });

  testWidgets('the default note comes from Preferences', (tester) async {
    SharedPreferences.setMockInitialValues({
      'flutter.DefaultNote': 'journal/today.md',
    });
    store.notes['journal/today.md'] = 'today';
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('default-note')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field()).controller!.text, 'today');
    expect(find.byKey(const ValueKey('note:journal/today.md')), findsOneWidget);
    expect(store.notes.containsKey('TurboNote.md'), isFalse);
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
    expect(tester.widget<TextField>(field()).focusNode!.hasFocus, isTrue);
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
    await tester.tap(find.byTooltip('Show menu'));
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

  testWidgets('on a phone, rename reopens the note under its new name', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(400, 800));
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename / move'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('path-field')), 'later');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(store.notes.keys, contains('later.md'));
    expect(find.text('later.md'), findsOneWidget); // the page subtitle
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('on a phone, delete with unsaved edits closes the note', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(400, 800));
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    await tester.enterText(field(), 'edited');
    await tester.pump();
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete note?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete'),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.notes.containsKey('inbox.md'), isFalse);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byKey(const ValueKey('note:inbox.md')), findsNothing);
  });

  testWidgets('shortcuts still work after the open note is deleted', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    await tester.tap(field());
    await tester.pump();
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete note'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete'),
      ),
    );
    await tester.pumpAndSettle();
    expect(field(), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fuzzy-query')), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('on a phone the editor header fits one row', (tester) async {
    await pumpHome(tester, size: const Size(400, 800));
    await tester.tap(find.byKey(const ValueKey('note:inbox.md')));
    await tester.pumpAndSettle();
    expect(find.text('WYSIWYG'), findsNothing); // icons only
    final save = tester.getCenter(find.byKey(const ValueKey('note-save')));
    final mode = tester.getCenter(find.byIcon(Icons.text_format));
    expect((save.dy - mode.dy).abs(), lessThan(4));
    await tester.tap(find.byIcon(Icons.text_format));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Bold (Ctrl+B)'), findsOneWidget);
  });
}
