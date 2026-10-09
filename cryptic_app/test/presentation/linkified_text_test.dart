import 'package:cryptic_app/presentation/widgets/linkified_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finds a plain URL', () {
    final links = findLinks('Visit https://example.com/path');

    expect(links.map((link) => link.url), ['https://example.com/path']);
  });

  test('trims trailing periods and commas', () {
    final links = findLinks(
      'First https://example.com/path. Then https://example.org/path,',
    );

    expect(
      links.map((link) => link.url),
      ['https://example.com/path', 'https://example.org/path'],
    );
  });

  test('trims surrounding parentheses but keeps balanced URL parentheses', () {
    final links = findLinks(
      'Wrapped (https://example.com/path), '
      'inside https://example.com/a_(b).',
    );

    expect(
      links.map((link) => link.url),
      ['https://example.com/path', 'https://example.com/a_(b)'],
    );
  });

  test('finds multiple URLs', () {
    final links = findLinks('https://one.example and http://two.example');

    expect(
      links.map((link) => link.url),
      ['https://one.example', 'http://two.example'],
    );
  });

  test('ignores unsupported or invalid URLs', () {
    expect(
      findLinks('ftp://example.com javascript:alert(1) http:// '),
      isEmpty,
    );
  });

  test('returns no links when text has no URL', () {
    expect(findLinks('Just ordinary chat text.'), isEmpty);
  });
}
