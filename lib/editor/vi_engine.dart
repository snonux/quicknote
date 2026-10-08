import 'package:flutter/widgets.dart';

/// The modes of [ViEngine].
enum ViMode {
  normal,
  insert,
  visual,
  visualLine;

  bool get isVisual => this == visual || this == visualLine;

  String get label => switch (this) {
    normal => 'NORMAL',
    insert => 'INSERT',
    visual => 'VISUAL',
    visualLine => 'VISUAL LINE',
  };
}

/// What `/`, `?` and `:` ask for: a line typed at the bottom of the editor.
enum ViPrompt {
  searchForward('/'),
  searchBackward('?'),
  command(':');

  const ViPrompt(this.prefix);
  final String prefix;
}

/// How far `>>` and `<<` shift a line: the indent of a nested Markdown list.
const kViShiftWidth = 2;

/// A subset of vi's modal editing on a [TextEditingController].
///
/// The engine never sees typed text: in insert mode the field edits itself,
/// and [handle] only takes the keys that leave it. In the other modes every
/// key is a command. Keys are the characters themselves (`d`, `G`, `$`) plus
/// `<Esc>`, `<CR>`, `<BS>` and `<C-r>`.
///
/// The caret stands for vi's cursor: a collapsed selection at offset `o`
/// is the cursor on the character at `o`. Visual mode shows its range as the
/// field's selection.
///
/// Undo is its own: every change (one command, or one stay in insert mode)
/// is one step, as in vi, rather than the field's time-sliced history.
class ViEngine extends ChangeNotifier {
  ViEngine(
    this.controller, {
    this.onYank,
    this.onPrompt,
    this.onWrite,
    this.onQuit,
  });

  final TextEditingController controller;

  /// Called with text that `y` copied, for the system clipboard.
  final ValueChanged<String>? onYank;

  /// Asks the editor for a search pattern or an ex command; it answers with
  /// [search] or [command].
  final ValueChanged<ViPrompt>? onPrompt;

  /// `:w`.
  final VoidCallback? onWrite;

  /// `:q`; `:wq` and `:x` call [onWrite] first.
  final VoidCallback? onQuit;

  ViMode _mode = ViMode.normal;
  ViMode get mode => _mode;

  /// The keys of the command typed so far, for the status line.
  String get pending => _keys.join();
  final List<String> _keys = [];

  /// A short note for the status line ("Pattern not found"), until the next key.
  String? get message => _message;
  String? _message;

  String _register = '';
  bool _registerLinewise = false;

  /// The last search, for `n` and `N`.
  String? _search;
  bool _searchForward = true;

  /// The last `f`, `F`, `t` or `T` and its character, for `;` and `,`.
  String? _find;
  String? _findChar;

  /// The column `j` and `k` aim for; -1 for the end of the line (after `$`).
  int? _column;

  int _anchor = 0;

  final List<TextEditingValue> _undo = [];
  final List<TextEditingValue> _redo = [];
  static const _undoLimit = 200;

  /// Set by u and Ctrl+R, whose change is not a new step.
  bool _movedInHistory = false;

  /// The text before the current stay in insert mode, to undo it as one.
  TextEditingValue? _insertStart;

  String get _text => controller.text;
  int get _length => controller.text.length;

  int get _caret {
    final s = controller.selection;
    return s.isValid ? s.extentOffset.clamp(0, _length) : 0;
  }

  /// Back to normal mode with no history, e.g. for another note.
  void reset() {
    _keys.clear();
    _message = null;
    _undo.clear();
    _redo.clear();
    _insertStart = null;
    _column = null;
    _setMode(ViMode.normal);
  }

  void _setMode(ViMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  /// Handles [key]; false means the field should process it as usual (any
  /// key in insert mode but `<Esc>`).
  bool handle(String key) {
    if (_mode == ViMode.insert) {
      if (key != '<Esc>') return false;
      _leaveInsert();
      return true;
    }
    _message = null;
    if (_mode == ViMode.normal) _adoptMouseSelection();
    if (_mode.isVisual) _checkVisualSelection();
    if (key == '<Esc>' && _keys.isEmpty) {
      if (_mode.isVisual) _exitVisual();
      notifyListeners();
      return true;
    }
    _keys.add(key);
    final keys = List.of(_keys);
    final before = controller.value;
    _Status status;
    try {
      status = _mode.isVisual ? _visualCommand(keys) : _normalCommand(keys);
    } on _Abort {
      status = _Status.done;
    }
    if (status != _Status.more) {
      _keys.clear();
      if (_mode == ViMode.insert) {
        _insertStart ??= before;
      } else if (!_movedInHistory) {
        _record(before);
      }
      _movedInHistory = false;
      if (_mode == ViMode.normal) _clampToLine();
    }
    notifyListeners();
    return true;
  }

  /// Answers [ViPrompt.searchForward] / [ViPrompt.searchBackward].
  void search(String pattern, {required bool forward}) {
    if (pattern.isEmpty) pattern = _search ?? '';
    if (pattern.isEmpty) return;
    _search = pattern;
    _searchForward = forward;
    _searchNext(1, sameDirection: true);
    notifyListeners();
  }

  /// Answers [ViPrompt.command]: `w`, `q`, `wq`, `x` and a line number.
  void command(String line) {
    final cmd = line.trim();
    final number = int.tryParse(cmd);
    if (number != null) {
      _moveTo(_firstNonBlank(_lineStartOf(_lineNumberToOffset(number))));
      _clampToLine();
    } else if (cmd == 'w') {
      onWrite?.call();
    } else if (cmd == 'q' || cmd == 'q!') {
      onQuit?.call();
    } else if (cmd == 'wq' || cmd == 'x') {
      onWrite?.call();
      onQuit?.call();
    } else if (cmd == '\$') {
      _moveTo(_firstNonBlank(_lineStartOf(_length)));
      _clampToLine();
    } else if (cmd.isNotEmpty) {
      _message = 'Not an editor command: $cmd';
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- history

  void _record(TextEditingValue before) {
    if (before.text == _text) return;
    _undo.add(before);
    if (_undo.length > _undoLimit) _undo.removeAt(0);
    _redo.clear();
  }

  void _leaveInsert() {
    final start = _insertStart;
    _insertStart = null;
    if (start != null) _record(start);
    _setMode(ViMode.normal);
    // Like vi, the cursor steps back onto the last typed character.
    final p = _caret;
    if (p > _lineStartOf(p)) _moveTo(p - 1);
    _clampToLine();
  }

  void _undoOrRedo(int count, {required bool redo}) {
    _movedInHistory = true;
    final from = redo ? _redo : _undo;
    final to = redo ? _undo : _redo;
    if (from.isEmpty) {
      _message = redo ? 'Already at newest change' : 'Already at oldest change';
      return;
    }
    for (var i = 0; i < count && from.isNotEmpty; i++) {
      final target = from.removeLast();
      to.add(controller.value);
      final at = target.selection.isValid
          ? target.selection.start.clamp(0, target.text.length)
          : 0;
      controller.value = TextEditingValue(
        text: target.text,
        selection: TextSelection.collapsed(offset: at),
      );
    }
  }

  // ---------------------------------------------------------------- lines

  int _lineStartOf(int p) {
    if (p <= 0) return 0;
    final i = _text.lastIndexOf('\n', p - 1);
    return i + 1;
  }

  int _lineEndOf(int p) {
    final i = _text.indexOf('\n', p.clamp(0, _length));
    return i < 0 ? _length : i;
  }

  int _lineIndexOf(int p) {
    var n = 0;
    final end = p.clamp(0, _length);
    for (var i = 0; i < end; i++) {
      if (_text.codeUnitAt(i) == 0x0A) n++;
    }
    return n;
  }

  int get _lastLineIndex => _lineIndexOf(_length);

  int _lineStartAt(int index) {
    var p = 0;
    for (var i = 0; i < index; i++) {
      final nl = _text.indexOf('\n', p);
      if (nl < 0) return p;
      p = nl + 1;
    }
    return p;
  }

  /// The start of 1-based line [number], clamped to the text.
  int _lineNumberToOffset(int number) =>
      _lineStartAt((number - 1).clamp(0, _lastLineIndex));

  int _firstNonBlank(int lineStart) {
    var p = lineStart;
    while (p < _length && (_text[p] == ' ' || _text[p] == '\t')) {
      p++;
    }
    return p;
  }

  void _moveTo(int p) {
    controller.selection = TextSelection.collapsed(offset: p.clamp(0, _length));
  }

  /// In normal mode the cursor sits on a character, never after the last one
  /// of a line.
  void _clampToLine() {
    final p = _caret;
    final start = _lineStartOf(p);
    final end = _lineEndOf(p);
    final at = end > start && p >= end ? end - 1 : p;
    if (at != p || !controller.selection.isCollapsed) _moveTo(at);
  }

  // ---------------------------------------------------------------- words

  /// 0 blank, 1 word character, 2 punctuation; with [big] every non-blank
  /// is 1.
  int _class(int i, bool big) {
    final c = _text[i];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') return 0;
    if (big) return 1;
    final u = c.codeUnitAt(0);
    final word =
        (u >= 0x30 && u <= 0x39) ||
        (u >= 0x41 && u <= 0x5A) ||
        (u >= 0x61 && u <= 0x7A) ||
        u == 0x5F ||
        u > 0x7F;
    return word ? 1 : 2;
  }

  bool _emptyLineAt(int i) =>
      i < _length && _text[i] == '\n' && (i == 0 || _text[i - 1] == '\n');

  int _nextWordStart(int p, bool big) {
    final n = _length;
    if (p >= n) return n;
    var q = p;
    final c = _class(q, big);
    if (c != 0) {
      while (q < n && _class(q, big) == c) {
        q++;
      }
    }
    while (q < n && _class(q, big) == 0) {
      if (q > p && _emptyLineAt(q)) return q;
      q++;
    }
    return q;
  }

  int _prevWordStart(int p, bool big) {
    var q = p - 1;
    if (q < 0) return 0;
    while (q > 0 && _class(q, big) == 0) {
      if (_emptyLineAt(q)) return q;
      q--;
    }
    final c = _class(q, big);
    while (q > 0 && _class(q - 1, big) == c) {
      q--;
    }
    return q;
  }

  int _wordEnd(int p, bool big) {
    final n = _length;
    var q = p + 1;
    while (q < n && _class(q, big) == 0) {
      q++;
    }
    if (q >= n) return n == 0 ? 0 : n - 1;
    final c = _class(q, big);
    while (q + 1 < n && _class(q + 1, big) == c) {
      q++;
    }
    return q;
  }

  // ---------------------------------------------------------------- motions

  /// Parses a motion at [keys][i]; null when keys are missing.
  _Motion? _motion(List<String> keys, int i, int? count) {
    if (i >= keys.length) return null;
    final key = keys[i];
    final n = count ?? 1;
    final p = _caret;
    final start = _lineStartOf(p);
    final end = _lineEndOf(p);
    switch (key) {
      case 'h':
      case '<BS>':
        return _Motion(i + 1, (p - n).clamp(start, p));
      case 'l':
      case ' ':
        return _Motion(i + 1, (p + n).clamp(p, end));
      case 'j':
      case 'k':
      case '<CR>':
      case '-':
      case '+':
        final down = key == 'j' || key == '<CR>' || key == '+';
        final line = _lineIndexOf(p);
        final target = (down ? line + n : line - n).clamp(0, _lastLineIndex);
        if (target == line && count == null) {
          return _Motion(i + 1, p, linewise: true, failed: true);
        }
        final s = _lineStartAt(target);
        if (key == 'j' || key == 'k') {
          final column = _column ??= p - start;
          final e = _lineEndOf(s);
          final at = column < 0 ? e : (s + column).clamp(s, e);
          return _Motion(i + 1, at, linewise: true, keepColumn: true);
        }
        return _Motion(i + 1, _firstNonBlank(s), linewise: true);
      case '0':
        return _Motion(i + 1, start);
      case '^':
        return _Motion(i + 1, _firstNonBlank(start));
      case '\$':
        var e = end;
        for (var k = 1; k < n && e < _length; k++) {
          e = _lineEndOf(e + 1);
        }
        _column = -1;
        return _Motion(i + 1, e, keepColumn: true);
      case 'w':
      case 'W':
        var q = p;
        for (var k = 0; k < n; k++) {
          q = _nextWordStart(q, key == 'W');
        }
        return _Motion(i + 1, q);
      case 'b':
      case 'B':
        var q = p;
        for (var k = 0; k < n; k++) {
          q = _prevWordStart(q, key == 'B');
        }
        return _Motion(i + 1, q);
      case 'e':
      case 'E':
        var q = p;
        for (var k = 0; k < n; k++) {
          q = _wordEnd(q, key == 'E');
        }
        return _Motion(i + 1, q, inclusive: true);
      case 'G':
        final s = count == null
            ? _lineStartAt(_lastLineIndex)
            : _lineNumberToOffset(count);
        return _Motion(i + 1, _firstNonBlank(s), linewise: true);
      case 'g':
        if (i + 1 >= keys.length) return null;
        if (keys[i + 1] == 'g') {
          final s = _lineNumberToOffset(count ?? 1);
          return _Motion(i + 2, _firstNonBlank(s), linewise: true);
        }
        if (keys[i + 1] == '_') {
          var e = _lineEndOf(_lineStartAt(_lineIndexOf(p) + n - 1));
          while (e > start && (_text[e - 1] == ' ' || _text[e - 1] == '\t')) {
            e--;
          }
          return _Motion(i + 2, e > 0 ? e - 1 : 0, inclusive: true);
        }
        throw const _Abort();
      case '}':
      case '{':
        var q = p;
        for (var k = 0; k < n; k++) {
          q = key == '}' ? _paragraphEnd(q) : _paragraphStart(q);
        }
        return _Motion(i + 1, q);
      case 'f':
      case 'F':
      case 't':
      case 'T':
        if (i + 1 >= keys.length) return null;
        final c = keys[i + 1];
        if (c.length != 1) throw const _Abort();
        _find = key;
        _findChar = c;
        return _findMotion(i + 2, key, c, n);
      case ';':
      case ',':
        final f = _find;
        final c = _findChar;
        if (f == null || c == null) throw const _Abort();
        final dir = key == ';'
            ? f
            : const {'f': 'F', 'F': 'f', 't': 'T', 'T': 't'}[f]!;
        return _findMotion(i + 1, dir, c, n, repeat: true);
      case '%':
        final m = _matchBracket(p);
        if (m == null) return _Motion(i + 1, p, failed: true);
        return _Motion(i + 1, m, inclusive: true);
      case 'n':
      case 'N':
      case '*':
      case '#':
        final at = _searchMotion(key, n);
        if (at == null) return _Motion(i + 1, p, failed: true);
        return _Motion(i + 1, at);
    }
    throw const _Abort();
  }

  _Motion _findMotion(
    int consumed,
    String kind,
    String c,
    int n, {
    bool repeat = false,
  }) {
    final p = _caret;
    final start = _lineStartOf(p);
    final end = _lineEndOf(p);
    var q = p;
    final forward = kind == 'f' || kind == 't';
    final till = kind == 't' || kind == 'T';
    for (var k = 0; k < n; k++) {
      // Repeating a till must not get stuck right before the same character.
      final from = forward
          ? q + 1 + (till && repeat && k == 0 ? 1 : 0)
          : q - 1 - (till && repeat && k == 0 ? 1 : 0);
      final hit = forward
          ? (from < end ? _text.indexOf(c, from) : -1)
          : (from >= start ? _text.lastIndexOf(c, from) : -1);
      if (hit < 0 || (forward && hit >= end) || (!forward && hit < start)) {
        return _Motion(consumed, p, failed: true);
      }
      q = hit;
    }
    if (till) q = forward ? q - 1 : q + 1;
    return _Motion(consumed, q, inclusive: forward);
  }

  bool _blankLine(int lineStart) {
    final e = _lineEndOf(lineStart);
    return _text.substring(lineStart, e).trim().isEmpty;
  }

  int _paragraphEnd(int p) {
    var s = _lineStartOf(p);
    while (s < _length && _blankLine(s)) {
      s = _lineEndOf(s) + 1;
    }
    while (s < _length) {
      final e = _lineEndOf(s);
      if (e >= _length) return _length;
      s = e + 1;
      if (_blankLine(s)) return s;
    }
    return _length;
  }

  int _paragraphStart(int p) {
    var s = _lineStartOf(p);
    while (s > 0 && _blankLine(s)) {
      s = _lineStartOf(s - 1);
    }
    while (s > 0) {
      s = _lineStartOf(s - 1);
      if (_blankLine(s)) return s;
    }
    return 0;
  }

  static const _pairs = {'(': ')', '[': ']', '{': '}', '<': '>'};

  int? _matchBracket(int p) {
    final end = _lineEndOf(p);
    var q = p;
    while (q < end && !'()[]{}'.contains(_text[q])) {
      q++;
    }
    if (q >= end) return null;
    final c = _text[q];
    final open = _pairs[c] != null;
    final mate = open
        ? _pairs[c]!
        : _pairs.keys.firstWhere((k) => _pairs[k] == c);
    var depth = 0;
    for (var i = q; open ? i < _length : i >= 0; open ? i++ : i--) {
      if (_text[i] == c) depth++;
      if (_text[i] == mate) depth--;
      if (depth == 0) return i;
    }
    return null;
  }

  int? _searchMotion(String key, int n) {
    if (key == '*' || key == '#') {
      final word = _wordUnderCursor();
      if (word == null) return null;
      _search = word;
      _searchForward = key == '*';
      return _findPattern(word, forward: _searchForward, n: n, from: _caret);
    }
    final pattern = _search;
    if (pattern == null) {
      _message = 'No previous search';
      return null;
    }
    final forward = key == 'n' ? _searchForward : !_searchForward;
    return _findPattern(pattern, forward: forward, n: n, from: _caret);
  }

  String? _wordUnderCursor() {
    var p = _caret;
    final end = _lineEndOf(p);
    while (p < end && _class(p, false) != 1) {
      p++;
    }
    if (p >= end) return null;
    var s = p;
    while (s > 0 && _class(s - 1, false) == 1) {
      s--;
    }
    var e = p;
    while (e < _length && _class(e, false) == 1) {
      e++;
    }
    return _text.substring(s, e);
  }

  /// Plain-text search, wrapping around; case-insensitive unless [pattern]
  /// holds a capital letter.
  int? _findPattern(
    String pattern, {
    required bool forward,
    required int n,
    required int from,
  }) {
    final smart = pattern.toLowerCase() == pattern;
    final hay = smart ? _text.toLowerCase() : _text;
    final needle = smart ? pattern.toLowerCase() : pattern;
    var at = from;
    for (var k = 0; k < n; k++) {
      int hit;
      if (forward) {
        hit = at + 1 <= hay.length ? hay.indexOf(needle, at + 1) : -1;
        if (hit < 0) hit = hay.indexOf(needle);
      } else {
        hit = at - 1 >= 0 ? hay.lastIndexOf(needle, at - 1) : -1;
        if (hit < 0) hit = hay.lastIndexOf(needle);
      }
      if (hit < 0) {
        _message = 'Pattern not found: $pattern';
        return null;
      }
      at = hit;
    }
    return at;
  }

  void _searchNext(int n, {required bool sameDirection}) {
    final pattern = _search;
    if (pattern == null) return;
    final forward = sameDirection ? _searchForward : !_searchForward;
    final at = _findPattern(pattern, forward: forward, n: n, from: _caret);
    if (at != null) _moveTo(at);
  }

  // ------------------------------------------------------------ text objects

  /// `iw`, `a"`, `i(` and friends; null while the object's key is missing.
  ({int consumed, int start, int end})? _textObject(List<String> keys, int i) {
    if (i + 1 >= keys.length) return null;
    final inner = keys[i] == 'i';
    final kind = keys[i + 1];
    final p = _caret;
    ({int start, int end})? range;
    switch (kind) {
      case 'w':
      case 'W':
        range = _wordObject(p, inner, kind == 'W');
      case '"':
      case "'":
      case '`':
        range = _quoteObject(p, kind, inner);
      case '(':
      case ')':
      case 'b':
        range = _bracketObject(p, '(', ')', inner);
      case '[':
      case ']':
        range = _bracketObject(p, '[', ']', inner);
      case '{':
      case '}':
      case 'B':
        range = _bracketObject(p, '{', '}', inner);
      case '<':
      case '>':
        range = _bracketObject(p, '<', '>', inner);
      default:
        throw const _Abort();
    }
    if (range == null) throw const _Abort();
    return (consumed: i + 2, start: range.start, end: range.end);
  }

  ({int start, int end})? _wordObject(int p, bool inner, bool big) {
    final ls = _lineStartOf(p);
    final le = _lineEndOf(p);
    if (le == ls) return null;
    final at = p.clamp(ls, le - 1);
    final c = _class(at, big);
    var s = at;
    var e = at + 1;
    while (s > ls && _class(s - 1, big) == c) {
      s--;
    }
    while (e < le && _class(e, big) == c) {
      e++;
    }
    if (inner) return (start: s, end: e);
    if (c == 0) {
      // On blanks, "a word" is the blanks and the word after them.
      if (e < le) {
        final k = _class(e, big);
        while (e < le && _class(e, big) == k) {
          e++;
        }
      }
      return (start: s, end: e);
    }
    var e2 = e;
    while (e2 < le && _class(e2, big) == 0) {
      e2++;
    }
    if (e2 > e) return (start: s, end: e2);
    var s2 = s;
    while (s2 > ls && _class(s2 - 1, big) == 0) {
      s2--;
    }
    return (start: s2, end: e);
  }

  ({int start, int end})? _quoteObject(int p, String q, bool inner) {
    final ls = _lineStartOf(p);
    final le = _lineEndOf(p);
    final quotes = <int>[];
    for (var i = ls; i < le; i++) {
      if (_text[i] == q && (i == ls || _text[i - 1] != '\\')) quotes.add(i);
    }
    for (var k = 0; k + 1 < quotes.length; k += 2) {
      final a = quotes[k];
      final b = quotes[k + 1];
      if (p <= b) {
        if (p < a && k > 0) return null;
        return inner ? (start: a + 1, end: b) : (start: a, end: b + 1);
      }
    }
    return null;
  }

  ({int start, int end})? _bracketObject(
    int p,
    String open,
    String close,
    bool inner,
  ) {
    if (_length == 0) return null;
    var depth = 0;
    var o = -1;
    for (var i = p.clamp(0, _length - 1); i >= 0; i--) {
      final c = _text[i];
      if (c == close && i != p) depth++;
      if (c == open) {
        if (depth == 0) {
          o = i;
          break;
        }
        depth--;
      }
    }
    if (o < 0) return null;
    depth = 0;
    for (var i = o; i < _length; i++) {
      final c = _text[i];
      if (c == open) depth++;
      if (c == close) {
        depth--;
        if (depth == 0) {
          return inner ? (start: o + 1, end: i) : (start: o, end: i + 1);
        }
      }
    }
    return null;
  }

  // ---------------------------------------------------------------- commands

  static int? _digit(String k, {required bool first}) {
    if (k.length != 1) return null;
    final u = k.codeUnitAt(0);
    if (u < 0x30 || u > 0x39 || (first && u == 0x30)) return null;
    return u - 0x30;
  }

  /// Reads a count at [keys][i]; returns the count (null if none) and the
  /// index after it.
  static (int?, int) _count(List<String> keys, int i) {
    int? n;
    while (i < keys.length) {
      final d = _digit(keys[i], first: n == null);
      if (d == null) break;
      n = (n ?? 0) * 10 + d;
      i++;
    }
    return (n, i);
  }

  _Status _normalCommand(List<String> keys) {
    final (count, i) = _count(keys, 0);
    if (i >= keys.length) return _Status.more;
    final key = keys[i];
    final n = count ?? 1;
    final p = _caret;
    // Anything but j and k forgets the column they were aiming for.
    if (key != 'j' && key != 'k') _column = null;
    switch (key) {
      case '<Esc>':
        return _Status.done;
      case 'd':
      case 'c':
      case 'y':
      case '>':
      case '<':
        return _operatorCommand(keys, i + 1, key, count);
      case 'x':
      case 'X':
        if (_lineEndOf(p) == _lineStartOf(p)) return _Status.done;
        final m = _motion([key == 'x' ? 'l' : 'h'], 0, n)!;
        _applyCharwise('d', p, m.target, inclusive: false);
        return _Status.done;
      case 's':
        final m = _motion(['l'], 0, n)!;
        _applyCharwise('c', p, m.target, inclusive: false);
        return _Status.done;
      case 'S':
        return _operatorCommand(['c', 'c'], 1, 'c', count);
      case 'D':
      case 'C':
        final m = _motion(['\$'], 0, n)!;
        _column = null;
        _applyCharwise(key == 'D' ? 'd' : 'c', p, m.target, inclusive: false);
        return _Status.done;
      case 'Y':
        return _operatorCommand(['y', 'y'], 1, 'y', count);
      case 'p':
      case 'P':
        _put(after: key == 'p', count: n);
        return _Status.done;
      case 'J':
        _join(_caret, n < 2 ? 2 : n);
        return _Status.done;
      case 'r':
        if (i + 1 >= keys.length) return _Status.more;
        final c = keys[i + 1] == '<CR>' ? '\n' : keys[i + 1];
        if (c.length != 1) return _Status.done;
        final e = _lineEndOf(p);
        if (p + n > e) return _Status.done;
        _replace(p, p + n, c * n);
        _moveTo(p + n - 1);
        return _Status.done;
      case '~':
        final e = (p + n).clamp(p, _lineEndOf(p));
        _replace(p, e, _toggleCase(_text.substring(p, e)));
        _moveTo(e);
        return _Status.done;
      case 'u':
        _undoOrRedo(n, redo: false);
        return _Status.done;
      case '<C-r>':
        _undoOrRedo(n, redo: true);
        return _Status.done;
      case 'i':
        _setMode(ViMode.insert);
        return _Status.done;
      case 'a':
        if (_lineEndOf(p) > p) _moveTo(p + 1);
        _setMode(ViMode.insert);
        return _Status.done;
      case 'I':
        _moveTo(_firstNonBlank(_lineStartOf(p)));
        _setMode(ViMode.insert);
        return _Status.done;
      case 'A':
        _moveTo(_lineEndOf(p));
        _setMode(ViMode.insert);
        return _Status.done;
      case 'o':
      case 'O':
        _openLine(below: key == 'o');
        return _Status.done;
      case 'v':
      case 'V':
        _anchor = p;
        _setMode(key == 'v' ? ViMode.visual : ViMode.visualLine);
        _showVisual();
        return _Status.done;
      case '/':
      case '?':
      case ':':
        onPrompt?.call(
          key == '/'
              ? ViPrompt.searchForward
              : key == '?'
              ? ViPrompt.searchBackward
              : ViPrompt.command,
        );
        return _Status.done;
    }
    final m = _motion(keys, i, count);
    if (m == null) return _Status.more;
    _moveTo(m.target);
    return _Status.done;
  }

  _Status _operatorCommand(List<String> keys, int i, String op, int? count1) {
    final (count2, j) = _count(keys, i);
    if (j >= keys.length) return _Status.more;
    final count = count1 == null && count2 == null
        ? null
        : (count1 ?? 1) * (count2 ?? 1);
    final n = count ?? 1;
    final p = _caret;
    final key = keys[j];
    if (key == op) {
      // dd, cc, yy, >>, <<: whole lines.
      final first = _lineIndexOf(p);
      final last = (first + n - 1).clamp(first, _lastLineIndex);
      _applyLinewise(op, _lineStartAt(first), _lineStartAt(last));
      return _Status.done;
    }
    if (key == 'i' || key == 'a') {
      final obj = _textObject(keys, j);
      if (obj == null) return _Status.more;
      _applyCharwise(op, obj.start, obj.end, inclusive: false);
      return _Status.done;
    }
    // cw changes to the end of the word, like ce.
    if (op == 'c' &&
        (key == 'w' || key == 'W') &&
        p < _length &&
        _class(p, key == 'W') != 0) {
      final word = _wordEndForChange(p, n, key == 'W');
      _applyCharwise(op, p, word, inclusive: true);
      return _Status.done;
    }
    final m = _motion(keys, j, count);
    if (m == null) return _Status.more;
    _column = null;
    if (m.failed) return _Status.done;
    if (m.linewise) {
      _applyLinewise(op, _lineStartOf(p), _lineStartOf(m.target));
      return _Status.done;
    }
    var target = m.target;
    if (key == 'w' || key == 'W') {
      // dw on the last word of a line stops at the line's end.
      final end = _lineEndOf(p);
      if (target > end && end > p) target = end;
    }
    _applyCharwise(op, p, target, inclusive: m.inclusive);
    return _Status.done;
  }

  int _wordEndForChange(int p, int n, bool big) {
    var q = p;
    for (var k = 0; k < n; k++) {
      // On the last character of a word, cw changes just that character.
      if (k == 0 &&
          (q + 1 >= _length || _class(q + 1, big) != _class(q, big))) {
        continue;
      }
      q = _wordEnd(q, big);
    }
    return q;
  }

  _Status _visualCommand(List<String> keys) {
    final (count, i) = _count(keys, 0);
    if (i >= keys.length) return _Status.more;
    final key = keys[i];
    final head = _visualHead;
    switch (key) {
      case '<Esc>':
        _exitVisual();
        return _Status.done;
      case 'v':
      case 'V':
        final mode = key == 'v' ? ViMode.visual : ViMode.visualLine;
        if (_mode == mode) {
          _exitVisual();
        } else {
          _setMode(mode);
          _showVisual();
        }
        return _Status.done;
      case 'o':
        final a = _anchor;
        _anchor = head;
        _setVisualHead(a);
        return _Status.done;
      case 'd':
      case 'x':
      case 'c':
      case 's':
      case 'y':
      case '>':
      case '<':
      case 'J':
      case '~':
      case 'u':
      case 'U':
        _visualOperator(key);
        return _Status.done;
      case 'i':
      case 'a':
        if (_mode != ViMode.visual) throw const _Abort();
        _moveTo(head);
        final obj = _textObject(keys, i);
        if (obj == null) {
          _setVisualHead(head);
          return _Status.more;
        }
        _anchor = obj.start;
        _setVisualHead(obj.end > obj.start ? obj.end - 1 : obj.start);
        return _Status.done;
    }
    _moveTo(head);
    final _Motion? m;
    try {
      m = _motion(keys, i, count);
    } finally {
      if (_mode.isVisual) _setVisualHead(head);
    }
    if (m == null) return _Status.more;
    if (!m.keepColumn) _column = null;
    var target = m.target;
    if (target >= _length && _length > 0) target = _length - 1;
    _setVisualHead(target);
    return _Status.done;
  }

  /// The visual range's moving end: the character under the cursor.
  int _visualHead = 0;

  void _setVisualHead(int head) {
    _visualHead = head.clamp(0, _length);
    _showVisual();
  }

  ({int start, int end}) get _visualRange {
    final a = _anchor.clamp(0, _length);
    final h = _visualHead.clamp(0, _length);
    if (_mode == ViMode.visualLine) {
      final s = _lineStartOf(a < h ? a : h);
      final e = _lineEndOf(a < h ? h : a);
      return (start: s, end: e);
    }
    final s = a < h ? a : h;
    final e = ((a < h ? h : a) + 1).clamp(0, _length);
    return (start: s, end: e);
  }

  TextSelection? _shown;

  void _showVisual() {
    if (!_mode.isVisual) return;
    final r = _visualRange;
    final forward = _visualHead >= _anchor;
    final sel = forward
        ? TextSelection(baseOffset: r.start, extentOffset: r.end)
        : TextSelection(baseOffset: r.end, extentOffset: r.start);
    _shown = sel;
    controller.selection = sel;
  }

  /// When the field's selection was changed by the mouse in visual mode,
  /// visual mode ends there.
  void _checkVisualSelection() {
    if (_shown != controller.selection) {
      _setMode(ViMode.normal);
      _adoptMouseSelection();
    }
  }

  /// A selection dragged with the mouse in normal mode becomes a visual one.
  void _adoptMouseSelection() {
    final s = controller.selection;
    if (!s.isValid || s.isCollapsed) {
      _visualHead = _caret;
      return;
    }
    _anchor = s.baseOffset;
    _visualHead = s.extentOffset > s.baseOffset
        ? s.extentOffset - 1
        : s.extentOffset;
    _setMode(ViMode.visual);
    _showVisual();
  }

  void _exitVisual() {
    final head = _visualHead;
    _setMode(ViMode.normal);
    _shown = null;
    _moveTo(head);
    _clampToLine();
  }

  void _visualOperator(String key) {
    final r = _visualRange;
    final linewise = _mode == ViMode.visualLine;
    _setMode(ViMode.normal);
    _shown = null;
    switch (key) {
      case 'J':
        final first = _lineIndexOf(r.start);
        final last = _lineIndexOf(r.end);
        _moveTo(r.start);
        _join(r.start, last - first + 1 < 2 ? 2 : last - first + 1);
        return;
      case '~':
      case 'u':
      case 'U':
        final s = _text.substring(r.start, r.end);
        _replace(
          r.start,
          r.end,
          key == '~'
              ? _toggleCase(s)
              : key == 'u'
              ? s.toLowerCase()
              : s.toUpperCase(),
        );
        _moveTo(r.start);
        return;
    }
    final op = switch (key) {
      'x' => 'd',
      's' => 'c',
      _ => key,
    };
    if (linewise || op == '>' || op == '<') {
      _applyLinewise(op, _lineStartOf(r.start), _lineStartOf(r.end));
    } else {
      _applyCharwise(op, r.start, r.end, inclusive: false);
    }
  }

  // ------------------------------------------------------------- operators

  void _replace(int start, int end, String with_) {
    final t = _text;
    controller.value = TextEditingValue(
      text: t.replaceRange(start, end, with_),
      selection: TextSelection.collapsed(offset: start + with_.length),
    );
  }

  void _applyCharwise(String op, int a, int b, {required bool inclusive}) {
    var s = a < b ? a : b;
    var e = a < b ? b : a;
    if (inclusive) e = (e + 1).clamp(0, _length);
    s = s.clamp(0, _length);
    e = e.clamp(s, _length);
    final text = _text.substring(s, e);
    switch (op) {
      case 'd':
      case 'c':
        if (text.isNotEmpty) _setRegister(text, linewise: false);
        _replace(s, e, '');
        if (op == 'c') _setMode(ViMode.insert);
      case 'y':
        _setRegister(text, linewise: false);
        onYank?.call(text);
        _moveTo(s);
      case '>':
      case '<':
        _applyLinewise(op, _lineStartOf(s), _lineStartOf(e));
    }
  }

  /// Applies [op] to the lines from the one at [a] to the one at [b].
  void _applyLinewise(String op, int a, int b) {
    final first = a < b ? a : b;
    final lastStart = a < b ? b : a;
    final lastEnd = _lineEndOf(lastStart);
    final lines = _text.substring(first, lastEnd);
    switch (op) {
      case 'y':
        _setRegister('$lines\n', linewise: true);
        onYank?.call('$lines\n');
        _moveTo(first);
      case 'd':
        _setRegister('$lines\n', linewise: true);
        if (lastEnd < _length) {
          _replace(first, lastEnd + 1, '');
          _moveTo(_firstNonBlank(first));
        } else if (first > 0) {
          _replace(first - 1, lastEnd, '');
          _moveTo(_firstNonBlank(_lineStartOf(first - 1)));
        } else {
          _replace(0, lastEnd, '');
          _moveTo(0);
        }
      case 'c':
        _setRegister('$lines\n', linewise: true);
        final indent = _text.substring(first, _firstNonBlank(first));
        _replace(first, lastEnd, indent);
        _setMode(ViMode.insert);
      case '>':
      case '<':
        final shifted = lines
            .split('\n')
            .map((l) => op == '>' ? _indent(l) : _outdent(l))
            .join('\n');
        _replace(first, lastEnd, shifted);
        _moveTo(_firstNonBlank(first));
    }
  }

  static String _indent(String line) =>
      line.trim().isEmpty ? line : '${' ' * kViShiftWidth}$line';

  static String _outdent(String line) {
    if (line.startsWith('\t')) return line.substring(1);
    var k = 0;
    while (k < kViShiftWidth && k < line.length && line[k] == ' ') {
      k++;
    }
    return line.substring(k);
  }

  static String _toggleCase(String s) => String.fromCharCodes(
    s.runes.map((r) {
      final c = String.fromCharCode(r);
      final up = c.toUpperCase();
      return (c == up ? c.toLowerCase() : up).runes.first;
    }),
  );

  void _setRegister(String text, {required bool linewise}) {
    _register = text;
    _registerLinewise = linewise;
  }

  void _put({required bool after, required int count}) {
    if (_register.isEmpty) return;
    final p = _caret;
    final text = _register * count;
    if (_registerLinewise) {
      if (after) {
        final e = _lineEndOf(p);
        if (e < _length) {
          _replace(e + 1, e + 1, text);
          _moveTo(_firstNonBlank(e + 1));
        } else {
          _replace(e, e, '\n${text.substring(0, text.length - 1)}');
          _moveTo(_firstNonBlank(e + 1));
        }
      } else {
        final s = _lineStartOf(p);
        _replace(s, s, text);
        _moveTo(_firstNonBlank(s));
      }
      return;
    }
    final at = after && _lineEndOf(p) > p ? p + 1 : p;
    _replace(at, at, text);
    _moveTo(at + text.length - 1);
  }

  void _join(int p, int lines) {
    var at = p;
    for (var k = 1; k < lines; k++) {
      final e = _lineEndOf(at);
      if (e >= _length) break;
      var next = e + 1;
      while (next < _length && (_text[next] == ' ' || _text[next] == '\t')) {
        next++;
      }
      final nextEmpty = next >= _length || _text[next] == '\n';
      final glue = nextEmpty || _text[next] == ')' || e == _lineStartOf(e)
          ? ''
          : ' ';
      var s = e;
      while (s > _lineStartOf(e) &&
          (_text[s - 1] == ' ' || _text[s - 1] == '\t')) {
        s--;
      }
      _replace(s, next, glue);
      at = s;
    }
    _moveTo(at);
  }

  void _openLine({required bool below}) {
    final p = _caret;
    final s = _lineStartOf(p);
    final indent = _text.substring(s, _firstNonBlank(s));
    if (below) {
      final e = _lineEndOf(p);
      _replace(e, e, '\n$indent');
    } else {
      _replace(s, s, '$indent\n');
      _moveTo(s + indent.length);
    }
    _setMode(ViMode.insert);
  }
}

enum _Status { done, more }

/// Ends an invalid command: its keys are dropped, as vi does.
class _Abort implements Exception {
  const _Abort();
}

class _Motion {
  _Motion(
    this.consumed,
    this.target, {
    this.linewise = false,
    this.inclusive = false,
    this.keepColumn = false,
    this.failed = false,
  });

  /// Index after the motion's keys.
  final int consumed;
  final int target;
  final bool linewise;
  final bool inclusive;

  /// j, k and $ keep aiming for the same column.
  final bool keepColumn;

  /// The motion could not move (no match, first line); operators do nothing.
  final bool failed;
}
