import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor/markdown_controller.dart';
import '../services/note_store.dart';
import '../services/preferences.dart';
import 'format_toolbar.dart';

/// What the user chose when leaving a note with unsaved edits.
enum LeaveDecision { save, discard, stay }

/// Editor for one note, with a Raw / WYSIWYG switch.
///
/// Both modes edit the same markdown source (see [MarkdownEditingController]),
/// so switching is instant and never reformats anything. Saving writes back
/// to the same path. If the file changed on disk since it was opened --
/// Syncthing delivering an edit from another device, say -- the save asks
/// before overwriting it.
class NoteEditor extends StatefulWidget {
  const NoteEditor({
    super.key,
    required this.store,
    required this.path,
    required this.initialMode,
    this.onModeChanged,
    this.onDirtyChanged,
  });

  final NoteStore store;
  final String path;
  final EditorMode initialMode;
  final ValueChanged<EditorMode>? onModeChanged;
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<NoteEditor> createState() => NoteEditorState();
}

class NoteEditorState extends State<NoteEditor> {
  final MarkdownEditingController _controller = MarkdownEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  late EditorMode _mode = widget.initialMode;

  /// The text on disk as last loaded or saved; "dirty" means the field
  /// differs from it.
  String _original = '';
  bool _loading = true;
  Object? _loadError;
  bool _saving = false;
  bool _lastDirty = false;

  bool get dirty =>
      !_loading && _loadError == null && _controller.text != _original;
  EditorMode get mode => _mode;

  @override
  void initState() {
    super.initState();
    _controller.wysiwyg = _mode == EditorMode.wysiwyg;
    _controller.addListener(_onChanged);
    _load();
  }

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.store != widget.store) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
      _load();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    final d = dirty;
    if (d != _lastDirty) {
      _lastDirty = d;
      widget.onDirtyChanged?.call(d);
      setState(() {});
    }
  }

  Future<void> _load() async {
    final path = widget.path;
    try {
      final text = await widget.store.read(path);
      if (!mounted || path != widget.path) return;
      _original = text;
      _controller.value = TextEditingValue(
        text: text,
        selection: const TextSelection.collapsed(offset: 0),
      );
      _loadError = null;
    } catch (e) {
      // Show the reason instead of an empty editor: saving an empty buffer
      // over a note that merely could not be read would destroy it.
      if (!mounted || path != widget.path) return;
      _loadError = e;
    }
    setState(() => _loading = false);
    _onChanged();
  }

  void setMode(EditorMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _controller.wysiwyg = mode == EditorMode.wysiwyg;
    });
    widget.onModeChanged?.call(mode);
    _focus.requestFocus();
  }

  /// Saves; returns whether the note on disk now holds the field's text.
  Future<bool> save() async {
    if (_saving || _loading || _loadError != null) return false;
    if (!dirty) return true;
    setState(() => _saving = true);
    final text = _controller.text;
    try {
      final onDisk = await widget.store.read(widget.path);
      if (onDisk != _original && onDisk != text) {
        if (!mounted) return false;
        final overwrite = await _confirmOverwrite();
        if (!overwrite) {
          if (mounted) setState(() => _saving = false);
          return false;
        }
      }
      await widget.store.write(widget.path, text);
    } catch (e) {
      // Stay in the editor so nothing typed is lost.
      if (mounted) {
        setState(() => _saving = false);
        _snack('Could not save: $e', error: true);
      }
      return false;
    }
    if (!mounted) return true;
    _original = text;
    setState(() => _saving = false);
    _onChanged();
    _snack('Saved ${widget.path}');
    return true;
  }

  /// Puts the field back to the text loaded from disk.
  void revert() {
    _controller.value = TextEditingValue(
      text: _original,
      selection: TextSelection.collapsed(offset: _original.length),
    );
  }

  /// Asks about unsaved edits before the note is closed; true means it is
  /// fine to leave (saved, discarded, or nothing to lose).
  Future<bool> confirmLeave() async {
    if (!dirty) return true;
    final decision = await showDialog<LeaveDecision>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: Text('${widget.path} has edits that are not saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(LeaveDecision.stay),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(LeaveDecision.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(LeaveDecision.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    switch (decision) {
      case LeaveDecision.save:
        return save();
      case LeaveDecision.discard:
        return true;
      case LeaveDecision.stay:
      case null:
        return false;
    }
  }

  Future<bool> _confirmOverwrite() async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Changed on disk'),
        content: Text(
          '${widget.path} was changed outside Quicknote since you opened it. '
          'Saving replaces those changes with yours.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Overwrite'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  void _snack(String message, {bool error = false}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        duration: Duration(seconds: error ? 6 : 2),
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    const SingleActivator(LogicalKeyboardKey.keyS, control: true): save,
    const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
        _controller.toggleWrap('**'),
    const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
        _controller.toggleWrap('*'),
    const SingleActivator(LogicalKeyboardKey.keyE, control: true): () =>
        setMode(_mode == EditorMode.raw ? EditorMode.wysiwyg : EditorMode.raw),
  };

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not read ${widget.path}: $_loadError'),
        ),
      );
    }
    final theme = Theme.of(context);
    final wysiwyg = _mode == EditorMode.wysiwyg;
    final base = wysiwyg
        ? theme.textTheme.bodyLarge!.copyWith(height: 1.45)
        : theme.textTheme.bodyMedium!.copyWith(
            fontFamily: 'monospace',
            fontFamilyFallback: const ['Noto Sans Mono', 'DejaVu Sans Mono'],
            height: 1.4,
          );
    return CallbackShortcuts(
      bindings: _shortcuts,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(theme),
          if (wysiwyg) FormatToolbar(controller: _controller, focus: _focus),
          const Divider(height: 1),
          Expanded(
            child: TextField(
              key: const ValueKey('note-editor-field'),
              controller: _controller,
              focusNode: _focus,
              scrollController: _scroll,
              expands: true,
              maxLines: null,
              minLines: null,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              style: base,
              inputFormatters: [if (wysiwyg) ListContinuationFormatter()],
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(16, 12, 16, 48),
                hintText: 'Empty note',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        spacing: 8,
        runSpacing: 4,
        children: [
          SegmentedButton<EditorMode>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(
                value: EditorMode.raw,
                icon: Icon(Icons.code),
                label: Text('Raw'),
                tooltip: 'Plain markdown source (Ctrl+E toggles)',
              ),
              ButtonSegment(
                value: EditorMode.wysiwyg,
                icon: Icon(Icons.text_format),
                label: Text('WYSIWYG'),
                tooltip: 'Formatted markdown (Ctrl+E toggles)',
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setMode(s.first),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dirty)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    'Unsaved',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Revert to saved',
                icon: const Icon(Icons.undo),
                onPressed: dirty && !_saving ? revert : null,
              ),
              FilledButton.icon(
                key: const ValueKey('note-save'),
                onPressed: dirty && !_saving ? save : null,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
