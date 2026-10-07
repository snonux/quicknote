import 'package:flutter/material.dart';

import '../services/note_store.dart';
import '../services/note_tree.dart';
import '../services/preferences.dart';
import '../widgets/note_editor.dart';

/// A note on its own screen, for narrow (phone) layouts. Leaving with
/// unsaved edits asks first, like switching notes in the two-pane layout.
class NotePage extends StatefulWidget {
  const NotePage({
    super.key,
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

  /// Called once unsaved edits are dealt with: renaming copies the file as
  /// it is on disk.
  final VoidCallback onRename;

  /// Called as is: deleting confirms on its own, and edits to a deleted
  /// note are moot.
  final VoidCallback onDelete;

  @override
  State<NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> {
  final GlobalKey<NoteEditorState> _editor = GlobalKey();
  bool _dirty = false;

  Future<void> _rename() async {
    final editor = _editor.currentState;
    if (editor != null && !await editor.confirmLeave()) return;
    widget.onRename();
  }

  Future<void> _onPop(bool didPop) async {
    if (didPop) return;
    final editor = _editor.currentState;
    if (editor == null || !await editor.confirmLeave() || !mounted) return;
    setState(() => _dirty = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) => _onPop(didPop),
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
            PopupMenuButton<VoidCallback>(
              onSelected: (action) => action(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _rename,
                  child: const Text('Rename / move'),
                ),
                PopupMenuItem(
                  value: widget.onDelete,
                  child: const Text('Delete'),
                ),
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
