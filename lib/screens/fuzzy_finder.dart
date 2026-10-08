import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/fuzzy.dart';

/// Opens the fuzzy finder over [paths] and returns the chosen note path, or
/// null when dismissed. Type to filter, arrows to move, Enter to open.
Future<String?> showFuzzyFinder(BuildContext context, List<String> paths) {
  return showDialog<String>(
    context: context,
    builder: (_) => FuzzyFinderDialog(paths: paths),
  );
}

class FuzzyFinderDialog extends StatefulWidget {
  const FuzzyFinderDialog({super.key, required this.paths});

  final List<String> paths;

  @override
  State<FuzzyFinderDialog> createState() => _FuzzyFinderDialogState();
}

class _FuzzyFinderDialogState extends State<FuzzyFinderDialog> {
  static const _limit = 200;
  static const _rowHeight = 52.0;

  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late List<FuzzyMatch> _matches = fuzzyFilter('', widget.paths, limit: _limit);
  int _index = 0;

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    setState(() {
      _matches = fuzzyFilter(q, widget.paths, limit: _limit);
      _index = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _move(int delta) {
    if (_matches.isEmpty) return;
    setState(() => _index = (_index + delta).clamp(0, _matches.length - 1));
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
    final at = i ?? _index;
    if (at < 0 || at >= _matches.length) return;
    Navigator.of(context).pop(_matches[at].candidate);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
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
            const SingleActivator(LogicalKeyboardKey.pageDown): () => _move(8),
            const SingleActivator(LogicalKeyboardKey.pageUp): () => _move(-8),
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  key: const ValueKey('fuzzy-query'),
                  controller: _query,
                  autofocus: true,
                  onChanged: _onQuery,
                  onSubmitted: (_) => _choose(),
                  textInputAction: TextInputAction.go,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Find a note…',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixText:
                        '${_matches.length}'
                        '${_matches.length == _limit ? '+' : ''}',
                  ),
                ),
              ),
              Flexible(
                child: _matches.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No matching notes'),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        itemExtent: _rowHeight,
                        itemCount: _matches.length,
                        itemBuilder: (context, i) =>
                            _row(theme, _matches[i], i == _index, i),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, FuzzyMatch match, bool selected, int i) {
    final path = match.candidate;
    final slash = path.lastIndexOf('/');
    final hit = match.positions.toSet();
    final highlight = TextStyle(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.bold,
    );

    List<TextSpan> spans(int from, int to) => [
      for (var c = from; c < to; c++)
        TextSpan(text: path[c], style: hit.contains(c) ? highlight : null),
    ];

    return Material(
      color: selected
          ? theme.colorScheme.secondaryContainer
          : Colors.transparent,
      child: InkWell(
        onTap: () => _choose(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text.rich(
                TextSpan(children: spans(slash + 1, path.length)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (slash > 0)
                Text.rich(
                  TextSpan(
                    children: spans(0, slash),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
