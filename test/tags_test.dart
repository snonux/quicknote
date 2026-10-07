import 'package:flutter_test/flutter_test.dart';
import 'package:turbonotes/services/tags.dart';

void main() {
  group('extractTags', () {
    test('finds plain and nested tags, lower-cased', () {
      expect(
        extractTags('Plan #Work/TurboNotes and #idea, also (#later).\n#todo'),
        {'work/turbonotes', 'idea', 'todo'},
      );
    });

    test('ignores headings, fragments, entities and numbers', () {
      expect(
        extractTags(
          '# Heading\n## Sub\nSee page#top or https://x.y/#frag, &#38;, '
          'issue #123 and [link](#anchor)',
        ),
        isEmpty,
      );
    });

    test('ignores code spans and fenced code', () {
      expect(
        extractTags('Real #tag and `#notatag`\n```\n#also-not\n```\n#after'),
        {'tag', 'after'},
      );
    });

    test('drops trailing slashes and dashes', () {
      expect(extractTags('#a/b/ #c-'), {'a/b', 'c'});
    });

    test('accepts non-ASCII letters', () {
      expect(extractTags('#café #über'), {'café', 'über'});
    });
  });

  test('tagMatches covers nested tags only', () {
    expect(tagMatches('work', 'work'), isTrue);
    expect(tagMatches('work/q', 'work'), isTrue);
    expect(tagMatches('workshop', 'work'), isFalse);
  });

  test('TagNode.build nests tags and counts notes once', () {
    final root = TagNode.build({
      'a.md': {'work/q', 'work'},
      'b.md': {'work/r'},
      'c.md': {'home'},
    });
    expect(root.children.map((n) => n.tag), ['home', 'work']);
    final work = root.children.last;
    expect(work.notes, {'a.md', 'b.md'});
    expect(work.children.map((n) => n.tag), ['work/q', 'work/r']);
    expect(work.children.first.notes, {'a.md'});
  });
}
