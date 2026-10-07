import 'package:shared_preferences/shared_preferences.dart';

import 'storage.dart';

const _kDirectory = 'Directory';
const _kScopedTreeUri = 'ScopedTreeUri';
const _kScopedTreeName = 'ScopedTreeName';
const _kEditorMode = 'EditorMode';
const _kDefaultNote = 'DefaultNote';

/// The note the home button opens unless Preferences names another.
const kDefaultNotePath = 'Quicknote.md';

/// Which editor a note opens in.
enum EditorMode {
  /// Plain text: the markdown source exactly as it is on disk.
  raw,

  /// Rendered, editable markdown (headings, lists, bold... as you type).
  wysiwyg;

  static EditorMode parse(String? raw) =>
      raw == 'wysiwyg' ? EditorMode.wysiwyg : EditorMode.raw;
}

class PreferencesService {
  Future<String> directory() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kDirectory);
    if (stored != null && stored.isNotEmpty) return stored;
    return defaultNotesDirectory();
  }

  /// The directory exactly as stored, or null while the default applies.
  Future<String?> storedDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kDirectory);
    return stored == null || stored.isEmpty ? null : stored;
  }

  Future<void> setDirectory(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDirectory, value);
  }

  /// Forget the chosen directory so [directory] falls back to the default.
  Future<void> clearDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDirectory);
  }

  /// An Android folder picked with the system picker, or null when the
  /// typed [directory] is in use.
  Future<({String uri, String name})?> scopedFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final uri = prefs.getString(_kScopedTreeUri);
    if (uri == null || uri.isEmpty) return null;
    return (
      uri: uri,
      name: prefs.getString(_kScopedTreeName) ?? 'Selected folder',
    );
  }

  Future<void> setScopedFolder(String uri, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kScopedTreeUri, uri);
    await prefs.setString(_kScopedTreeName, name);
  }

  Future<void> clearScopedFolder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kScopedTreeUri);
    await prefs.remove(_kScopedTreeName);
  }

  Future<EditorMode> editorMode() async {
    final prefs = await SharedPreferences.getInstance();
    return EditorMode.parse(prefs.getString(_kEditorMode));
  }

  Future<void> setEditorMode(EditorMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEditorMode, mode.name);
  }

  /// The note the home button opens, relative to the notes folder.
  Future<String> defaultNote() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kDefaultNote);
    return stored == null || stored.isEmpty ? kDefaultNotePath : stored;
  }

  Future<void> setDefaultNote(String path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == kDefaultNotePath) {
      await prefs.remove(_kDefaultNote);
    } else {
      await prefs.setString(_kDefaultNote, path);
    }
  }
}
