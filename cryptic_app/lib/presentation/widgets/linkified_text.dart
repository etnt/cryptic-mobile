import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A validated HTTP(S) URL found in text.
class LinkMatch {
  /// Creates a URL match with its source-text boundaries.
  const LinkMatch({
    required this.start,
    required this.end,
    required this.url,
    required this.uri,
  });

  /// Start offset in the source text.
  final int start;

  /// Exclusive end offset in the source text.
  final int end;

  /// The URL exactly as it appears in the source text.
  final String url;

  /// The parsed URL.
  final Uri uri;
}

/// Finds valid HTTP(S) URLs in [text].
List<LinkMatch> findLinks(String text) {
  final matches = <LinkMatch>[];
  final expression = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

  for (final match in expression.allMatches(text)) {
    final matchedUrl = match.group(0);
    if (matchedUrl == null) continue;

    var end = match.end;
    var url = matchedUrl;

    while (url.isNotEmpty && _isTrailingPunctuation(url, url.length - 1)) {
      url = url.substring(0, url.length - 1);
      end--;
    }

    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme.toLowerCase() != 'http' &&
            uri.scheme.toLowerCase() != 'https') ||
        uri.host.isEmpty) {
      continue;
    }

    matches.add(
      LinkMatch(start: match.start, end: end, url: url, uri: uri),
    );
  }

  return matches;
}

bool _isTrailingPunctuation(String url, int index) {
  const punctuation = '.,;:!?)]}\'"';
  final character = url[index];
  if (!punctuation.contains(character)) return false;

  if (character == ')') {
    final openingParentheses = '('.allMatches(url.substring(0, index)).length;
    final closingParentheses = ')'.allMatches(url.substring(0, index)).length;
    // Keep this close parenthesis when it balances one inside the URL.
    return closingParentheses >= openingParentheses;
  }

  return true;
}

/// Displays text with validated HTTP(S) URLs that open in the external browser.
class LinkifiedText extends StatefulWidget {
  /// Creates rich text with tappable links.
  const LinkifiedText({
    required this.text,
    required this.style,
    required this.linkStyle,
    this.onOpen,
    super.key,
  });

  /// The text to display and scan for URLs.
  final String text;

  /// The style applied to plain text.
  final TextStyle style;

  /// The style applied to links.
  final TextStyle linkStyle;

  /// Optional URL opener. Defaults to opening the URL in the external browser.
  final Future<bool> Function(Uri uri)? onOpen;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  List<LinkMatch> _links = const [];
  List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _rebuildRecognizers();
  }

  @override
  void didUpdateWidget(covariant LinkifiedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _rebuildRecognizers();
  }

  void _rebuildRecognizers() {
    _disposeRecognizers();
    _links = findLinks(widget.text);
    _recognizers = _links
        .map(
          (link) =>
              TapGestureRecognizer()..onTap = () => unawaited(_open(link.uri)),
        )
        .toList();
  }

  Future<void> _open(Uri uri) async {
    try {
      await (widget.onOpen ?? _launchExternally)(uri);
    } catch (_) {
      // Link opening is best-effort; a failed external launch is a no-op.
    }
  }

  Future<bool> _launchExternally(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers = [];
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final children = <InlineSpan>[];
    var offset = 0;

    for (var index = 0; index < _links.length; index++) {
      final link = _links[index];
      if (link.start > offset) {
        children.add(
          TextSpan(text: widget.text.substring(offset, link.start)),
        );
      }
      children.add(
        TextSpan(
          text: link.url,
          style: widget.linkStyle,
          recognizer: _recognizers[index],
        ),
      );
      offset = link.end;
    }

    if (offset < widget.text.length) {
      children.add(TextSpan(text: widget.text.substring(offset)));
    }

    return Text.rich(
      TextSpan(style: widget.style, children: children),
      softWrap: true,
    );
  }
}
