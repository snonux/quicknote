import 'directory_note_store.dart';
import 'note_store.dart';
import 'preferences.dart';
import 'saf_note_store.dart';

/// The store for the folder currently configured in Preferences: the picked
/// Android folder when there is one, else the typed directory.
Future<NoteStore> configuredNoteStore(PreferencesService prefs) async {
  final folder = await prefs.scopedFolder();
  if (folder != null) return SafNoteStore(folder.uri, folder.name);
  return DirectoryNoteStore(await prefs.directory());
}
