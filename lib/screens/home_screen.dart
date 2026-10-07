import 'dart:io' show FileSystemException;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/active_store.dart';
import '../services/app_version.dart';
import '../services/note_store.dart';
import '../services/note_tree.dart';
import '../services/preferences.dart';
import '../widgets/note_editor.dart';
import '../widgets/note_tree_view.dart';
import 'fuzzy_finder.dart';
import 'preferences_screen.dart';

/// Window width from which the tree and the editor sit side by side.
const double kTwoPaneWidth = 760;

/// The notes folder as a file tree, plus the editor. On wide windows the
/// editor sits next to the tree; on phones a note opens on its own screen.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.preferences, this.storeFactory});

  final PreferencesService preferences;

  /// Optional override for tests; defaults to the folder in Preferences.
  final Future<NoteStore> Function()? storeFactory;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  NoteStore? _store;
  List<String> _notes = const [];
  NoteFolder _tree = NoteFolder.build(const []);
  final Set<String> _expanded = {};
  bool _loading = true;
  Object? _error;
  String? _selected;
  EditorMode _mode = EditorMode.raw;
  bool _editorDirty = false;

  /// A note just created here, so its editor opens focused at the end.
  String? _created;
  final GlobalKey<NoteEditorState> _editorKey = GlobalKey();

  PreferencesService get _prefs => widget.preferences;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Notes may have arrived (Syncthing) or gone while the app was away.
    if (state == AppLifecycleState.resumed && !_loading && _store != null) {
      _reload();
    }
  }

  Future<void> _init() async {
    _mode = await _prefs.editorMode();
    await _reload(reopenStore: true);
  }

  Future<void> _reload({bool reopenStore = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (reopenStore || _store == null) {
        _store =
            await (widget.storeFactory?.call() ?? configuredNoteStore(_prefs));
      }
      final notes = await _store!.list();
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _tree = NoteFolder.build(notes);
        if (_selected != null && !notes.contains(_selected)) _selected = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _notes = const [];
        _tree = NoteFolder.build(const []);
        _selected = null;
        _loading = false;
      });
    }
  }

  bool get _twoPane => MediaQuery.sizeOf(context).width >= kTwoPaneWidth;

  void _setMode(EditorMode mode) {
    _mode = mode;
    _prefs.setEditorMode(mode);
  }

  Future<void> _open(String path) async {
    final store = _store;
    if (store == null) return;
    setState(() {
      for (final folder in ancestorFolders(path)) {
        _expanded.add(folder);
      }
    });
    if (_twoPane) {
      if (path == _selected) return;
      final editor = _editorKey.currentState;
      if (editor != null && !await editor.confirmLeave()) return;
      if (!mounted) return;
      setState(() {
        _selected = path;
        _editorDirty = false;
      });
      return;
    }
    setState(() => _selected = path);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _NotePage(
          store: store,
          path: path,
          initialMode: _mode,
          autofocus: _created == path,
          onModeChanged: _setMode,
          onRename: () => _rename(path, fromNotePage: true),
          onDelete: () => _delete(path, fromNotePage: true),
        ),
      ),
    );
  }

  /// The folder new notes go into by default: that of the open note.
  String get _currentFolder {
    final selected = _selected;
    return selected == null ? '' : parentPath(selected);
  }

  Future<void> _findNote() async {
    if (_notes.isEmpty) return;
    final path = await showFuzzyFinder(context, _notes);
    if (path != null && mounted) await _open(path);
  }

  Future<void> _newNote() async {
    final store = _store;
    if (store == null) return;
    final folder = _currentFolder;
    final path = await _askPath(
      title: 'New note',
      action: 'Create',
      initial: folder.isEmpty ? '' : '$folder/',
      hint: 'folder/name.md',
    );
    if (path == null || !mounted) return;
    try {
      await store.create(path, '# ${displayName(path)}\n\n');
    } catch (e) {
      _snack('Could not create $path: $e', error: true);
      return;
    }
    _created = path;
    await _reload();
    if (mounted) await _open(path);
  }

  Future<void> _rename(String path, {bool fromNotePage = false}) async {
    final store = _store;
    if (store == null) return;
    if (!fromNotePage && path == _selected) {
      final editor = _editorKey.currentState;
      if (editor != null && !await editor.confirmLeave()) return;
    }
    if (!mounted) return;
    final target = await _askPath(
      title: 'Rename note',
      action: 'Rename',
      initial: path,
      hint: 'folder/name.md',
    );
    if (target == null || target == path || !mounted) return;
    try {
      await store.rename(path, target);
    } catch (e) {
      _snack('Could not rename $path: $e', error: true);
      return;
    }
    if (fromNotePage && mounted) Navigator.of(context).pop();
    if (_selected == path) _selected = target;
    _expanded.addAll(ancestorFolders(target));
    await _reload();
    if (mounted && _twoPane) setState(() {});
  }

  Future<void> _delete(String path, {bool fromNotePage = false}) async {
    final store = _store;
    if (store == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text(
          '$path will be deleted from the notes folder for good. '
          'There is no trash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await store.delete(path);
    } catch (e) {
      _snack('Could not delete $path: $e', error: true);
      return;
    }
    if (fromNotePage && mounted) Navigator.of(context).pop();
    if (_selected == path) {
      _selected = null;
      _editorDirty = false;
    }
    _snack('Deleted $path');
    await _reload();
  }

  Future<void> _noteMenu(String path, Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: 'rename', child: Text('Rename / move')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (!mounted) return;
    if (choice == 'rename') await _rename(path);
    if (choice == 'delete') await _delete(path);
  }

  Future<String?> _askPath({
    required String title,
    required String action,
    required String initial,
    required String hint,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _PathDialog(
        title: title,
        action: action,
        initial: initial,
        hint: hint,
        exists: _notes.contains,
      ),
    );
  }

  Future<void> _openPreferences() async {
    final editor = _editorKey.currentState;
    if (editor != null && !await editor.confirmLeave()) return;
    if (!mounted) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PreferencesScreen(preferences: _prefs)),
    );
    if (changed == true && mounted) {
      _selected = null;
      _editorDirty = false;
      _expanded.clear();
      await _init();
    }
  }

  Future<void> _showAbout() async {
    // The version comes from the bundled pubspec.yaml, never a literal here.
    String? version;
    try {
      version = await loadAppVersion(DefaultAssetBundle.of(context));
    } catch (e, st) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'quicknote',
          context: ErrorDescription('while loading the app version for About'),
        ),
      );
    }
    if (!mounted) return;
    showAboutDialog(
      context: context,
      applicationName: 'Quicknote',
      applicationVersion: version,
      applicationIcon: Image.asset('logo-small.png', width: 48, height: 48),
      applicationLegalese:
          'Edit a folder of markdown notes. Local files only; no network, '
          'no accounts, no telemetry.',
    );
  }

  static String _describe(Object error) => switch (error) {
    FileSystemException(:final message, :final path, :final osError) => [
      message,
      if (osError != null && osError.message.isNotEmpty) osError.message,
      ?path,
    ].join(': '),
    PlatformException(:final message, :final code) => message ?? code,
    _ => '$error',
  };

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final twoPane = _twoPane;
    final title = _selected != null && twoPane
        ? '${displayName(_selected!)}${_editorDirty ? ' •' : ''}'
        : 'Quicknote';
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP, control: true):
            _findNote,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _findNote,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newNote,
        const SingleActivator(LogicalKeyboardKey.f5): _reload,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, overflow: TextOverflow.ellipsis),
                if (_store != null)
                  Text(
                    _selected != null && twoPane ? _selected! : _store!.label,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
            actions: [
              IconButton(
                key: const ValueKey('find-note'),
                tooltip: 'Find note (Ctrl+P)',
                icon: const Icon(Icons.search),
                onPressed: _notes.isEmpty ? null : _findNote,
              ),
              IconButton(
                key: const ValueKey('new-note'),
                tooltip: 'New note (Ctrl+N)',
                icon: const Icon(Icons.note_add_outlined),
                onPressed: _store == null || _error != null ? null : _newNote,
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'refresh':
                      _reload();
                    case 'collapse':
                      setState(_expanded.clear);
                    case 'rename':
                      if (_selected != null) _rename(_selected!);
                    case 'delete':
                      if (_selected != null) _delete(_selected!);
                    case 'prefs':
                      _openPreferences();
                    case 'about':
                      _showAbout();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'refresh',
                    child: Text('Refresh (F5)'),
                  ),
                  const PopupMenuItem(
                    value: 'collapse',
                    child: Text('Collapse all folders'),
                  ),
                  if (twoPane && _selected != null) ...[
                    const PopupMenuItem(
                      value: 'rename',
                      child: Text('Rename / move note'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete note'),
                    ),
                  ],
                  const PopupMenuItem(
                    value: 'prefs',
                    child: Text('Preferences'),
                  ),
                  const PopupMenuItem(value: 'about', child: Text('About')),
                ],
              ),
            ],
          ),
          body: twoPane ? _twoPaneBody() : _treePane(),
        ),
      ),
    );
  }

  Widget _treePane() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Cannot read the notes folder:\n${_describe(error)}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _openPreferences,
                child: const Text('Choose notes folder'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: NoteTreeView(
        root: _tree,
        expanded: _expanded,
        selected: _selected,
        onToggleFolder: (path) => setState(() {
          if (!_expanded.remove(path)) _expanded.add(path);
        }),
        onOpen: _open,
        onNoteMenu: _noteMenu,
      ),
    );
  }

  Widget _twoPaneBody() {
    final store = _store;
    final selected = _selected;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 300, child: _treePane()),
        const VerticalDivider(width: 1),
        Expanded(
          child: _error != null || _loading
              ? const SizedBox.shrink()
              : store == null || selected == null
              ? Center(
                  child: Text(
                    _notes.isEmpty
                        ? 'Create a note with Ctrl+N.'
                        : 'Pick a note, or press Ctrl+P to find one.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : NoteEditor(
                  key: _editorKey,
                  store: store,
                  path: selected,
                  initialMode: _mode,
                  autofocus: _created == selected,
                  onModeChanged: _setMode,
                  onDirtyChanged: (d) => setState(() => _editorDirty = d),
                ),
        ),
      ],
    );
  }
}

/// A note on its own screen, for narrow (phone) layouts.
class _NotePage extends StatefulWidget {
  const _NotePage({
    required this.store,
    required this.path,
    required this.initialMode,
    required this.autofocus,
    required this.onModeChanged,
    required this.onRename,
    required this.onDelete,
  });

  final NoteStore store;
  final String path;
  final EditorMode initialMode;
  final bool autofocus;
  final ValueChanged<EditorMode> onModeChanged;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  State<_NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<_NotePage> {
  final GlobalKey<NoteEditorState> _editor = GlobalKey();
  bool _dirty = false;

  Future<void> _guarded(VoidCallback action) async {
    final editor = _editor.currentState;
    if (editor != null && !await editor.confirmLeave()) return;
    action();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final editor = _editor.currentState;
        if (editor != null && await editor.confirmLeave() && context.mounted) {
          setState(() => _dirty = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${displayName(widget.path)}${_dirty ? ' •' : ''}',
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                widget.path,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) =>
                  _guarded(v == 'rename' ? widget.onRename : widget.onDelete),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename / move')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: NoteEditor(
            key: _editor,
            store: widget.store,
            path: widget.path,
            initialMode: widget.initialMode,
            autofocus: widget.autofocus,
            onModeChanged: widget.onModeChanged,
            onDirtyChanged: (d) => setState(() => _dirty = d),
          ),
        ),
      ),
    );
  }
}

/// Asks for a note path relative to the notes folder and validates it.
class _PathDialog extends StatefulWidget {
  const _PathDialog({
    required this.title,
    required this.action,
    required this.initial,
    required this.hint,
    required this.exists,
  });

  final String title;
  final String action;
  final String initial;
  final String hint;
  final bool Function(String path) exists;

  @override
  State<_PathDialog> createState() => _PathDialogState();
}

class _PathDialogState extends State<_PathDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void initState() {
    super.initState();
    // Select the file name, not the folder, so typing replaces just that.
    final text = widget.initial;
    final start = text.lastIndexOf('/') + 1;
    var end = text.lastIndexOf('.');
    if (end < start) end = text.length;
    _controller.selection = TextSelection(baseOffset: start, extentOffset: end);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final path = normalizeNotePath(_controller.text);
      if (path != widget.initial && widget.exists(path)) {
        setState(() => _error = '$path already exists.');
        return;
      }
      Navigator.of(context).pop(path);
    } on InvalidNotePathException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const ValueKey('path-field'),
          controller: _controller,
          autofocus: true,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: widget.hint,
            helperText:
                'Relative to the notes folder. Folders are created '
                'as needed; .md is added if missing.',
            helperMaxLines: 2,
            errorText: _error,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}
