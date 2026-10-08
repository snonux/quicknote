import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/note_index.dart';
import '../services/note_tree.dart';
import '../services/text_search.dart';

/// Where a search result opens: the note, and the match to select.
typedef SearchTarget = ({String path, TextSelection match});

/// Opens full-text search over [index] (null while it is still being built)
/// and returns the chosen match, or null when dismissed.
Future<SearchTarget?> showSearchDialog(
  BuildContext context,
  ValueListenable<NoteIndex?> index,
) {
  return showDialog<SearchTarget>(
    context: context,
    builder: (_) => SearchDialog(index: index),
  );
}

class SearchDialog extends StatefulWidget {
  const SearchDialog({super.key, required this.index});

  final ValueListenable<NoteIndex?> index;

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  static const _rowHeight = 78.0;

  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();
  List<SearchHit> _hits = const [];
  int _index = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    widget.index.addListener(_search);
    _search();
  }

  @override
  void dispose() {
    widget.index.removeListener(_search);
    _debounce?.cancel();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _search() {
    final index = widget.index.value;
    setState(() {
      _hits = index == null ? const [] : searchNotes(_query.text, index);
      _index = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _search);
  }

  void _move(int delta) {
    if (_hits.isEmpty) return;
    setState(() => _index = (_index + delta).clamp(0, _hits.length - 1));
    if (!_scroll.hasClients) return;
    final top = _index * _rowHeight;
    final bottom = top + _rowHeight;
    final view = _scroll.position;
    if (top < view.pixels) {
      _scroll.jumpTo(top);
    } else if (bottom > view.pixels + view.viewportDimension) {
      _scroll.jumpTo(bottom - view.viewportDimension);
    }
  }

  void _choose([int? i]) {
    // A tapped row is one on screen: open it as shown. Enter while the
    // query is still settling opens the top hit of the query as typed.
    if (i == null && (_debounce?.isActive ?? false)) {
      _debounce!.cancel();
      _search();
    }
    final at = i ?? _index;
    if (at < 0 || at >= _hits.length) return;
    final hit = _hits[at];
    Navigator.of(context).pop((
      path: hit.path,
      match: hit.snippets.isEmpty
          ? const TextSelection.collapsed(offset: 0)
          : hit.snippets.first.firstMatch,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loading = widget.index.value == null;
    final empty = _query.text.trim().isEmpty;
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
            const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
                _move(1),
            const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
                _move(-1),
            // Vi-style, as in fzf.
            const SingleActivator(LogicalKeyboardKey.keyJ, control: true): () =>
                _move(1),
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
                _move(-1),
            const SingleActivator(LogicalKeyboardKey.pageDown): () => _move(6),
            const SingleActivator(LogicalKeyboardKey.pageUp): () => _move(-6),
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  key: const ValueKey('search-query'),
                  controller: _query,
                  autofocus: true,
                  onChanged: _onQuery,
                  onSubmitted: (_) => _choose(),
                  textInputAction: TextInputAction.go,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.manage_search),
                    hintText: 'Search all notes…  (#tag filters)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixText: empty || loading ? null : '${_hits.length}',
                  ),
                ),
              ),
              Flexible(
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Text('Reading notes…'),
                          ],
                        ),
                      )
                    : _hits.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          empty
                              ? 'Type to search the text of every note. '
                                    'Small typos are forgiven.'
                              : 'Nothing found',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        itemExtent: _rowHeight,
                        itemCount: _hits.length,
                        itemBuilder: (context, i) =>
                            _row(theme, _hits[i], i == _index, i),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, SearchHit hit, bool selected, int i) {
    final folder = parentPath(hit.path);
    return Material(
      color: selected
          ? theme.colorScheme.secondaryContainer
          : Colors.transparent,
      child: InkWell(
        key: ValueKey('search-hit:${hit.path}'),
        onTap: () => _choose(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text.rich(
                TextSpan(
                  text: displayName(hit.path),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  children: [
                    if (folder.isNotEmpty)
                      TextSpan(
                        text: '  $folder',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              for (final s in hit.snippets.take(2))
                LayoutBuilder(
                  builder: (context, constraints) => Text.rich(
                    _snippetSpan(theme, s, constraints.maxWidth),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The snippet's line, starting a little before its first match so the
  /// match is visible even on long lines and narrow phone screens.
  TextSpan _snippetSpan(ThemeData theme, SearchSnippet s, double width) {
    final line = s.line;
    var from = line.length - line.trimLeft().length;
    var cut = false;
    // Roughly the characters that fit; keep the match in the first half.
    final fits = (width / 7).floor();
    final lead = (fits * 0.3).floor().clamp(8, 45);
    if (s.ranges.isNotEmpty && s.ranges.first.$1 - from > fits ~/ 2) {
      from = (s.ranges.first.$1 - lead).clamp(0, line.length);
      cut = true;
    }
    final highlight = TextStyle(
      color: theme.colorScheme.onPrimaryContainer,
      backgroundColor: theme.colorScheme.primaryContainer,
      fontWeight: FontWeight.bold,
    );
    final spans = <TextSpan>[if (cut) const TextSpan(text: '…')];
    var pos = from;
    for (final (start, end) in s.ranges) {
      if (end <= pos) continue;
      final st = start < pos ? pos : start;
      if (st > pos) spans.add(TextSpan(text: line.substring(pos, st)));
      spans.add(TextSpan(text: line.substring(st, end), style: highlight));
      pos = end;
    }
    if (pos < line.length) spans.add(TextSpan(text: line.substring(pos)));
    return TextSpan(children: spans);
  }
}
