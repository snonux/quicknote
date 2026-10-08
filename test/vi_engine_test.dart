import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turbonotes/editor/vi_engine.dart';

/// Text with `|` marking the caret, as in the expectations below.
TextEditingController at(String marked) {
  final i = marked.indexOf('|');
  return TextEditingController(text: marked.replaceFirst('|', ''))
    ..selection = TextSelection.collapsed(offset: i);
}

String show(TextEditingController c) {
  final s = c.selection;
  if (!s.isCollapsed) {
    return '${c.text.substring(0, s.start)}[${c.text.substring(s.start, s.end)}]'
        '${c.text.substring(s.end)}';
  }
  return c.text.replaceRange(s.baseOffset, s.baseOffset, '|');
}

/// Feeds [keys]: characters, or `<Esc>`-style names.
void type(ViEngine vi, String keys) {
  final re = RegExp(r'<[A-Za-z-]+>|.', dotAll: true);
  for (final m in re.allMatches(keys)) {
    vi.handle(m.group(0)!);
  }
}

String run(String marked, String keys, {List<String>? yanks}) {
  final c = at(marked);
  final vi = ViEngine(c, onYank: yanks?.add);
  type(vi, keys);
  return show(c);
}

void main() {
  group('motions', () {
    test('h and l stay on the line', () {
      expect(run('ab|c\ndef', 'l'), 'ab|c\ndef');
      expect(run('abc\n|def', 'h'), 'abc\n|def');
      expect(run('a|bcd', '2l'), 'abc|d');
    });

    test('j and k keep the column', () {
      expect(run('ab|cd\nx\nabcd', 'jj'), 'abcd\nx\nab|cd');
      expect(run('abcd\nx\nab|cd', 'k'), 'abcd\n|x\nabcd');
      expect(run('a|bcd\nab\nabcd', '\$jj'), 'abcd\nab\nabc|d');
    });

    test('words', () {
      expect(run('|foo bar.baz qux', 'w'), 'foo |bar.baz qux');
      expect(run('|foo bar.baz qux', 'ww'), 'foo bar|.baz qux');
      expect(run('|foo bar.baz qux', '2W'), 'foo bar.baz |qux');
      expect(run('foo bar.baz |qux', 'b'), 'foo bar.|baz qux');
      expect(run('foo bar.baz |qux', 'B'), 'foo |bar.baz qux');
      expect(run('|foo bar', 'e'), 'fo|o bar');
      expect(run('|foo\n\nbar', 'w'), 'foo\n|\nbar');
    });

    test('line starts and ends', () {
      expect(run('  ab|c', '0'), '|  abc');
      expect(run('  ab|c', '^'), '  |abc');
      expect(run('|abc\nd', '\$'), 'ab|c\nd');
    });

    test('gg, G and a line number', () {
      expect(run('a\nb\n  |c', 'gg'), '|a\nb\n  c');
      expect(run('|a\nb\n  c', 'G'), 'a\nb\n  |c');
      expect(run('|a\nb\nc', '2G'), 'a\n|b\nc');
      expect(run('|a\nb\nc', '3gg'), 'a\nb\n|c');
    });

    test('find in line, repeated', () {
      expect(run('|a,b,c,d', 'f,'), 'a|,b,c,d');
      expect(run('|a,b,c,d', 'f,;;'), 'a,b,c|,d');
      expect(run('|a,b,c,d', 't,;'), 'a,|b,c,d');
      expect(run('a,b,c,|d', 'F,'), 'a,b,c|,d');
      expect(run('|a,b,c,d', 'f,;,'), 'a|,b,c,d');
    });

    test('paragraphs and brackets', () {
      expect(run('|a\nb\n\nc', '}'), 'a\nb\n|\nc');
      expect(run('a\n\nb\n|c', '{'), 'a\n|\nb\nc');
      expect(run('|f(a(b)c)', '%'), 'f(a(b)c|)');
      expect(run('f(a(b)c|)', '%'), 'f|(a(b)c)');
    });

    test('search forward, backward and the word under the cursor', () {
      final c = at('|one two One two');
      final vi = ViEngine(c);
      vi.search('two', forward: true);
      expect(show(c), 'one |two One two');
      type(vi, 'n');
      expect(show(c), 'one two One |two');
      type(vi, 'N');
      expect(show(c), 'one |two One two');
      vi.search('One', forward: true);
      expect(show(c), 'one two |One two');
      type(vi, 'gg*');
      expect(
        show(c),
        'one two |One two',
        reason: 'smartcase: lower matches all',
      );
      vi.search('nope', forward: true);
      expect(vi.message, 'Pattern not found: nope');
    });
  });

  group('operators', () {
    test('dw, de, d\$, dd and counts', () {
      expect(run('|foo bar baz', 'dw'), '|bar baz');
      expect(run('|foo bar baz', 'd2w'), '|baz');
      expect(run('|foo bar baz', '2dw'), '|baz');
      expect(run('foo |bar', 'dw'), 'foo| ');
      expect(run('|foo bar', 'de'), '| bar');
      expect(run('foo |bar baz', 'D'), 'foo| ');
      expect(run('a\n|b\nc', 'dd'), 'a\n|c');
      expect(run('a\nb\n|c', 'dd'), 'a\n|b');
      expect(run('|a\nb\nc', '2dd'), '|c');
      expect(run('|a\nb\nc', 'dj'), '|c');
      expect(run('a\nb\n|c', 'dgg'), '|');
    });

    test('dw on the last word of a line keeps the newline', () {
      expect(run('a |bc\nd', 'dw'), 'a| \nd');
    });

    test('x, X, r, ~ and J', () {
      expect(run('a|bcd', 'x'), 'a|cd');
      expect(run('a|bcd', '2x'), 'a|d');
      expect(run('ab|cd', 'X'), 'a|cd');
      expect(run('a|bc', 'rx'), 'a|xc');
      expect(run('|abc', '2~'), 'AB|c');
      expect(run('|a\n  b', 'J'), 'a| b');
      expect(run('|a\nb\nc', '3J'), 'a b| c');
    });

    test('change enters insert mode, one undo step', () {
      final c = at('foo |bar baz');
      final vi = ViEngine(c);
      type(vi, 'cw');
      expect(vi.mode, ViMode.insert);
      expect(show(c), 'foo | baz');
      // The field types on its own in insert mode.
      expect(vi.handle('x'), isFalse);
      c.value = const TextEditingValue(
        text: 'foo qux baz',
        selection: TextSelection.collapsed(offset: 7),
      );
      type(vi, '<Esc>');
      expect(vi.mode, ViMode.normal);
      expect(show(c), 'foo qu|x baz');
      type(vi, 'u');
      expect(c.text, 'foo bar baz');
      type(vi, '<C-r>');
      expect(c.text, 'foo qux baz');
    });

    test('cw on a word end, ciw, ci" and di(', () {
      expect(run('fo|o bar', 'cw'), 'fo| bar');
      expect(run('foo b|ar baz', 'ciw'), 'foo | baz');
      expect(run('foo b|ar baz', 'daw'), 'foo |baz');
      expect(run('say "he|llo" now', 'ci"'), 'say "|" now');
      expect(run('say "he|llo" now', 'da"'), 'say | now');
      expect(run('f(a, (b|), c)', 'di('), 'f(a, (|), c)');
      expect(run('f(a, (b), |c)', 'di('), 'f(|)');
      expect(run('[a|b]', 'ca['), '|');
    });

    test('cc keeps the indent, S too', () {
      expect(run('x\n  fo|o\ny', 'cc'), 'x\n  |\ny');
      expect(run('  fo|o', 'S'), '  |');
    });

    test('yank and put, charwise and linewise', () {
      final yanks = <String>[];
      expect(run('|foo bar', 'ywP', yanks: yanks), 'foo| foo bar');
      expect(yanks, ['foo ']);
      expect(run('|a\nb', 'yyp'), 'a\n|a\nb');
      expect(run('a\n|b', 'yyp'), 'a\nb\n|b');
      expect(run('a\n|b', 'yyP'), 'a\n|b\nb');
      expect(run('|a\nb', 'ddp'), 'b\n|a');
      expect(run('|ab', 'xp'), 'b|a');
      expect(run('|ab', 'yl3p'), 'aaa|ab');
    });

    test('indent and outdent lines', () {
      expect(run('|- a\n- b', '>j'), '  |- a\n  - b');
      expect(run('  |- a', '<<'), '|- a');
      expect(run('|a\n\nb', '>2j'), '  |a\n\n  b');
    });

    test('o and O open a line with the same indent', () {
      final c = at('  |- a');
      final vi = ViEngine(c);
      type(vi, 'o');
      expect(vi.mode, ViMode.insert);
      expect(show(c), '  - a\n  |');
      expect(run('|a\nb', 'O'), '|\na\nb');
    });

    test('invalid commands are dropped', () {
      final c = at('|abc');
      final vi = ViEngine(c);
      type(vi, 'dq');
      expect(vi.pending, '');
      type(vi, 'x');
      expect(show(c), '|bc');
    });

    test('a pending command shows, Esc cancels it', () {
      final c = at('|abc');
      final vi = ViEngine(c);
      type(vi, '2d');
      expect(vi.pending, '2d');
      type(vi, '<Esc>');
      expect(vi.pending, '');
      expect(c.text, 'abc');
    });
  });

  group('insert mode', () {
    test('i, a, I and A', () {
      String enter(String marked, String key) {
        final c = at(marked);
        final vi = ViEngine(c);
        type(vi, key);
        expect(vi.mode, ViMode.insert);
        return show(c);
      }

      expect(enter('a|bc', 'i'), 'a|bc');
      expect(enter('a|bc', 'a'), 'ab|c');
      expect(enter('  a|bc', 'I'), '  |abc');
      expect(enter('a|bc\nd', 'A'), 'abc|\nd');
    });

    test('Esc steps back onto the last character', () {
      final c = at('abc|');
      final vi = ViEngine(c)..handle('i');
      vi.handle('<Esc>');
      expect(show(c), 'ab|c');
    });

    test('an insert that typed nothing leaves no undo step', () {
      final c = at('|abc');
      final vi = ViEngine(c);
      type(vi, 'x');
      type(vi, 'i<Esc>');
      type(vi, 'u');
      expect(c.text, 'abc');
    });
  });

  group('visual mode', () {
    test('v selects through the cursor and d deletes it', () {
      final c = at('a|bcd');
      final vi = ViEngine(c);
      type(vi, 'vl');
      expect(vi.mode, ViMode.visual);
      expect(show(c), 'a[bc]d');
      type(vi, 'd');
      expect(vi.mode, ViMode.normal);
      expect(show(c), 'a|d');
    });

    test('backwards, o swaps the ends', () {
      final c = at('ab|cd');
      final vi = ViEngine(c);
      type(vi, 'vh');
      expect(show(c), 'a[bc]d');
      type(vi, 'ol');
      expect(show(c), 'a[bcd]');
    });

    test('V works on lines; y yanks them', () {
      final yanks = <String>[];
      final c = at('a\n|b\nc');
      final vi = ViEngine(c, onYank: yanks.add);
      type(vi, 'Vj');
      expect(vi.mode, ViMode.visualLine);
      type(vi, 'y');
      expect(yanks, ['b\nc\n']);
      type(vi, 'P');
      expect(c.text, 'a\nb\nc\nb\nc');
    });

    test('viw and c', () {
      final c = at('foo b|ar baz');
      final vi = ViEngine(c);
      type(vi, 'viwc');
      expect(vi.mode, ViMode.insert);
      expect(show(c), 'foo | baz');
    });

    test('Esc leaves visual mode on the cursor', () {
      final c = at('|abcd');
      final vi = ViEngine(c);
      type(vi, 'vll<Esc>');
      expect(vi.mode, ViMode.normal);
      expect(show(c), 'ab|cd');
    });

    test('a mouse selection in normal mode becomes visual', () {
      final c = at('|abcd');
      final vi = ViEngine(c);
      c.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
      type(vi, 'd');
      expect(show(c), 'a|d');
    });
  });

  group('ex commands', () {
    test(':w, :q, :wq and a line number', () {
      final calls = <String>[];
      final c = at('|a\nb\nc');
      final vi = ViEngine(
        c,
        onWrite: () => calls.add('w'),
        onQuit: () => calls.add('q'),
      );
      vi.command('w');
      vi.command('q');
      vi.command('wq');
      vi.command('x');
      expect(calls, ['w', 'q', 'w', 'q', 'w', 'q']);
      vi.command('3');
      expect(show(c), 'a\nb\n|c');
      vi.command('frob');
      expect(vi.message, 'Not an editor command: frob');
    });

    test('/, ? and : ask for a line', () {
      final prompts = <ViPrompt>[];
      final vi = ViEngine(at('|a'), onPrompt: prompts.add);
      type(vi, '/?:');
      expect(prompts, [
        ViPrompt.searchForward,
        ViPrompt.searchBackward,
        ViPrompt.command,
      ]);
    });
  });

  test('normal mode never leaves the cursor after a line\'s end', () {
    expect(run('|abc', 'A<Esc>'), 'ab|c');
    expect(run('abc|', 'l'), 'ab|c');
  });

  test('works on an empty text', () {
    for (final keys in [
      'x',
      'dd',
      'p',
      'w',
      'b',
      'e',
      'G',
      'J',
      'ciw',
      'di(',
      '%',
      'vd',
    ]) {
      expect(run('|', keys), '|', reason: keys);
    }
  });
}
