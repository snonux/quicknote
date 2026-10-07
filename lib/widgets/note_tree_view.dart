import 'package:flutter/material.dart';

import '../services/note_tree.dart';

/// Collapsible folder tree of the notes folder. Folders sort first; a
/// folder row shows how many notes it holds, recursively.
class NoteTreeView extends StatelessWidget {
  const NoteTreeView({
    super.key,
    required this.root,
    required this.expanded,
    required this.selected,
    required this.onToggleFolder,
    required this.onOpen,
    this.onNoteMenu,
  });

  final NoteFolder root;
  final Set<String> expanded;
  final String? selected;
  final ValueChanged<String> onToggleFolder;
  final ValueChanged<String> onOpen;

  /// Long-press / secondary-click on a note, e.g. for rename and delete.
  final void Function(String path, Offset globalPosition)? onNoteMenu;

  @override
  Widget build(BuildContext context) {
    final rows = <_Row>[];
    void walk(NoteFolder folder, int depth) {
      for (final child in folder.folders) {
        rows.add(_Row.folder(child, depth));
        if (expanded.contains(child.path)) walk(child, depth + 1);
      }
      for (final note in folder.notes) {
        rows.add(_Row.note(note, depth));
      }
    }

    walk(root, 0);
    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No markdown notes in this folder yet.\nUse + to create one.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      key: const PageStorageKey('note-tree'),
      itemCount: rows.length,
      itemBuilder: (context, i) => _buildRow(context, rows[i]),
    );
  }

  Widget _buildRow(BuildContext context, _Row row) {
    final theme = Theme.of(context);
    final indent = 8.0 + row.depth * 16.0;
    final folder = row.folder;
    if (folder != null) {
      final open = expanded.contains(folder.path);
      return InkWell(
        key: ValueKey('folder:${folder.path}'),
        onTap: () => onToggleFolder(folder.path),
        child: Padding(
          padding: EdgeInsets.fromLTRB(indent, 8, 12, 8),
          child: Row(
            children: [
              Icon(open ? Icons.expand_more : Icons.chevron_right, size: 20),
              const SizedBox(width: 2),
              Icon(
                open ? Icons.folder_open : Icons.folder,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(folder.name, overflow: TextOverflow.ellipsis),
              ),
              Text(
                '${folder.noteCount}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final path = row.note!;
    final isSelected = path == selected;
    return Material(
      color: isSelected
          ? theme.colorScheme.secondaryContainer
          : Colors.transparent,
      child: InkWell(
        key: ValueKey('note:$path'),
        onTap: () => onOpen(path),
        onLongPress: onNoteMenu == null
            ? null
            : () {
                final box = _boxOf(context);
                onNoteMenu!(path, box);
              },
        onSecondaryTapUp: onNoteMenu == null
            ? null
            : (d) => onNoteMenu!(path, d.globalPosition),
        child: Padding(
          padding: EdgeInsets.fromLTRB(indent + 22, 8, 12, 8),
          child: Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  displayName(path),
                  overflow: TextOverflow.ellipsis,
                  style: isSelected
                      ? const TextStyle(fontWeight: FontWeight.w600)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Offset _boxOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    return box.localToGlobal(box.size.center(Offset.zero));
  }
}

/// A note's file name without its markdown extension.
String displayName(String path) {
  final name = baseName(path);
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

class _Row {
  _Row.folder(NoteFolder this.folder, this.depth) : note = null;
  _Row.note(String this.note, this.depth) : folder = null;

  final NoteFolder? folder;
  final String? note;
  final int depth;
}
