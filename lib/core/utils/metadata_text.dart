import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

class MetadataOverviewContent {
  const MetadataOverviewContent({required this.text, this.sources = const []});

  final String text;
  final List<Uri> sources;
}

String sanitizeMetadataOverviewText(String raw) =>
    parseMetadataOverview(raw).text;

MetadataOverviewContent parseMetadataOverview(String raw) {
  if (raw.isEmpty) {
    return const MetadataOverviewContent(text: '');
  }
  if (!raw.contains('<') && !raw.contains('&') && !_plainUrl.hasMatch(raw)) {
    return MetadataOverviewContent(text: _normalizeOverviewWhitespace(raw));
  }
  final reader = _OverviewReader();
  // An unfinished opening tag has no DOM node. Remove only that fragment and
  // a clearly separated source label, leaving preceding prose untouched.
  var input = raw.replaceAll(RegExp(r'<a\b[^>\n]*$', caseSensitive: false), '');
  if (input != raw) {
    input = _withoutSourceLabel(input);
  }
  for (final node in html.parseFragment(input).nodes) {
    reader.read(node);
  }
  return MetadataOverviewContent(
    text: _normalizeOverviewWhitespace(reader.chunks.join()),
    sources: List.unmodifiable(reader.sources),
  );
}

Uri? resolveMetadataSourceUri(String value) {
  if (RegExp(r'[\x00-\x20\x7f]').hasMatch(value.trim())) {
    return null;
  }
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

const _sourceLabels = [
  '原始视频',
  '视频来源',
  '原视频',
  '在线观看',
  '来源',
  '原文',
  '原文链接',
  '相关链接',
  '链接',
  '下载地址',
  'source',
];

final _sourceLabel = RegExp(
  r'(^|[\s，。！？!?；;,、（(【\[])'
  r'([^\s：:，。！？!?；;,、<>（）()【】\[\]]{1,16})[ \t]*[:：][ \t]*$',
);

String _withoutSourceLabel(String text) {
  final match = _sourceLabel.firstMatch(text);
  if (match == null) {
    return text;
  }
  final label = match.group(2)!.toLowerCase();
  // A known label glued to prose is not a reliable deletion boundary.
  if (!_sourceLabels.contains(label)) {
    if (_sourceLabels.any((known) => label.endsWith(known)) ||
        !RegExp(r'^[\u4e00-\u9fffA-Za-z]{1,4}(地址|网址)$').hasMatch(label)) {
      return text;
    }
  }
  return text.substring(0, match.start) + match.group(1)!;
}

final _plainUrl = RegExp(
  r'''https?://[^\s<>"'，。！？；、（）【】\[\]]+''',
  caseSensitive: false,
);
final _encodedMarkup = RegExp(
  r'(?:<|&lt;|&#60;|&#x3c;)/?(?:a|br|p|div|span|b|strong|em|i)\b',
  caseSensitive: false,
);

class _OverviewReader {
  final chunks = <String>[];
  final sources = <Uri>[];
  final _seen = <String>{};
  bool _afterSource = false;

  void read(dom.Node node, [int encodingDepth = 0]) {
    if (node is dom.Text) {
      final text = node.data;
      if (encodingDepth < 2 && _encodedMarkup.hasMatch(text)) {
        for (final child in html.parseFragment(text).nodes) {
          read(child, encodingDepth + 1);
        }
        return;
      }
      var offset = 0;
      for (final match in _plainUrl.allMatches(text)) {
        _append(text.substring(offset, match.start));
        final url = match.group(0)!;
        final withoutPunctuation = url.replaceFirst(RegExp(r'[.,;!?)]+$'), '');
        _source(withoutPunctuation);
        _append(url.substring(withoutPunctuation.length));
        offset = match.end;
      }
      _append(text.substring(offset));
      return;
    }
    if (node is! dom.Element) {
      return;
    }
    final tag = node.localName;
    if (const {'script', 'style', 'template', 'iframe', 'noscript'}
        .contains(tag)) {
      return;
    }
    if (tag == 'a' && node.attributes.containsKey('href')) {
      _source(node.attributes['href']!);
      return;
    }
    if (tag == 'br' || tag == 'hr') {
      _break('\n');
      return;
    }
    final block = const {
      'p',
      'div',
      'section',
      'article',
      'blockquote',
      'ul',
      'ol',
      'li',
      'h1',
      'h2',
      'h3',
      'h4',
      'pre',
    }.contains(tag);
    if (block) {
      _break('\n\n', paragraph: true);
    }
    for (final child in node.nodes) {
      read(child, encodingDepth);
    }
    if (block) {
      _break('\n\n', paragraph: true);
    }
  }

  void _source(String raw) {
    final uri = resolveMetadataSourceUri(raw);
    if (uri != null && _seen.add(uri.toString())) {
      sources.add(uri);
    }
    if (chunks.isNotEmpty) {
      chunks[chunks.length - 1] = _withoutSourceLabel(chunks.last);
    }
    _afterSource = true;
  }

  void _append(String text) {
    if (_afterSource) {
      text = text.trimLeft();
    }
    if (text.isEmpty) {
      return;
    }
    _afterSource = false;
    if (chunks.isNotEmpty && !chunks.last.endsWith('\n')) {
      chunks[chunks.length - 1] += text;
    } else {
      chunks.add(text);
    }
  }

  void _break(String text, {bool paragraph = false}) {
    if (paragraph || !_afterSource) {
      chunks.add(text);
    }
  }
}

String _normalizeOverviewWhitespace(String value) {
  return value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[ \t\f\v\u00a0]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
