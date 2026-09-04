const Map<String, String> _metadataTextEntities = {
  'nbsp': ' ',
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  '#39': "'",
  '#x27': "'",
};

String sanitizeMetadataOverviewText(String raw) {
  if (raw.isEmpty) {
    return '';
  }

  var text = _decodeBasicHtmlEntities(raw);
  text = _stripLabeledLinks(text);
  text = _stripRemainingLinks(text);
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  text = text.replaceAllMapped(
    RegExp(r'<\s*br\s*/?>', caseSensitive: false),
    (_) => '\n',
  );
  text = text.replaceAllMapped(
    RegExp(r'<\s*/\s*p\s*>|<\s*p\s+[^>]*>', caseSensitive: false),
    (_) => '\n',
  );
  // Remove normal tags and common malformed fragments such as `<a br` that
  // sometimes arrive without a closing bracket.
  text = text.replaceAll(
    RegExp(r'<\s*/?\s*[A-Za-z][^>\n]*>?', caseSensitive: false),
    '',
  );
  text = _collapseMetadataWhitespace(text);
  return text;
}

String _stripLabeledLinks(String value) {
  return value.replaceAllMapped(
    RegExp(
      r'(^|[\s，。！？!?；;])'
      r'([^\s：:，。！？!?；;<>\n]*\s*[:：])'
      r'\s*<a\b[^>]*>[^<]*</a>(?:\s*<br\s*/?>)*',
      caseSensitive: false,
    ),
    (match) => match.group(1) ?? '',
  );
}

String _stripRemainingLinks(String value) {
  return value.replaceAllMapped(
    RegExp(
      r'<a\b[^>]*>[^<]*</a>(?:\s*<br\s*/?>)*',
      caseSensitive: false,
    ),
    (_) => '',
  );
}

String _decodeBasicHtmlEntities(String value) {
  return value.replaceAllMapped(
    RegExp(r'&(#?[A-Za-z0-9]+);'),
    (match) {
      final rawEntity = match.group(1) ?? '';
      final entity = rawEntity.toLowerCase();
      final known = _metadataTextEntities[entity];
      if (known != null) {
        return known;
      }
      if (entity.startsWith('#x') && entity.length > 2) {
        final codePoint = int.tryParse(entity.substring(2), radix: 16);
        if (codePoint != null && codePoint > 0 && codePoint <= 0x10ffff) {
          return String.fromCharCode(codePoint);
        }
      } else if (entity.startsWith('#') && entity.length > 1) {
        final codePoint = int.tryParse(entity.substring(1), radix: 10);
        if (codePoint != null && codePoint > 0 && codePoint <= 0x10ffff) {
          return String.fromCharCode(codePoint);
        }
      }
      return match.group(0) ?? '';
    },
  );
}

String _collapseMetadataWhitespace(String value) {
  return value
      .replaceAll(RegExp(r'[ \t\f\v]+'), ' ')
      .replaceAll(RegExp(r'[ \t\f\v]*\n[ \t\f\v]*'), '\n')
      .trim();
}
