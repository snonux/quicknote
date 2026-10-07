import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../services/preferences.dart';
import '../services/saf_note_store.dart';
import '../services/scoped_folder_service.dart';
import '../services/storage.dart';
import '../services/storage_access_service.dart';

/// Notes folder and editor settings. Pops `true` when something was saved.
class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({
    super.key,
    required this.preferences,
    this.scopedFolderService,
  });

  final PreferencesService preferences;
  final ScopedFolderService? scopedFolderService;

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen>
    with WidgetsBindingObserver {
  PreferencesService get _prefs => widget.preferences;
  final TextEditingController _dirController = TextEditingController();
  EditorMode _mode = EditorMode.raw;
  bool _loaded = false;
  // Whether the typed directory is actually writable -- not whether the
  // All files access permission is held. See canWriteToDirectory().
  bool _directoryWritable = true;
  ScopedFolder? _scopedFolder;
  final Set<String> _unsavedTreeUris = {};
  bool _scopedAccessible = true;
  int? _androidStorageApiLevel;

  ScopedFolderService get _folderPicker =>
      widget.scopedFolderService ?? const ScopedFolderService();

  bool get _canPickFolder =>
      Platform.isAndroid || widget.scopedFolderService != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dirController.dispose();
    // Grants picked but never saved are not kept.
    for (final uri in _unsavedTreeUris) {
      _folderPicker.release(uri);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The user may have just granted access in Settings, so re-probe rather
      // than trust what we found when the screen opened.
      _checkAccess();
    }
  }

  Future<void> _load() async {
    _dirController.text = await _prefs.directory();
    final folder = await _prefs.scopedFolder();
    _scopedFolder = folder == null
        ? null
        : ScopedFolder(folder.uri, folder.name);
    _mode = await _prefs.editorMode();
    _androidStorageApiLevel = await StorageAccessService.storageApiLevel();
    await _checkAccess();
    if (!mounted) return;
    setState(() => _loaded = true);
  }

  Future<void> _checkAccess() async {
    final folder = _scopedFolder;
    if (folder == null) {
      final writable = await canWriteToDirectory(_dirController.text);
      if (mounted) setState(() => _directoryWritable = writable);
      return;
    }
    var accessible = true;
    try {
      await SafNoteStore(folder.uri, folder.name).list();
    } catch (_) {
      accessible = false;
    }
    if (mounted) setState(() => _scopedAccessible = accessible);
  }

  Future<void> _pickScopedFolder() async {
    ScopedFolder? picked;
    try {
      picked = await _folderPicker.pick();
      if (picked == null) return;
      final saved = await _prefs.scopedFolder();
      if (picked.uri != saved?.uri) _unsavedTreeUris.add(picked.uri);
      await SafNoteStore(picked.uri, picked.name).list();
      if (!mounted) return;
      setState(() {
        _scopedFolder = picked;
        _scopedAccessible = true;
      });
    } catch (e) {
      if (picked != null && _unsavedTreeUris.remove(picked.uri)) {
        await _folderPicker.release(picked.uri);
      }
      if (!mounted) return;
      final message = e is PlatformException ? (e.message ?? e.code) : '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot use the selected folder: $message')),
      );
    }
  }

  Future<void> _requestStorageAccess() async {
    try {
      await StorageAccessService.requestStorageAccess();
      final writable = await canWriteToDirectory(_dirController.text);
      if (mounted) setState(() => _directoryWritable = writable);
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'Cannot open storage permissions.'),
        ),
      );
    }
  }

  Future<void> _resetToDefault() async {
    _dirController.text = await defaultNotesDirectory();
    setState(() => _scopedFolder = null);
    await _checkAccess();
  }

  void _useDirectory(String path) {
    _dirController.text = path;
    setState(() => _scopedFolder = null);
    _checkAccess();
  }

  Future<void> _save() async {
    final previous = await _prefs.scopedFolder();
    await _prefs.setDirectory(_dirController.text.trim());
    final folder = _scopedFolder;
    if (folder == null) {
      await _prefs.clearScopedFolder();
    } else {
      await _prefs.setScopedFolder(folder.uri, folder.name);
      _unsavedTreeUris.remove(folder.uri);
    }
    if (previous != null && previous.uri != folder?.uri) {
      await _folderPicker.release(previous.uri);
    }
    await _prefs.setEditorMode(_mode);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferences'),
        actions: [
          IconButton(
            key: const ValueKey('prefs.save'),
            tooltip: 'Save',
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_scopedFolder != null && !_scopedAccessible)
            Card(
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.folder_off),
                title: const Text('Selected folder is unavailable'),
                subtitle: const Text(
                  'Access may have been revoked. Select the folder again.',
                ),
                onTap: _canPickFolder ? _pickScopedFolder : null,
              ),
            ),
          if (_scopedFolder == null && !_directoryWritable)
            Card(
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.folder_off),
                title: const Text('Cannot write to this folder'),
                subtitle: Text(storageAccessWarning(_androidStorageApiLevel)),
                onTap: _androidStorageApiLevel == null
                    ? null
                    : _requestStorageAccess,
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Notes folder:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          TextField(
            key: const ValueKey('prefs.directory'),
            controller: _dirController,
            onChanged: (_) => setState(() => _scopedFolder = null),
            onSubmitted: (_) => _checkAccess(),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (Platform.isAndroid)
                    PopupMenuButton<String>(
                      tooltip: 'Common folders',
                      icon: const Icon(Icons.bolt),
                      onSelected: _useDirectory,
                      itemBuilder: (context) => [
                        for (final d in quickSwitchDirectories)
                          PopupMenuItem(value: d.path, child: Text(d.label)),
                      ],
                    ),
                  IconButton(
                    tooltip: 'Reset to default',
                    icon: const Icon(Icons.restore),
                    onPressed: _resetToDefault,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_canPickFolder) ...[
            OutlinedButton.icon(
              onPressed: _pickScopedFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text(
                _scopedFolder == null
                    ? 'Choose folder with Android picker'
                    : 'Selected folder: ${_scopedFolder!.name} (change)',
              ),
            ),
            if (_scopedFolder != null)
              TextButton(
                onPressed: () => setState(() => _scopedFolder = null),
                child: const Text('Use the typed path instead'),
              ),
          ],
          const SizedBox(height: 4),
          Text(
            'Every .md and .markdown file in this folder and its subfolders '
            'shows up in the file tree. Folders starting with "." (like .git '
            'or .obsidian) are skipped.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          const Text(
            'Open notes in:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          SegmentedButton<EditorMode>(
            segments: const [
              ButtonSegment(
                value: EditorMode.raw,
                label: Text('Raw'),
                icon: Icon(Icons.code),
              ),
              ButtonSegment(
                value: EditorMode.wysiwyg,
                label: Text('WYSIWYG'),
                icon: Icon(Icons.text_format),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.single),
          ),
          const SizedBox(height: 8),
          Text(
            'Both editors change the same markdown text, so switching between '
            'them never reformats a note. The editor remembers the last one '
            'you used.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
