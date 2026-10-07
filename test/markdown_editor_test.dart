import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quicknote/editor/markdown_controller.dart';
import 'package:quicknote/editor/markdown_styler.dart';

const sample = '''# Title

Some *italic*, **bold**, `code`, ~~gone~~ and [a link](https://x.y).
snake_case_words stay plain.

- [ ] open
- [x] done
- bullet
1. one

> quote

```
code **not bold**
```
---
| a | b |
Last''';

String plain(InlineSpan span) {
  final b = StringBuffer();
  span.visitChildren((s) {
    if (s is TextSpan && s.text != null) b.write(s.text);
    return true;
  });
  return b.toString();
}

void main() {
  final styler = MarkdownStyler(
    base: const TextStyle(fontSize: 14),
    scheme: ColorScheme.fromSeed(seedColor: Colors.teal),
  );

  group('MarkdownStyler', () {
    test('emits exactly one character per source character', () {
      for (final sel in [
        const TextSelection.collapsed(offset: -1),
        const TextSelection.collapsed(offset: 0),
        const TextSelection.collapsed(offset: 40),
        TextSelection(baseOffset: 0, extentOffset: sample.length),
      ]) {
        expect(plain(styler.build(sample, sel)).length, sample.length);
      }
    });

    test('shows the exact source on the active line', () {
      final out = plain(
        styler.build(sample, const TextSelection.collapsed(offset: 0)),
      );
      expect(out.split('\n').first, '# Title');
    });

    test('paints list and task markers as symbols elsewhere', () {
      final out = plain(
        styler.build(sample, const TextSelection.collapsed(offset: 0)),
      );
      final lines = out.split('\n');
      expect(lines[5], startsWith('- ☐'));
      expect(lines[6], startsWith('- ☑'));
      expect(lines[7], startsWith('• '));
    });

    // A smaller newline after a heading made clicks past the end of the
    // heading land on the next line.
    test('a line break takes the size of the line it ends', () {
      final span = styler.build(
        '# Big\nsmall',
        const TextSelection.collapsed(offset: -1),
      );
      final spans = <TextSpan>[];
      span.visitChildren((s) {
        if (s is TextSpan && s.text != null) spans.add(s);
        return true;
      });
      final nl = spans.firstWhere((s) => s.text == '\n');
      expect(nl.style!.fontSize, greaterThan(14));
    });

    test('empty text and a trailing newline are fine', () {
      expect(
        plain(styler.build('', const TextSelection.collapsed(offset: 0))),
        '',
      );
      expect(
        plain(styler.build('a\n', const TextSelection.collapsed(offset: 2))),
        'a\n',
      );
    });
  });

  group('MarkdownEditingController', () {
    MarkdownEditingController at(String text, int start, [int? end]) =>
        MarkdownEditingController(text: text)
          ..selection = TextSelection(
            baseOffset: start,
            extentOffset: end ?? start,
          );

    test('toggleWrap wraps and unwraps the selection', () {
      final c = at('hello world', 0, 5)..toggleWrap('**');
      expect(c.text, '**hello** world');
      expect(c.selection, const TextSelection(baseOffset: 2, extentOffset: 7));
      c.toggleWrap('**');
      expect(c.text, 'hello world');
    });

    test('toggleWrap with no selection puts the caret inside a pair', () {
      final c = at('ab', 1)..toggleWrap('`');
      expect(c.text, 'a``b');
      expect(c.selection.baseOffset, 2);
    });

    test('toggleHeading sets, changes and removes the level', () {
      final c = at('Title\nbody', 2)..toggleHeading(2);
      expect(c.text, '## Title\nbody');
      c.toggleHeading(1);
      expect(c.text, '# Title\nbody');
      c.toggleHeading(1);
      expect(c.text, 'Title\nbody');
    });

    test('list prefixes apply to every selected line and toggle off', () {
      final c = at('a\nb\nc', 0, 3)..toggleLinePrefix('1. ');
      expect(c.text, '1. a\n2. b\nc');
      c.selection = TextSelection(
        baseOffset: 0,
        extentOffset: c.text.indexOf('b') + 1,
      );
      c.toggleLinePrefix('1. ');
      expect(c.text, 'a\nb\nc');
      c.selection = const TextSelection.collapsed(offset: 0);
      c.toggleLinePrefix('- ');
      expect(c.text, '- a\nb\nc');
      c.toggleLinePrefix('> ');
      expect(c.text, '> a\nb\nc');
    });

    test('toggleTask ticks, unticks and creates tasks', () {
      final c = at('- [ ] x', 3)..toggleTask();
      expect(c.text, '- [x] x');
      c.toggleTask();
      expect(c.text, '- [ ] x');
      final d = at('plain', 0)..toggleTask();
      expect(d.text, '- [ ] plain');
    });

    test('insertLink selects the URL placeholder', () {
      final c = at('see docs', 4, 8)..insertLink();
      expect(c.text, 'see [docs](https://)');
      expect(c.selection.textInside(c.text), 'https://');
    });
  });

  group('ListContinuationFormatter', () {
    TextEditingValue enter(String before) {
      final old = TextEditingValue(
        text: before,
        selection: TextSelection.collapsed(offset: before.length),
      );
      final typed = TextEditingValue(
        text: '$before\n',
        selection: TextSelection.collapsed(offset: before.length + 1),
      );
      return ListContinuationFormatter().formatEditUpdate(old, typed);
    }

    test('continues bullets, numbers and tasks', () {
      expect(enter('- a').text, '- a\n- ');
      expect(enter('  * a').text, '  * a\n  * ');
      expect(enter('9. a').text, '9. a\n10. ');
      expect(enter('- [x] done').text, '- [x] done\n- [ ] ');
      expect(enter('> q').text, '> q\n> ');
    });

    test('Enter on an empty item ends the list', () {
      final v = enter('- a\n- ');
      expect(v.text, '- a\n');
      expect(v.selection.baseOffset, 4);
    });

    test('plain lines are left alone', () {
      expect(enter('text').text, 'text\n');
    });
  });
}
