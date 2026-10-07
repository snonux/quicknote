import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quicknote/services/directory_note_store.dart';
import 'package:quicknote/services/note_store.dart';
import 'package:quicknote/services/note_tree.dart';

void main() {
  group('normalizeNotePath', () {
    test('adds .md, strips leading slashes, uses / separators', () {
      expect(normalizeNotePath('todo'), 'todo.md');
      expect(normalizeNotePath('/a\\b.markdown'), 'a/b.markdown');
      expect(normalizeNotePath(' a/b.MD '), 'a/b.MD');
    });

    test('rejects paths that leave the folder or are hidden', () {
      for (final bad in ['', '  ', 'a/../b', './a', 'a//b', '.git/x', 'a/.b']) {
        expect(
          () => normalizeNotePath(bad),
          throwsA(isA<InvalidNotePathException>()),
          reason: bad,
        );
      }
    });
  });

  group('DirectoryNoteStore', () {
    late Directory root;
    late DirectoryNoteStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('quicknote-store');
      store = DirectoryNoteStore(root.path);
      await Directory('${root.path}/b/c').create(recursive: true);
      await Directory('${root.path}/.git').create();
      await File('${root.path}/a.md').writeAsString('A');
      await File('${root.path}/b/c/d.markdown').writeAsString('D');
      await File('${root.path}/b/notes.txt').writeAsString('not a note');
      await File('${root.path}/.git/HEAD.md').writeAsString('hidden');
    });

    tearDown(() => root.delete(recursive: true));

    test('lists markdown notes recursively, skipping hidden folders', () async {
      expect(await store.list(), ['a.md', 'b/c/d.markdown']);
    });

    test('a missing folder fails the listing instead of looking empty', () {
      expect(
        DirectoryNoteStore('${root.path}/missing').list(),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('write replaces the content and leaves no temp files', () async {
      await store.write('a.md', 'new text');
      expect(await store.read('a.md'), 'new text');
      expect(root.listSync().map((e) => e.path.split('/').last).toSet(), {
        'a.md',
        'b',
        '.git',
      });
    });

    test('write refuses a note that does not exist', () {
      expect(
        store.write('nope.md', 'x'),
        throwsA(isA<PathNotFoundException>()),
      );
    });

    test('create makes folders and never overwrites', () async {
      await store.create('x/y/new', '# New');
      expect(await store.read('x/y/new.md'), '# New');
      expect(
        store.create('a.md', 'clobber'),
        throwsA(isA<NoteExistsException>()),
      );
      expect(await store.read('a.md'), 'A');
    });

    test('rename moves into new folders and refuses to overwrite', () async {
      await store.rename('a.md', 'moved/a.md');
      expect(await store.list(), ['b/c/d.markdown', 'moved/a.md']);
      expect(
        store.rename('moved/a.md', 'b/c/d.markdown'),
        throwsA(isA<NoteExistsException>()),
      );
    });

    test('delete removes the note', () async {
      await store.delete('a.md');
      expect(await store.list(), ['b/c/d.markdown']);
    });

    test('paths cannot escape the folder', () {
      expect(store.read('../x.md'), throwsA(isA<InvalidNotePathException>()));
    });
  });

  group('NoteFolder', () {
    test('builds a sorted tree with folders first and counts', () {
      final tree = NoteFolder.build([
        'z.md',
        'b/two.md',
        'a/x/deep.md',
        'b/One.md',
      ]);
      expect(tree.folders.map((f) => f.name), ['a', 'b']);
      expect(tree.notes, ['z.md']);
      expect(tree.folders[1].notes, ['b/One.md', 'b/two.md']);
      expect(tree.folders[0].folders.single.path, 'a/x');
      expect(tree.noteCount, 4);
      expect(tree.folders[0].noteCount, 1);
    });

    test('ancestorFolders lists every parent', () {
      expect(ancestorFolders('a/b/c.md').toList(), ['a', 'a/b']);
      expect(ancestorFolders('c.md'), isEmpty);
    });
  });
}
