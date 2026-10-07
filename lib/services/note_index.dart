import 'note_store.dart';
import 'tags.dart';

/// Lower-cases [s] one character at a time, so offsets into the result are
/// offsets into [s] (a plain toLowerCase can grow the string: `İ` -> `i̇`).
String foldCase(String s) {
  final lower = s.toLowerCase();
  if (lower.length == s.length) return lower;
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final l = s[i].toLowerCase();
    b.write(l.length == 1 ? l : s[i]);
  }
  return b.toString();
}

final RegExp _word = RegExp(r'[\p{L}\p{N}_]+', unicode: true);

/// One note's text plus what search and the tag tree need from it, computed
/// on first use.
class IndexedNote {
  IndexedNote(this.text);

  final String text;
  late final String folded = foldCase(text);
  late final Set<String> tags = extractTags(text);
  late final Set<String> words = {
    for (final m in _word.allMatches(folded)) m[0]!,
  };
}

/// The text of every note, kept in memory for full-text search and tags.
/// Built once per folder load, then kept current as notes are saved,
/// created, renamed and deleted from within the app.
class NoteIndex {
  NoteIndex([Map<String, String> texts = const {}])
    : _notes = {for (final e in texts.entries) e.key: IndexedNote(e.value)};

  final Map<String, IndexedNote> _notes;
  TagNode? _tagTree;
  Map<String, Set<String>>? _vocabulary;

  /// Reads every note in [paths], a few at a time. A note that cannot be
  /// read is left out rather than failing the whole index.
  static Future<NoteIndex> load(
    NoteStore store,
    List<String> paths, {
    int parallel = 8,
  }) async {
    final texts = <String, String>{};
    var next = 0;
    Future<void> worker() async {
      while (next < paths.length) {
        final path = paths[next++];
        try {
          texts[path] = await store.read(path);
        } catch (_) {
          // Unreadable notes are simply not searchable.
        }
      }
    }

    await Future.wait([for (var i = 0; i < parallel; i++) worker()]);
    return NoteIndex(texts);
  }

  Iterable<String> get paths => _notes.keys;

  IndexedNote? operator [](String path) => _notes[path];

  void put(String path, String text) {
    if (_notes[path]?.text == text) return;
    _notes[path] = IndexedNote(text);
    _changed();
  }

  void remove(String path) {
    if (_notes.remove(path) != null) _changed();
  }

  void rename(String from, String to) {
    final note = _notes.remove(from);
    if (note == null) return;
    _notes[to] = note;
    _changed();
  }

  void _changed() {
    _tagTree = null;
    _vocabulary = null;
  }

  Set<String> tagsOf(String path) => _notes[path]?.tags ?? const {};

  TagNode get tagTree => _tagTree ??= TagNode.build({
    for (final e in _notes.entries) e.key: e.value.tags,
  });

  /// Notes tagged [filter] or a tag nested below it.
  Set<String> notesTagged(String filter) => {
    for (final e in _notes.entries)
      if (e.value.tags.any((t) => tagMatches(t, filter))) e.key,
  };

  /// Every distinct word in any note, with the notes it occurs in.
  Map<String, Set<String>> get vocabulary {
    final cached = _vocabulary;
    if (cached != null) return cached;
    final vocabulary = <String, Set<String>>{};
    _notes.forEach((path, note) {
      for (final w in note.words) {
        (vocabulary[w] ??= {}).add(path);
      }
    });
    return _vocabulary = vocabulary;
  }
}
