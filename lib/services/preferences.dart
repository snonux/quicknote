import 'package:shared_preferences/shared_preferences.dart';

import 'storage.dart';

const _kDirectory = 'Directory';
const _kScopedTreeUri = 'ScopedTreeUri';
const _kScopedTreeName = 'ScopedTreeName';
const _kEditorMode = 'EditorMode';

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

  Future<void> setDirectory(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDirectory, value);
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
}
