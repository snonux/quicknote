import 'package:flutter_test/flutter_test.dart';
import 'package:quicknote/services/note_index.dart';
import 'package:quicknote/services/text_search.dart';

void main() {
  final index = NoteIndex({
    'journal/monday.md':
        '# Monday\n\nTeam meeting about the release.\n#work/meetings\n',
    'projects/quicknote.md':
        '# Quicknote\n\nFuzzy search across notes. #work/quicknote\n',
    'recipes/pancakes.md': '# Pancakes\n\n200 g flour, 2 eggs. #cooking\n',
    'todo.md': 'Call the plumber\n',
  });

  List<String> paths(String q) => [
    for (final h in searchNotes(q, index)) h.path,
  ];

  test('finds text case-insensitively', () {
    expect(paths('FLOUR'), ['recipes/pancakes.md']);
  });

  test('forgives typos', () {
    expect(paths('metting'), ['journal/monday.md']);
    expect(paths('plumbre'), ['todo.md']);
    expect(paths('panckaes'), ['recipes/pancakes.md']);
  });

  test('forgives a typo at the start of a longer word', () {
    expect(paths('quikc'), contains('projects/quicknote.md'));
  });

  test('short terms must match exactly', () {
    expect(paths('egs'), isEmpty);
  });

  test('every term must match', () {
    expect(paths('team release'), ['journal/monday.md']);
    expect(paths('team flour'), isEmpty);
  });

  test('matches note names too', () {
    expect(paths('todo'), ['todo.md']);
  });

  test('#tag terms filter by tag, nested tags included', () {
    expect(paths('#work'), ['journal/monday.md', 'projects/quicknote.md']);
    expect(paths('#work/meetings'), ['journal/monday.md']);
    expect(paths('#work fuzzy'), ['projects/quicknote.md']);
  });

  test('snippets point at the match', () {
    final hit = searchNotes('release', index).single;
    final s = hit.snippets.single;
    expect(s.line, 'Team meeting about the release.');
    expect(s.line.substring(s.ranges.single.$1, s.ranges.single.$2), 'release');
    final text = index['journal/monday.md']!.text;
    expect(text.substring(s.firstMatch.start, s.firstMatch.end), 'release');
  });

  test('exact matches rank above typo matches', () {
    final index = NoteIndex({
      'a.md': 'the meting notes',
      'b.md': 'the meeting notes',
    });
    expect(
      [for (final h in searchNotes('meeting', index)) h.path],
      ['b.md', 'a.md'],
    );
  });

  test('typoDistance counts swaps as one edit', () {
    expect(typoDistance('form', 'from', 2), 1);
    expect(typoDistance('kitten', 'sitting', 3), 3);
    expect(typoDistance('abc', 'xyzabc', 1), 2);
  });

  test('the index follows edits, renames and deletes', () {
    final index = NoteIndex({'a.md': 'alpha #one'});
    index.put('a.md', 'beta #two');
    expect(index.tagsOf('a.md'), {'two'});
    index.rename('a.md', 'b.md');
    expect([for (final h in searchNotes('beta', index)) h.path], ['b.md']);
    index.remove('b.md');
    expect(searchNotes('beta', index), isEmpty);
    expect(index.tagTree.children, isEmpty);
  });

  test('foldCase keeps offsets aligned', () {
    expect(foldCase('İx').length, 2);
  });
}
