import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'markdown_styler.dart';

/// The one text controller behind both editors. Its text is always the
/// note's markdown source; [wysiwyg] only changes how it is painted (see
/// [MarkdownStyler]), so switching editors never rewrites the note.
class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({super.text});

  /// Whether the field has focus. Without it no line shows its syntax: a
  /// leftover caret position must not keep revealing markers.
  bool _focused = false;
  set focused(bool value) {
    if (_focused == value) return;
    _focused = value;
    notifyListeners();
  }

  bool _wysiwyg = false;
  bool get wysiwyg => _wysiwyg;
  set wysiwyg(bool value) {
    if (_wysiwyg == value) return;
    _wysiwyg = value;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!_wysiwyg) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final styler = MarkdownStyler(
      base: style ?? DefaultTextStyle.of(context).style,
      scheme: Theme.of(context).colorScheme,
    );
    return styler.build(
      text,
      _focused ? selection : const TextSelection.collapsed(offset: -1),
    );
  }

  // --- Formatting commands, shared by the toolbar and the shortcuts. ---

  (int, int) _lineBounds(int offset) {
    final t = text;
    final start = offset <= 0 ? 0 : t.lastIndexOf('\n', offset - 1) + 1;
    var end = t.indexOf('\n', offset);
    if (end < 0) end = t.length;
    return (start, end);
  }

  TextSelection get _safeSelection => selection.isValid
      ? selection
      : TextSelection.collapsed(offset: text.length);

  /// Wraps the selection in [marker] (`**`, `*`, `` ` ``, `~~`), or unwraps
  /// it when it already is. With nothing selected, inserts an empty pair and
  /// puts the caret between.
  void toggleWrap(String marker) {
    final sel = _safeSelection;
    final t = text;
    final s = sel.start, e = sel.end;
    final n = marker.length;
    if (s >= n &&
        e + n <= t.length &&
        t.substring(s - n, s) == marker &&
        t.substring(e, e + n) == marker) {
      value = TextEditingValue(
        text: t.replaceRange(e, e + n, '').replaceRange(s - n, s, ''),
        selection: TextSelection(baseOffset: s - n, extentOffset: e - n),
      );
      return;
    }
    final inner = t.substring(s, e);
    if (inner.length >= 2 * n &&
        inner.startsWith(marker) &&
        inner.endsWith(marker)) {
      final un = inner.substring(n, inner.length - n);
      value = TextEditingValue(
        text: t.replaceRange(s, e, un),
        selection: TextSelection(baseOffset: s, extentOffset: s + un.length),
      );
      return;
    }
    value = TextEditingValue(
      text: t.replaceRange(s, e, '$marker$inner$marker'),
      selection: TextSelection(baseOffset: s + n, extentOffset: e + n),
    );
  }

  static final _blockPrefix = RegExp(
    r'^(\s*)(#{1,6}\s+|>\s?|[-*+]\s+\[[ xX]\]\s|[-*+]\s+|\d{1,9}[.)]\s+)?',
  );

  /// Applies [edit] to every line the selection touches, keeping the
  /// selection over the same lines afterwards.
  void _editLines(String Function(String line, int index) edit) {
    final sel = _safeSelection;
    final first = _lineBounds(sel.start).$1;
    final last = _lineBounds(sel.end).$2;
    final block = text.substring(first, last);
    final lines = block.split('\n');
    final edited = [
      for (var i = 0; i < lines.length; i++) edit(lines[i], i),
    ].join('\n');
    final delta = edited.length - block.length;
    value = TextEditingValue(
      text: text.replaceRange(first, last, edited),
      selection: sel.isCollapsed
          ? TextSelection.collapsed(
              offset: (sel.start + edited.length - block.length).clamp(
                first,
                first + edited.length,
              ),
            )
          : TextSelection(baseOffset: first, extentOffset: last + delta),
    );
  }

  /// Replaces whatever block prefix (heading, list, quote) the selected
  /// lines have with [prefix], or removes it when they already have exactly
  /// that kind. `1. ` numbers consecutive lines.
  void toggleLinePrefix(String prefix) {
    final sel = _safeSelection;
    final firstLine = text.substring(
      _lineBounds(sel.start).$1,
      _lineBounds(sel.start).$2,
    );
    final current = _blockPrefix.firstMatch(firstLine)!.group(2) ?? '';
    final numbered = prefix == '1. ';
    final same = numbered
        ? RegExp(r'^\d{1,9}[.)]\s+$').hasMatch(current)
        : _kindOf(current) == _kindOf(prefix);
    _editLines((line, i) {
      final m = _blockPrefix.firstMatch(line)!;
      final indent = m.group(1)!;
      final rest = line.substring(m.end);
      if (same) return '$indent$rest';
      final p = numbered ? '${i + 1}. ' : prefix;
      return '$indent$p$rest';
    });
  }

  static String _kindOf(String prefix) {
    final p = prefix.trim();
    if (p.startsWith('#')) return p; // heading level matters
    if (p.startsWith('>')) return '>';
    if (RegExp(r'^[-*+]\s+\[').hasMatch(p)) return 'task';
    if (RegExp(r'^[-*+]$').hasMatch(p)) return 'bullet';
    if (RegExp(r'^\d').hasMatch(p)) return 'ordered';
    return '';
  }

  void toggleHeading(int level) => toggleLinePrefix('${'#' * level} ');

  /// Ticks or unticks the task on the caret's line; turns a plain line or
  /// bullet into an open task.
  void toggleTask() {
    final (start, end) = _lineBounds(_safeSelection.start);
    final line = text.substring(start, end);
    final m = RegExp(r'^(\s*[-*+]\s+\[)([ xX])(\]\s)').firstMatch(line);
    if (m == null) {
      toggleLinePrefix('- [ ] ');
      return;
    }
    final at = start + m.group(1)!.length;
    final next = m.group(2) == ' ' ? 'x' : ' ';
    value = TextEditingValue(
      text: text.replaceRange(at, at + 1, next),
      selection: selection,
    );
  }

  /// Wraps the selection as a link and selects the URL placeholder.
  void insertLink() {
    final sel = _safeSelection;
    final label = sel.textInside(text);
    const url = 'https://';
    final inserted = '[${label.isEmpty ? 'link' : label}]($url)';
    final urlStart = sel.start + inserted.length - url.length - 1;
    value = TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, inserted),
      selection: TextSelection(
        baseOffset: urlStart,
        extentOffset: urlStart + url.length,
      ),
    );
  }
}

/// Continues lists on Enter in the WYSIWYG editor: a new line after a list
/// item starts with the same marker (numbers count up, tasks start open),
/// and Enter on an empty item ends the list instead.
class ListContinuationFormatter extends TextInputFormatter {
  static final _item = RegExp(
    r'^(\s*)([-*+]\s+\[[ xX]\]\s|[-*+]\s+|(\d{1,9})([.)])\s+|>\s?)',
  );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sel = newValue.selection;
    if (!sel.isCollapsed ||
        newValue.text.length != oldValue.text.length + 1 ||
        sel.start == 0 ||
        newValue.text[sel.start - 1] != '\n' ||
        oldValue.selection.start != sel.start - 1 ||
        !oldValue.selection.isCollapsed) {
      return newValue;
    }
    final t = newValue.text;
    final nl = sel.start - 1;
    final lineStart = t.lastIndexOf('\n', nl - 1) + 1;
    final line = t.substring(lineStart, nl);
    final m = _item.firstMatch(line);
    if (m == null) return newValue;
    if (line.substring(m.end).trim().isEmpty) {
      // Empty item: drop its marker and the new line, leaving a plain line.
      final text = t.replaceRange(lineStart, sel.start, '');
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: lineStart),
      );
    }
    var marker = m.group(2)!;
    if (m.group(3) != null) {
      marker = marker.replaceFirst(
        m.group(3)!,
        '${int.parse(m.group(3)!) + 1}',
      );
    } else {
      marker = marker.replaceFirst(RegExp(r'\[[xX]\]'), '[ ]');
    }
    final insert = '${m.group(1)}$marker';
    return TextEditingValue(
      text: t.replaceRange(sel.start, sel.start, insert),
      selection: TextSelection.collapsed(offset: sel.start + insert.length),
    );
  }
}
