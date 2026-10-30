import 'package:cryptic_app/presentation/widgets/linkified_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('findLinks', () {
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

    test('trims surrounding parentheses but keeps balanced URL parentheses',
        () {
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
  });

  group('long-press copy', () {
    String? clipboardText;

    setUp(() {
      clipboardText = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final arguments = call.arguments as Map<Object?, Object?>;
          clipboardText = arguments['text'] as String?;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Widget buildWidget({
      VoidCallback? onNonLinkLongPress,
      void Function(Uri uri)? onLongPressLink,
      Future<bool> Function(Uri uri)? onOpen,
    }) =>
        MaterialApp(
          home: Scaffold(
            body: LinkifiedText(
              text: 'see https://example.com/a?b=1. and plain words',
              style: const TextStyle(fontSize: 16),
              linkStyle: const TextStyle(color: Colors.blue),
              onNonLinkLongPress: onNonLinkLongPress,
              onLongPressLink: onLongPressLink,
              onOpen: onOpen,
            ),
          ),
        );

    /// Long-presses the first occurrence of [snippet] inside the rendered
    /// rich text, at the span's real screen position.
    Future<void> longPressOnText(WidgetTester tester, String snippet) async {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byType(RichText),
      );
      final start = paragraph.text.toPlainText().indexOf(snippet);
      expect(start, greaterThanOrEqualTo(0));
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + 1),
          )
          .single;
      await tester.longPressAt(
        paragraph.localToGlobal(
          Offset((box.left + box.right) / 2, (box.top + box.bottom) / 2),
        ),
      );
      await tester.pump();
    }

    testWidgets('long-pressing a link copies it to the clipboard',
        (tester) async {
      await tester.pumpWidget(buildWidget());
      await longPressOnText(tester, 'https://example.com/a?b=1');
      await tester.idle();

      expect(clipboardText, 'https://example.com/a?b=1');
      expect(find.text('Link copied'), findsOneWidget);
    });

    testWidgets('long-pressing a link reports the link callback',
        (tester) async {
      Uri? longPressed;
      await tester.pumpWidget(
        buildWidget(onLongPressLink: (uri) => longPressed = uri),
      );
      await longPressOnText(tester, 'https://example.com/a?b=1');

      expect(longPressed, Uri.parse('https://example.com/a?b=1'));
    });

    testWidgets('long-pressing a link does not forward to the bubble',
        (tester) async {
      var forwarded = 0;
      await tester.pumpWidget(
        buildWidget(onNonLinkLongPress: () => forwarded++),
      );
      await longPressOnText(tester, 'https://example.com/a?b=1');

      expect(forwarded, 0);
    });

    testWidgets(
        'long-pressing a link does not fire the tap recognizer and '
        'open the browser', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        buildWidget(
          onOpen: (uri) async {
            opened++;
            return true;
          },
        ),
      );
      await longPressOnText(tester, 'https://example.com/a?b=1');
      await tester.idle();

      expect(opened, 0);
    });

    testWidgets(
        'long-pressing plain text forwards to the bubble without '
        'copying', (tester) async {
      var forwarded = 0;
      await tester.pumpWidget(
        buildWidget(onNonLinkLongPress: () => forwarded++),
      );
      await longPressOnText(tester, 'and plain words');

      expect(forwarded, 1);
      expect(clipboardText, isNull);
    });
  });
}
