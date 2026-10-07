/// fzf-style fuzzy matching of a query against note paths.
///
/// Every query character must appear in the candidate in order (case
/// insensitive). Among matches, higher scores go to consecutive runs, to
/// characters at the start of a path segment or word, and to matches in the
/// file name rather than its folders. Whitespace splits the query into terms
/// that must all match, so `proj note` finds `projects/quicknote.md`.
class FuzzyMatch {
  const FuzzyMatch(this.candidate, this.score, this.positions);

  final String candidate;
  final int score;

  /// Indices into [candidate] of the matched characters, for highlighting.
  final List<int> positions;
}

const _kMatch = 16;
const _kConsecutive = 24;
const _kBoundary = 30;
const _kFileName = 12;
const _kGapPenalty = 1;

bool _isBoundary(String s, int i) {
  if (i == 0) return true;
  final prev = s[i - 1];
  if (prev == '/' || prev == '-' || prev == '_' || prev == ' ' || prev == '.') {
    return true;
  }
  // camelCase hump.
  final c = s[i];
  return prev.toLowerCase() == prev &&
      c.toUpperCase() == c &&
      c.toLowerCase() != c;
}

/// Scores one term against [candidate], or returns null when it does not
/// match. A small DP over candidate positions picks the best alignment
/// rather than the greedy leftmost one, so `qn` prefers the `q` and `n` that
/// start `quick-note` over earlier stray letters.
({int score, List<int> positions})? _matchTerm(String term, String candidate) {
  final lower = candidate.toLowerCase();
  final q = term.toLowerCase();
  final n = candidate.length;
  final m = q.length;
  if (m == 0) return (score: 0, positions: const []);
  if (m > n) return null;
  final fileStart = candidate.lastIndexOf('/') + 1;

  // best[j][i]: best score with query[0..j] matched and query[j] at i.
  const none = -1 << 30;
  final best = List.generate(m, (_) => List<int>.filled(n, none));
  final from = List.generate(m, (_) => List<int>.filled(n, -1));

  int charScore(int i) {
    var s = _kMatch;
    if (_isBoundary(candidate, i)) s += _kBoundary;
    if (i >= fileStart) s += _kFileName;
    return s;
  }

  for (var i = 0; i < n; i++) {
    if (lower[i] == q[0]) best[0][i] = charScore(i) - i * _kGapPenalty ~/ 4;
  }
  for (var j = 1; j < m; j++) {
    var runningBest = none;
    var runningIdx = -1;
    for (var i = j; i < n; i++) {
      // Track the best predecessor strictly before i - 1 (a gap).
      final k = i - 2;
      if (k >= 0 && best[j - 1][k] != none) {
        final v = best[j - 1][k] + k * _kGapPenalty;
        if (v > runningBest) {
          runningBest = v;
          runningIdx = k;
        }
      }
      if (lower[i] != q[j]) continue;
      var score = none;
      var idx = -1;
      if (best[j - 1][i - 1] != none) {
        score = best[j - 1][i - 1] + _kConsecutive;
        idx = i - 1;
      }
      if (runningIdx >= 0) {
        final gapped = runningBest - (i - 1) * _kGapPenalty;
        if (gapped > score) {
          score = gapped;
          idx = runningIdx;
        }
      }
      if (idx >= 0) {
        best[j][i] = score + charScore(i);
        from[j][i] = idx;
      }
    }
  }
  var end = -1;
  var top = none;
  for (var i = 0; i < n; i++) {
    if (best[m - 1][i] > top) {
      top = best[m - 1][i];
      end = i;
    }
  }
  if (end < 0) return null;
  final positions = List<int>.filled(m, 0);
  for (var j = m - 1, i = end; j >= 0; j--) {
    positions[j] = i;
    i = from[j][i];
  }
  return (score: top, positions: positions);
}

/// Scores [candidate] against all whitespace-separated terms of [query].
FuzzyMatch? fuzzyMatch(String query, String candidate) {
  final terms = query.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
  var score = 0;
  final positions = <int>{};
  for (final term in terms) {
    final match = _matchTerm(term, candidate);
    if (match == null) return null;
    score += match.score;
    positions.addAll(match.positions);
  }
  // Shorter paths win ties: `todo.md` before `archive/2023/todo-old.md`.
  score -= candidate.length ~/ 8;
  return FuzzyMatch(candidate, score, positions.toList()..sort());
}

/// All [candidates] matching [query], best first. An empty query returns
/// every candidate in its original order.
List<FuzzyMatch> fuzzyFilter(
  String query,
  Iterable<String> candidates, {
  int? limit,
}) {
  if (query.trim().isEmpty) {
    final all = [for (final c in candidates) FuzzyMatch(c, 0, const [])];
    return limit == null ? all : all.take(limit).toList();
  }
  final matches = <FuzzyMatch>[];
  for (final c in candidates) {
    final m = fuzzyMatch(query, c);
    if (m != null) matches.add(m);
  }
  matches.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.candidate.compareTo(b.candidate);
  });
  return limit == null ? matches : matches.take(limit).toList();
}
