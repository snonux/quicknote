import 'package:path/path.dart' as p;

/// File extensions treated as markdown notes. Everything else in the notes
/// folder is left alone and never shown.
const List<String> kNoteExtensions = ['.md', '.markdown'];

bool isNotePath(String path) =>
    kNoteExtensions.contains(p.posix.extension(path).toLowerCase());

/// Folders that are never scanned: dot-folders such as `.git`, `.obsidian`
/// or `.stfolder` hold tooling state, not notes.
bool isHiddenSegment(String segment) => segment.startsWith('.');

/// Thrown for a note path a user typed that cannot name a note.
class InvalidNotePathException implements Exception {
  const InvalidNotePathException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thrown when [NoteStore.create] or [NoteStore.rename] would overwrite.
class NoteExistsException implements Exception {
  const NoteExistsException(this.path);
  final String path;
  @override
  String toString() => '$path already exists.';
}

/// Normalizes a user-typed note path to the store's form: POSIX separators,
/// relative to the notes folder, no `.`/`..` segments, a markdown extension
/// (`.md` is appended when none is given).
String normalizeNotePath(String raw) {
  var path = raw.trim().replaceAll('\\', '/');
  while (path.startsWith('/')) {
    path = path.substring(1);
  }
  if (path.isEmpty) {
    throw const InvalidNotePathException('Enter a file name.');
  }
  final segments = path.split('/');
  for (final segment in segments) {
    if (segment.isEmpty || segment == '.' || segment == '..') {
      throw const InvalidNotePathException(
        'Use a path inside the notes folder, without empty, "." or ".." parts.',
      );
    }
    if (isHiddenSegment(segment)) {
      throw const InvalidNotePathException(
        'Names starting with "." are hidden and cannot hold notes.',
      );
    }
  }
  if (!isNotePath(path)) path = '$path.md';
  return path;
}

/// A folder of markdown notes, addressed by relative POSIX paths such as
/// `projects/quicknote.md`. Implementations never touch anything outside
/// the folder and never list non-markdown files.
abstract class NoteStore {
  /// A short human label for the folder, for titles and messages.
  String get label;

  /// Every note path in the folder, recursively, sorted.
  Future<List<String>> list();

  Future<String> read(String path);

  /// Replaces the content of an existing note.
  Future<void> write(String path, String text);

  /// Creates a new note (and any missing parent folders). Throws
  /// [NoteExistsException] rather than overwrite.
  Future<void> create(String path, String text);

  Future<void> delete(String path);

  /// Moves a note. Throws [NoteExistsException] rather than overwrite.
  Future<void> rename(String from, String to);
}
