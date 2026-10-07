import 'package:flutter/material.dart';

import '../services/note_tree.dart';
import '../services/tags.dart';

/// Sections of the side list that fold away.
enum SidebarSection { pinned, recent, tags }

/// How many recent notes the Recent section lists.
const kRecentShown = 5;

/// The notes folder as a collapsible tree, with Pinned, Recent and Tags
/// sections above it. Folders sort first; a folder row shows how many notes
/// it holds, recursively. With a [tagFilter], the tree only holds the notes
/// carrying that tag, every folder open.
class NoteTreeView extends StatelessWidget {
  const NoteTreeView({
    super.key,
    required this.root,
    required this.expanded,
    required this.selected,
    required this.onToggleFolder,
    required this.onOpen,
    this.onNoteMenu,
    this.pinned = const [],
    this.recent = const [],
    this.tags,
    this.tagFilter,
    this.onTagFilter,
    this.expandedTags = const {},
    this.onToggleTag,
    this.collapsed = const {},
    this.onToggleSection,
  });

  final NoteFolder root;
  final Set<String> expanded;
  final String? selected;
  final ValueChanged<String> onToggleFolder;
  final ValueChanged<String> onOpen;

  /// Long-press / secondary-click on a note, e.g. for rename and delete.
  final void Function(String path, Offset globalPosition)? onNoteMenu;

  /// Pinned notes, in pin order; only ones that exist.
  final List<String> pinned;

  /// Recently opened notes, newest first; only ones that exist.
  final List<String> recent;

  /// The tag tree; null or empty hides the Tags section.
  final TagNode? tags;
  final String? tagFilter;

  /// Picks a tag to filter the tree by, or null to show every note.
  final ValueChanged<String?>? onTagFilter;
  final Set<String> expandedTags;
  final ValueChanged<String>? onToggleTag;

  final Set<SidebarSection> collapsed;
  final ValueChanged<SidebarSection>? onToggleSection;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final filter = tagFilter;

    if (filter != null) rows.add(_filterBar(context, filter));
    if (pinned.isNotEmpty) {
      rows.add(
        _header(context, SidebarSection.pinned, 'Pinned', Icons.push_pin),
      );
      if (!collapsed.contains(SidebarSection.pinned)) {
        for (final path in pinned) {
          rows.add(_noteRow(context, path, 0, prefix: 'pinned'));
        }
      }
    }
    if (recent.isNotEmpty) {
      rows.add(
        _header(context, SidebarSection.recent, 'Recent', Icons.history),
      );
      if (!collapsed.contains(SidebarSection.recent)) {
        for (final path in recent.take(kRecentShown)) {
          rows.add(_noteRow(context, path, 0, prefix: 'recent'));
        }
      }
    }
    final tagRoot = tags;
    if (tagRoot != null && tagRoot.children.isNotEmpty) {
      rows.add(_header(context, SidebarSection.tags, 'Tags', Icons.tag));
      if (!collapsed.contains(SidebarSection.tags)) {
        void walkTags(TagNode node, int depth) {
          for (final child in node.children) {
            rows.add(_tagRow(context, child, depth));
            if (expandedTags.contains(child.tag)) walkTags(child, depth + 1);
          }
        }

        walkTags(tagRoot, 0);
      }
    }
    final sections = rows.isNotEmpty;
    final firstNote = rows.length;
    void walk(NoteFolder folder, int depth) {
      for (final child in folder.folders) {
        rows.add(_folderRow(context, child, depth));
        if (filter != null || expanded.contains(child.path)) {
          walk(child, depth + 1);
        }
      }
      for (final note in folder.notes) {
        rows.add(_noteRow(context, note, depth));
      }
    }

    walk(root, 0);
    final noNotes = rows.length == firstNote;
    if (noNotes && filter == null && !sections) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No markdown notes in this folder yet.\nUse the new-note button to create one.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (sections) {
      rows.insert(
        firstNote,
        _plainHeader(context, 'Notes', Icons.folder_outlined),
      );
    }
    if (noNotes) {
      rows.add(
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            filter == null
                ? 'No markdown notes in this folder yet.'
                : 'No notes tagged #$filter.',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      );
    }
    return ListView.builder(
      key: const PageStorageKey('note-tree'),
      itemCount: rows.length,
      itemBuilder: (context, i) => rows[i],
    );
  }

  Widget _filterBar(BuildContext context, String filter) {
    return Padding(
      key: const ValueKey('tag-filter'),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InputChip(
          avatar: const Icon(Icons.filter_alt_outlined, size: 18),
          label: Text('#$filter'),
          tooltip: 'Showing notes tagged #$filter',
          onDeleted: () => onTagFilter?.call(null),
          deleteButtonTooltipMessage: 'Show all notes',
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    SidebarSection section,
    String title,
    IconData icon,
  ) {
    final open = !collapsed.contains(section);
    return InkWell(
      key: ValueKey('section:${section.name}'),
      onTap: onToggleSection == null ? null : () => onToggleSection!(section),
      child: _headerContent(
        context,
        title,
        icon,
        trailing: Icon(open ? Icons.expand_less : Icons.expand_more, size: 18),
      ),
    );
  }

  Widget _plainHeader(BuildContext context, String title, IconData icon) =>
      _headerContent(context, title, icon);

  Widget _headerContent(
    BuildContext context,
    String title,
    IconData icon, {
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _tagRow(BuildContext context, TagNode node, int depth) {
    final theme = Theme.of(context);
    final active = node.tag == tagFilter;
    final hasChildren = node.children.isNotEmpty;
    final open = expandedTags.contains(node.tag);
    return Material(
      color: active ? theme.colorScheme.secondaryContainer : Colors.transparent,
      child: InkWell(
        key: ValueKey('tag:${node.tag}'),
        onTap: () => onTagFilter?.call(active ? null : node.tag),
        child: Padding(
          padding: EdgeInsets.fromLTRB(8.0 + depth * 16.0, 4, 12, 4),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: hasChildren
                    ? IconButton(
                        key: ValueKey('tag-toggle:${node.tag}'),
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                        tooltip: open ? 'Collapse' : 'Expand',
                        onPressed: () => onToggleTag?.call(node.tag),
                        icon: Icon(
                          open ? Icons.expand_more : Icons.chevron_right,
                        ),
                      )
                    : null,
              ),
              Text(
                '#',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  node.name,
                  overflow: TextOverflow.ellipsis,
                  style: active
                      ? const TextStyle(fontWeight: FontWeight.w600)
                      : null,
                ),
              ),
              Text(
                '${node.notes.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _folderRow(BuildContext context, NoteFolder folder, int depth) {
    final theme = Theme.of(context);
    final indent = 8.0 + depth * 16.0;
    final open = tagFilter != null || expanded.contains(folder.path);
    return InkWell(
      key: ValueKey('folder:${folder.path}'),
      onTap: tagFilter != null ? null : () => onToggleFolder(folder.path),
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
            Expanded(child: Text(folder.name, overflow: TextOverflow.ellipsis)),
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

  /// A note row. Pinned and recent rows ([prefix]) show the folder too,
  /// since they sit outside the tree.
  Widget _noteRow(
    BuildContext context,
    String path,
    int depth, {
    String prefix = 'note',
  }) {
    final theme = Theme.of(context);
    final indent = 8.0 + depth * 16.0;
    final isSelected = path == selected;
    final inTree = prefix == 'note';
    final folder = parentPath(path);
    return Material(
      color: isSelected && inTree
          ? theme.colorScheme.secondaryContainer
          : Colors.transparent,
      child: Builder(
        builder: (rowContext) => InkWell(
          key: ValueKey('$prefix:$path'),
          onTap: () => onOpen(path),
          onLongPress: onNoteMenu == null
              ? null
              : () => onNoteMenu!(path, _boxOf(rowContext)),
          onSecondaryTapUp: onNoteMenu == null
              ? null
              : (d) => onNoteMenu!(path, d.globalPosition),
          child: Padding(
            padding: EdgeInsets.fromLTRB(indent + 22, 8, 12, 8),
            child: Row(
              children: [
                Icon(
                  prefix == 'pinned'
                      ? Icons.push_pin_outlined
                      : prefix == 'recent'
                      ? Icons.schedule
                      : Icons.description_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: displayName(path),
                      style: isSelected
                          ? const TextStyle(fontWeight: FontWeight.w600)
                          : null,
                      children: [
                        if (!inTree && folder.isNotEmpty)
                          TextSpan(
                            text: '  $folder',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
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
