import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/active_store.dart';
import '../services/app_version.dart';
import '../services/note_store.dart';
import '../services/note_tree.dart';
import '../services/preferences.dart';
import '../widgets/feedback.dart';
import '../widgets/note_dialogs.dart';
import '../widgets/note_editor.dart';
import '../widgets/note_tree_view.dart';
import 'fuzzy_finder.dart';
import 'note_page.dart';
import 'preferences_screen.dart';

/// Window width from which the tree and the editor sit side by side.
const double kTwoPaneWidth = 760;

enum _MenuAction { refresh, collapse, rename, delete, preferences, about }

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

  /// Holds focus for the screen's shortcuts when nothing inside has it.
  final FocusNode _rootFocus = FocusNode(debugLabel: 'home');

  /// When the focused widget goes away (the editor of a deleted note, say),
  /// focus falls back to the route's scope, which sits above [_rootFocus],
  /// so Ctrl+P and friends would stop working until something is clicked.
  void _keepShortcutsReachable() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary is FocusScopeNode && _rootFocus.ancestors.contains(primary)) {
      _rootFocus.requestFocus();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_keepShortcutsReachable);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_keepShortcutsReachable);
    _rootFocus.dispose();
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
        builder: (_) => NotePage(
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
    final path = await askNotePath(
      context,
      title: 'New note',
      action: 'Create',
      initial: folder.isEmpty ? '' : '$folder/',
      exists: _notes.contains,
    );
    if (path == null || !mounted) return;
    try {
      await store.create(path, '# ${displayName(path)}\n\n');
    } catch (e) {
      _snack('Could not create $path: ${describeError(e)}', error: true);
      return;
    }
    _created = path;
    await _reload();
    if (mounted) await _open(path);
  }

  /// Renames or moves [path]. From the phone note page, that page closes
  /// and the note reopens under its new name.
  Future<void> _rename(String path, {bool fromNotePage = false}) async {
    final store = _store;
    if (store == null) return;
    if (!fromNotePage && path == _selected) {
      final editor = _editorKey.currentState;
      if (editor != null && !await editor.confirmLeave()) return;
    }
    if (!mounted) return;
    final target = await askNotePath(
      context,
      title: 'Rename note',
      action: 'Rename',
      initial: path,
      exists: _notes.contains,
    );
    if (target == null || target == path || !mounted) return;
    try {
      await store.rename(path, target);
    } catch (e) {
      _snack('Could not rename $path: ${describeError(e)}', error: true);
      return;
    }
    if (!mounted) return;
    if (fromNotePage) Navigator.of(context).pop();
    setState(() {
      if (_selected == path) _selected = target;
      _expanded.addAll(ancestorFolders(target));
    });
    await _reload();
    if (fromNotePage && mounted) await _open(target);
  }

  Future<void> _delete(String path, {bool fromNotePage = false}) async {
    final store = _store;
    if (store == null) return;
    if (!await confirmDeleteNote(context, path) || !mounted) return;
    try {
      await store.delete(path);
    } catch (e) {
      _snack('Could not delete $path: ${describeError(e)}', error: true);
      return;
    }
    if (!mounted) return;
    if (fromNotePage) Navigator.of(context).pop();
    setState(() {
      if (_selected == path) {
        _selected = null;
        _editorDirty = false;
      }
    });
    _snack('Deleted $path');
    await _reload();
  }

  Future<void> _noteMenu(String path, Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<_MenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: _MenuAction.rename, child: Text('Rename / move')),
        PopupMenuItem(value: _MenuAction.delete, child: Text('Delete')),
      ],
    );
    if (!mounted) return;
    if (choice == _MenuAction.rename) await _rename(path);
    if (choice == _MenuAction.delete) await _delete(path);
  }

  Future<void> _openPreferences() async {
    final editor = _editorKey.currentState;
    if (editor != null && !await editor.confirmLeave()) return;
    if (!mounted) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PreferencesScreen(preferences: _prefs)),
    );
    if (changed == true && mounted) {
      setState(() {
        _selected = null;
        _editorDirty = false;
        _expanded.clear();
      });
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

  void _snack(String message, {bool error = false}) {
    if (mounted) showSnack(context, message, error: error);
  }

  void _onMenu(_MenuAction action) {
    final selected = _selected;
    switch (action) {
      case _MenuAction.refresh:
        _reload();
      case _MenuAction.collapse:
        setState(_expanded.clear);
      case _MenuAction.rename:
        if (selected != null) _rename(selected);
      case _MenuAction.delete:
        if (selected != null) _delete(selected);
      case _MenuAction.preferences:
        _openPreferences();
      case _MenuAction.about:
        _showAbout();
    }
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
        focusNode: _rootFocus,
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
              PopupMenuButton<_MenuAction>(
                onSelected: _onMenu,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _MenuAction.refresh,
                    child: Text('Refresh (F5)'),
                  ),
                  const PopupMenuItem(
                    value: _MenuAction.collapse,
                    child: Text('Collapse all folders'),
                  ),
                  if (twoPane && _selected != null) ...const [
                    PopupMenuItem(
                      value: _MenuAction.rename,
                      child: Text('Rename / move note'),
                    ),
                    PopupMenuItem(
                      value: _MenuAction.delete,
                      child: Text('Delete note'),
                    ),
                  ],
                  const PopupMenuItem(
                    value: _MenuAction.preferences,
                    child: Text('Preferences'),
                  ),
                  const PopupMenuItem(
                    value: _MenuAction.about,
                    child: Text('About'),
                  ),
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
                'Cannot read the notes folder:\n${describeError(error)}',
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
