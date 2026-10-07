/// A folder in the note tree, built from the flat path list a [NoteStore]
/// returns. Folders sort before notes, both alphabetically (case-insensitive).
class NoteFolder {
  NoteFolder(this.name, this.path);

  /// Last path segment; empty for the root.
  final String name;

  /// Relative path from the notes folder root; empty for the root.
  final String path;

  final Map<String, NoteFolder> _folders = {};
  final List<String> _notes = [];

  List<NoteFolder> get folders {
    final list = _folders.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Full relative note paths directly inside this folder.
  List<String> get notes {
    final list = List.of(_notes);
    list.sort(
      (a, b) => baseName(a).toLowerCase().compareTo(baseName(b).toLowerCase()),
    );
    return list;
  }

  int get noteCount =>
      _notes.length + _folders.values.fold(0, (sum, f) => sum + f.noteCount);

  static NoteFolder build(Iterable<String> notePaths) {
    final root = NoteFolder('', '');
    for (final path in notePaths) {
      final segments = path.split('/');
      var folder = root;
      for (var i = 0; i < segments.length - 1; i++) {
        final name = segments[i];
        final childPath = folder.path.isEmpty ? name : '${folder.path}/$name';
        folder = folder._folders.putIfAbsent(
          name,
          () => NoteFolder(name, childPath),
        );
      }
      folder._notes.add(path);
    }
    return root;
  }
}

String baseName(String path) => path.substring(path.lastIndexOf('/') + 1);

String parentPath(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

/// Every folder on the way to [path], e.g. `a/b/c.md` -> `a`, `a/b`.
Iterable<String> ancestorFolders(String path) sync* {
  final segments = path.split('/');
  for (var i = 1; i < segments.length; i++) {
    yield segments.take(i).join('/');
  }
}
