import 'package:flutter_test/flutter_test.dart';
import 'package:turbonotes/services/fuzzy.dart';

void main() {
  const paths = [
    'archive/2023/todo-old.md',
    'groceries.md',
    'journal/2026-10-07.md',
    'projects/quicknote/ideas.md',
    'projects/quicklog/notes.md',
    'todo.md',
  ];

  List<String> find(String q) => [
    for (final m in fuzzyFilter(q, paths)) m.candidate,
  ];

  test('an empty query keeps every path in order', () {
    expect(find(''), paths);
    expect(find('   '), paths);
  });

  test('characters must appear in order, case-insensitively', () {
    expect(find('GRC'), ['groceries.md']);
    expect(find('zzz'), isEmpty);
    expect(find('crg'), isEmpty);
  });

  test('matches across folders and file name', () {
    expect(find('qnidea').first, 'projects/quicknote/ideas.md');
  });

  test('whitespace separates terms that must all match', () {
    expect(find('quick notes').first, 'projects/quicklog/notes.md');
    expect(find('quick zebra'), isEmpty);
  });

  test('the shorter, file-name match ranks first', () {
    expect(find('todo').first, 'todo.md');
  });

  test('positions point at the matched characters', () {
    final m = fuzzyMatch('ideas', 'projects/quicknote/ideas.md')!;
    expect(
      m.positions.map((i) => 'projects/quicknote/ideas.md'[i]).join(),
      'ideas',
    );
    // The file name occurrence wins over scattered letters in the folders.
    expect(m.positions.first, 'projects/quicknote/'.length);
  });

  test('limit caps the result', () {
    expect(fuzzyFilter('o', paths, limit: 2), hasLength(2));
  });
}
