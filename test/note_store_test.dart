import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:turbonotes/services/directory_note_store.dart';
import 'package:turbonotes/services/note_store.dart';
import 'package:turbonotes/services/note_tree.dart';

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

    test('images are stored next to the notes, never overwritten', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      await store.createBytes('b/attachments/x.png', bytes);
      expect(await store.readBytes('b/attachments/x.png'), bytes);
      expect(
        store.createBytes('b/attachments/x.png', Uint8List(1)),
        throwsA(isA<NoteExistsException>()),
      );
      // Images are not notes.
      expect(await store.list(), ['a.md', 'b/c/d.markdown']);
      expect(
        store.createBytes('evil.md', bytes),
        throwsA(isA<InvalidNotePathException>()),
      );
      expect(
        store.readBytes('../x.png'),
        throwsA(isA<InvalidNotePathException>()),
      );
    });
  });

  group('resolveNoteLink', () {
    test('resolves relative to the note, decoding %20', () {
      expect(
        resolveNoteLink('a/b/n.md', 'attachments/x%20y.png'),
        'a/b/attachments/x y.png',
      );
      expect(resolveNoteLink('n.md', './img.png'), 'img.png');
      expect(resolveNoteLink('a/n.md', '../img.png'), 'img.png');
      expect(resolveNoteLink('a/n.md', '<my img.png>'), 'a/my img.png');
      expect(resolveNoteLink('a/n.md', 'i.png "Title"'), 'a/i.png');
    });

    test('rejects URLs, absolute paths and escapes', () {
      for (final t in ['https://x.y/i.png', '/etc/i.png', '../../i.png', '']) {
        expect(resolveNoteLink('a/n.md', t), isNull, reason: t);
      }
    });
  });

  test('attachment paths sit in the note folder, named after the note', () {
    final at = DateTime(2026, 10, 7, 18, 2, 15);
    expect(attachmentPathFor('a/to do.md', '.png', at), (
      path: 'a/attachments/to-do-20261007-180215.png',
      link: 'attachments/to-do-20261007-180215.png',
    ));
    expect(
      attachmentPathFor('n.md', 'jpg', at).path,
      'attachments/n-20261007-180215.jpg',
    );
    // A second image in the same second gets a suffix, as quick capture does.
    expect(
      attachmentPathFor('n.md', '.png', at, suffix: 1).link,
      'attachments/n-20261007-180215-1.png',
    );
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

  test('conflict copies sit next to the note with a timestamp', () {
    final at = DateTime(2026, 10, 7, 9, 5, 3);
    expect(
      conflictCopyPath('a/b/todo.md', at),
      'a/b/todo (conflict 2026-10-07 090503).md',
    );
    expect(
      conflictCopyPath('x.markdown', at),
      'x (conflict 2026-10-07 090503).markdown',
    );
    expect(normalizeNotePath(conflictCopyPath('a/todo.md', at)), isNotEmpty);
  });
}
