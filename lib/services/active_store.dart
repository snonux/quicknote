import 'dart:io';

import 'directory_note_store.dart';
import 'note_store.dart';
import 'preferences.dart';
import 'saf_note_store.dart';

/// The store for the folder currently configured in Preferences: the picked
/// Android folder when there is one, else the typed directory.
///
/// The default folder (`~/Notes` on Linux) is created on first use. A folder
/// the user chose is never created here: if it is gone (an unmounted drive,
/// say), listing it fails visibly instead of quietly starting an empty one.
Future<NoteStore> configuredNoteStore(PreferencesService prefs) async {
  final folder = await prefs.scopedFolder();
  if (folder != null) return SafNoteStore(folder.uri, folder.name);
  final directory = await prefs.directory();
  if (await prefs.storedDirectory() == null) {
    try {
      await Directory(directory).create(recursive: true);
    } on FileSystemException {
      // The listing reports the problem.
    }
  }
  return DirectoryNoteStore(directory);
}
