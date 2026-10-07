import 'package:flutter/material.dart';

/// Styles markdown source as it would render, for the WYSIWYG editor.
///
/// The editor never converts the note to another format: the text in the
/// field is always the exact markdown on disk, so switching editors or saving
/// cannot reformat a note. What makes it WYSIWYG is how that text is painted.
/// Headings are large, `**bold**` is bold, list markers become bullets and so
/// on, and the syntax characters themselves are hidden -- except on the lines
/// the cursor or selection touches, where they show dimmed so they can be
/// edited (the way Typora or Obsidian's live preview behave).
///
/// Every character of the source is emitted exactly once, in order. A few are
/// painted as a different single character (`-` as `•`, `[ ]` as `☐`), which
/// keeps the caret and selection mapping one-to-one with the controller text.
class MarkdownStyler {
  MarkdownStyler({required this.base, required this.scheme});

  final TextStyle base;
  final ColorScheme scheme;

  static const _headingScale = [1.75, 1.5, 1.3, 1.15, 1.05, 1.0];

  static final _fence = RegExp(r'^\s{0,3}(```|~~~)');
  static final _heading = RegExp(r'^(#{1,6})(\s+)');
  static final _quote = RegExp(r'^(\s*)(>)(\s?)');
  static final _task = RegExp(r'^(\s*)([-*+])(\s+)\[([ xX])\](\s)');
  static final _bullet = RegExp(r'^(\s*)([-*+])(\s+)');
  static final _ordered = RegExp(r'^(\s*)(\d{1,9}[.)])(\s+)');
  static final _rule = RegExp(r'^\s{0,3}([-*_])(\s*\1){2,}\s*$');
  static final _tableRow = RegExp(r'^\s*\|');

  TextStyle get _mono => base.copyWith(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Noto Sans Mono', 'DejaVu Sans Mono', 'Courier'],
  );

  TextStyle get _dim =>
      base.copyWith(color: scheme.onSurface.withValues(alpha: 0.4));

  /// Effectively invisible and zero-width. Not `fontSize: 0`, which some
  /// engines treat as "inherit" and which breaks hit testing.
  static const TextStyle _hidden = TextStyle(
    fontSize: 0.01,
    color: Colors.transparent,
    letterSpacing: 0,
    wordSpacing: 0,
    backgroundColor: Colors.transparent,
    decoration: TextDecoration.none,
  );

  TextStyle _marker(bool active, [TextStyle? over]) =>
      active ? (over ?? base).merge(_dim) : _hidden;

  /// [selection] decides which lines show their syntax; pass an invalid
  /// selection to hide it everywhere.
  TextSpan build(String text, TextSelection selection) {
    final spans = <InlineSpan>[];
    final lines = _splitLines(text);
    final activeLines = _activeLineRange(lines, selection);
    final blocks = _fenceBlocks(lines);

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final active = i >= activeLines.$1 && i <= activeLines.$2;
      final block = blocks[i];
      if (block != null) {
        final blockActive =
            activeLines.$1 <= block.$2 && activeLines.$2 >= block.$1;
        _codeLine(
          line,
          isFence: i == block.$1 || i == block.$2,
          active: blockActive,
          out: spans,
        );
      } else {
        _line(line, active, spans);
      }
    }
    return TextSpan(style: base, children: spans);
  }

  /// Lines including their trailing `\n`, so the spans add up to [text].
  static List<String> _splitLines(String text) {
    final lines = <String>[];
    var start = 0;
    while (true) {
      final nl = text.indexOf('\n', start);
      if (nl < 0) {
        lines.add(text.substring(start));
        break;
      }
      lines.add(text.substring(start, nl + 1));
      start = nl + 1;
    }
    return lines;
  }

  static (int, int) _activeLineRange(List<String> lines, TextSelection sel) {
    if (!sel.isValid) return (-1, -2);
    int lineOf(int offset) {
      var pos = 0;
      for (var i = 0; i < lines.length; i++) {
        pos += lines[i].length;
        if (offset < pos) return i;
      }
      return lines.length - 1;
    }

    return (lineOf(sel.start), lineOf(sel.end));
  }

  /// For each line inside a fenced code block, the (open, close) line range
  /// of that block. An unclosed fence runs to the end, as in CommonMark.
  static List<(int, int)?> _fenceBlocks(List<String> lines) {
    final result = List<(int, int)?>.filled(lines.length, null);
    var i = 0;
    while (i < lines.length) {
      final open = _fence.firstMatch(lines[i]);
      if (open == null) {
        i++;
        continue;
      }
      final marker = open.group(1)!;
      var close = lines.length - 1;
      for (var j = i + 1; j < lines.length; j++) {
        if (lines[j].trimLeft().startsWith(marker)) {
          close = j;
          break;
        }
      }
      for (var j = i; j <= close; j++) {
        result[j] = (i, close);
      }
      i = close + 1;
    }
    return result;
  }

  void _codeLine(
    String line, {
    required bool isFence,
    required bool active,
    required List<InlineSpan> out,
  }) {
    final code = _mono.copyWith(
      backgroundColor: scheme.surfaceContainerHighest,
      fontSize: (base.fontSize ?? 14) * 0.95,
    );
    if (isFence) {
      out.add(TextSpan(text: line, style: active ? code.merge(_dim) : _hidden));
    } else {
      out.add(TextSpan(text: line, style: code));
    }
  }

  void _line(String line, bool active, List<InlineSpan> out) {
    // The newline is painted with the base style so every line keeps a
    // normal height even when its content is hidden or small.
    final hasNl = line.endsWith('\n');
    final body = hasNl ? line.substring(0, line.length - 1) : line;
    _lineBody(body, active, out);
    if (hasNl) out.add(const TextSpan(text: '\n'));
  }

  void _lineBody(String line, bool active, List<InlineSpan> out) {
    if (_rule.hasMatch(line)) {
      if (active) {
        out.add(TextSpan(text: line, style: _dim));
      } else {
        // Wide letter spacing stretches the few source characters, and the
        // strike-through draws one continuous rule across them.
        final chars = line.trim().length;
        out.add(
          TextSpan(
            text: line,
            style: base.copyWith(
              color: Colors.transparent,
              letterSpacing: chars == 0 ? 0 : 320 / chars,
              decoration: TextDecoration.lineThrough,
              decorationColor: scheme.outlineVariant,
              decorationThickness: 1.5,
            ),
          ),
        );
      }
      return;
    }

    final heading = _heading.firstMatch(line);
    if (heading != null) {
      final level = heading.group(1)!.length;
      final style = base.copyWith(
        fontSize: (base.fontSize ?? 14) * _headingScale[level - 1],
        fontWeight: FontWeight.bold,
        color: scheme.primary,
        height: 1.3,
      );
      out.add(TextSpan(text: heading.group(0), style: _marker(active, style)));
      _inline(line.substring(heading.end), style, active, out);
      return;
    }

    final quote = _quote.firstMatch(line);
    if (quote != null) {
      final style = base.copyWith(
        fontStyle: FontStyle.italic,
        color: scheme.onSurfaceVariant,
      );
      out.add(TextSpan(text: quote.group(1)));
      out.add(
        TextSpan(
          text: active ? '>' : '▍',
          style: active
              ? _dim
              : base.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                ),
        ),
      );
      out.add(TextSpan(text: quote.group(3)));
      _inline(line.substring(quote.end), style, active, out);
      return;
    }

    final task = _task.firstMatch(line);
    if (task != null) {
      final checked = task.group(4)!.toLowerCase() == 'x';
      out.add(TextSpan(text: task.group(1)));
      if (active) {
        out.add(
          TextSpan(
            text: task.group(0)!.substring(task.group(1)!.length),
            style: _dim,
          ),
        );
      } else {
        out.add(TextSpan(text: task.group(2), style: _hidden));
        out.add(TextSpan(text: task.group(3), style: _hidden));
        out.add(
          TextSpan(
            text: checked ? '☑' : '☐',
            style: base.copyWith(color: scheme.primary),
          ),
        );
        out.add(TextSpan(text: task.group(4), style: _hidden));
        out.add(TextSpan(text: ']', style: _hidden));
        out.add(TextSpan(text: task.group(5)));
      }
      final style = checked
          ? base.copyWith(
              decoration: TextDecoration.lineThrough,
              color: scheme.onSurface.withValues(alpha: 0.55),
            )
          : base;
      _inline(line.substring(task.end), style, active, out);
      return;
    }

    final bullet = _bullet.firstMatch(line);
    if (bullet != null) {
      out.add(TextSpan(text: bullet.group(1)));
      out.add(
        TextSpan(
          text: active ? bullet.group(2) : '•',
          style: base.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      out.add(TextSpan(text: bullet.group(3)));
      _inline(line.substring(bullet.end), base, active, out);
      return;
    }

    final ordered = _ordered.firstMatch(line);
    if (ordered != null) {
      out.add(TextSpan(text: ordered.group(1)));
      out.add(
        TextSpan(
          text: ordered.group(2),
          style: base.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      out.add(TextSpan(text: ordered.group(3)));
      _inline(line.substring(ordered.end), base, active, out);
      return;
    }

    if (_tableRow.hasMatch(line)) {
      out.add(TextSpan(text: line, style: _mono));
      return;
    }

    _inline(line, base, active, out);
  }

  static final List<RegExp> _inlinePatterns = [
    // 0: code span
    RegExp(r'`([^`\n]+)`'),
    // 1: image or link
    RegExp(r'(!?)\[([^\]\n]*)\]\(([^)\n]*)\)'),
    // 2: bold
    RegExp(r'(\*\*|__)(?=\S)(.+?)(?<=\S)\1'),
    // 3: strikethrough
    RegExp(r'~~(?=\S)(.+?)(?<=\S)~~'),
    // 4: italic with *
    RegExp(r'(?<![\w*])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?!\*)'),
    // 5: italic with _ (not inside snake_case words)
    RegExp(r'(?<![\w_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\w_])'),
    // 6: bare URL
    RegExp(r'https?://[^\s<>()\[\]]+[^\s<>()\[\].,;:!?]'),
  ];

  /// Inline markup inside one line: the earliest match wins, its content is
  /// styled recursively, and its delimiters are hidden unless [active].
  void _inline(
    String text,
    TextStyle style,
    bool active,
    List<InlineSpan> out,
  ) {
    var pos = 0;
    while (pos < text.length) {
      Match? best;
      var bestKind = -1;
      for (var k = 0; k < _inlinePatterns.length; k++) {
        final m = _inlinePatterns[k].allMatches(text, pos).firstOrNull;
        if (m != null && (best == null || m.start < best.start)) {
          best = m;
          bestKind = k;
        }
      }
      if (best == null) {
        out.add(TextSpan(text: text.substring(pos), style: style));
        return;
      }
      if (best.start > pos) {
        out.add(TextSpan(text: text.substring(pos, best.start), style: style));
      }
      _inlineMatch(bestKind, best, style, active, out);
      pos = best.end;
    }
  }

  void _inlineMatch(
    int kind,
    Match m,
    TextStyle style,
    bool active,
    List<InlineSpan> out,
  ) {
    final whole = m.group(0)!;
    switch (kind) {
      case 0:
        final code = style
            .merge(_mono)
            .copyWith(backgroundColor: scheme.surfaceContainerHighest);
        out.add(TextSpan(text: '`', style: _marker(active, code)));
        out.add(TextSpan(text: m.group(1), style: code));
        out.add(TextSpan(text: '`', style: _marker(active, code)));
      case 1:
        final bang = m.group(1)!;
        final label = m.group(2)!;
        final link = style.copyWith(
          color: scheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: scheme.primary,
        );
        out.add(TextSpan(text: '$bang[', style: _marker(active, style)));
        if (bang.isNotEmpty) {
          // Images cannot be shown inline in a text field; label them.
          out.add(
            TextSpan(
              text: label,
              style: link.copyWith(fontStyle: FontStyle.italic),
            ),
          );
        } else {
          _inline(label, link, active, out);
        }
        out.add(
          TextSpan(
            text: whole.substring(bang.length + 1 + label.length),
            style: _marker(active, style),
          ),
        );
      case 2:
        final d = m.group(1)!;
        final bold = style.copyWith(fontWeight: FontWeight.bold);
        out.add(TextSpan(text: d, style: _marker(active, bold)));
        _inline(m.group(2)!, bold, active, out);
        out.add(TextSpan(text: d, style: _marker(active, bold)));
      case 3:
        final strike = style.copyWith(decoration: TextDecoration.lineThrough);
        out.add(TextSpan(text: '~~', style: _marker(active, strike)));
        _inline(m.group(1)!, strike, active, out);
        out.add(TextSpan(text: '~~', style: _marker(active, strike)));
      case 4:
      case 5:
        final d = whole[0];
        final italic = style.copyWith(fontStyle: FontStyle.italic);
        out.add(TextSpan(text: d, style: _marker(active, italic)));
        _inline(m.group(1)!, italic, active, out);
        out.add(TextSpan(text: d, style: _marker(active, italic)));
      case 6:
        out.add(
          TextSpan(
            text: whole,
            style: style.copyWith(
              color: scheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: scheme.primary,
            ),
          ),
        );
    }
  }
}
