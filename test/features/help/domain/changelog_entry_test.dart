import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/help/domain/changelog_entry.dart';

void main() {
  group('ChangelogEntry.fromMap', () {
    test('parses a published feature entry', () {
      final e = ChangelogEntry.fromMap(const {
        'id': '11111111-1111-1111-1111-111111111111',
        'version': '2026.05',
        'title': 'New dashboard',
        'body': 'Cleaner, faster, fewer clicks.',
        'category': 'feature',
        'published_at': '2026-05-15T10:00:00Z',
        'created_at': '2026-05-14T09:00:00Z',
        'updated_at': '2026-05-15T10:00:00Z',
      });
      expect(e.title, 'New dashboard');
      expect(e.version, '2026.05');
      expect(e.category, ChangelogCategory.feature);
      expect(e.isPublished, isTrue);
      expect(e.isDraft, isFalse);
    });

    test('parses a draft entry', () {
      final e = ChangelogEntry.fromMap(const {
        'id': '1',
        'title': 'Coming soon',
        'body': 'TBD',
        'category': 'improvement',
        'published_at': null,
        'created_at': '2026-05-14T09:00:00Z',
        'updated_at': '2026-05-14T09:00:00Z',
      });
      expect(e.isDraft, isTrue);
      expect(e.isPublished, isFalse);
      expect(e.publishedAt, isNull);
      expect(e.version, isNull);
      expect(e.category, ChangelogCategory.improvement);
    });

    test('parses all categories from db strings', () {
      ChangelogCategory parse(String s) =>
          ChangelogEntry.fromMap({
            'id': '1',
            'title': 't',
            'body': 'b',
            'category': s,
            'created_at': '2026-05-14T09:00:00Z',
            'updated_at': '2026-05-14T09:00:00Z',
          }).category;

      expect(parse('feature'), ChangelogCategory.feature);
      expect(parse('improvement'), ChangelogCategory.improvement);
      expect(parse('fix'), ChangelogCategory.fix);
      expect(parse('security'), ChangelogCategory.security);
    });

    test('unknown category defaults to feature', () {
      final e = ChangelogEntry.fromMap(const {
        'id': '1',
        'title': 't',
        'body': 'b',
        'category': 'banana',
        'created_at': '2026-05-14T09:00:00Z',
        'updated_at': '2026-05-14T09:00:00Z',
      });
      expect(e.category, ChangelogCategory.feature);
    });
  });

  group('categoryDbValue round-trip', () {
    test('every category produces a db value that parses back', () {
      for (final c in ChangelogCategory.values) {
        final dummy = ChangelogEntry(
          id: '1',
          title: 't',
          body: 'b',
          category: c,
          createdAt: DateTime(2026, 5, 14),
          updatedAt: DateTime(2026, 5, 14),
        );
        final reparsed = ChangelogEntry.fromMap({
          'id': '1',
          'title': 't',
          'body': 'b',
          'category': dummy.categoryDbValue,
          'created_at': '2026-05-14T09:00:00Z',
          'updated_at': '2026-05-14T09:00:00Z',
        });
        expect(reparsed.category, c);
      }
    });
  });
}
