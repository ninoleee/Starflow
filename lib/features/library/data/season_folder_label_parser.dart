int? parseSeasonNumberFromFolderLabel(String value) {
  final normalized = _normalizeFullWidthDigits(value).trim();
  if (normalized.isEmpty) {
    return null;
  }
  if (_looksLikeSpecialSeasonLabel(normalized)) {
    return 0;
  }

  for (final pattern in const [
    r'(?:^|[ ._\-])s(\d{1,2})(?:$|[ ._\-])',
    r'season[ ._\-]?(\d{1,2})',
    r'series[ ._\-]?(\d{1,2})',
    r'第(\d{1,2})季',
  ]) {
    final match = RegExp(pattern, caseSensitive: false).firstMatch(normalized);
    final parsed = int.tryParse(match?.group(1) ?? '');
    if (parsed != null && parsed >= 0) {
      return parsed;
    }
  }

  final chineseSeasonMatch = RegExp(
    r'第([零〇一二三四五六七八九十百千两\d]{1,6})季',
  ).firstMatch(normalized);
  final chineseSeasonNumber = _parseFlexibleSeasonNumber(
    chineseSeasonMatch?.group(1),
  );
  if (chineseSeasonNumber != null) {
    return chineseSeasonNumber;
  }

  final anchoredPartMatch = RegExp(
    r'^\s*第([零〇一二三四五六七八九十百千两\d]{1,6})(?:部|篇|章)\s*$',
  ).firstMatch(normalized);
  final anchoredPartNumber = _parseFlexibleSeasonNumber(
    anchoredPartMatch?.group(1),
  );
  if (anchoredPartNumber != null) {
    return anchoredPartNumber;
  }

  return null;
}

int? parseLeadingNumericSeasonNumber(String value) {
  final normalized = _normalizeFullWidthDigits(value);
  final match = RegExp(r'^\s*(\d{1,2})(?:[ ._\-]|$)').firstMatch(normalized);
  final seasonNumber = int.tryParse(match?.group(1) ?? '');
  if (seasonNumber == null || seasonNumber <= 0) {
    return null;
  }
  return seasonNumber;
}

bool looksLikeSeasonFolderLabel(String value) {
  return parseSeasonNumberFromFolderLabel(value) != null ||
      looksLikeNumericTopicSeason(value);
}

bool looksLikeStrictSeasonFolderLabel(String value) {
  final normalized = _normalizeFullWidthDigits(value).trim();
  if (normalized.isEmpty) {
    return false;
  }
  if (_looksLikeSpecialSeasonLabel(normalized)) {
    return true;
  }
  if (looksLikeNumericTopicSeason(normalized)) {
    return true;
  }

  if (RegExp(
    r'^\s*(?:s\d{1,2}|season[ ._\-]?\d{1,2}|series[ ._\-]?\d{1,2})\s*$',
    caseSensitive: false,
  ).hasMatch(normalized)) {
    return true;
  }

  final chineseSeasonMatch = RegExp(
    r'^\s*第([零〇一二三四五六七八九十百千两\d]{1,6})季\s*$',
  ).firstMatch(normalized);
  if (_parseFlexibleSeasonNumber(chineseSeasonMatch?.group(1)) != null) {
    return true;
  }

  final anchoredPartMatch = RegExp(
    r'^\s*第([零〇一二三四五六七八九十百千两\d]{1,6})(?:部|篇|章)\s*$',
  ).firstMatch(normalized);
  return _parseFlexibleSeasonNumber(anchoredPartMatch?.group(1)) != null;
}

bool looksLikeNumericTopicSeason(String value) {
  return RegExp(r'^\s*\d{1,2}(?:[ ._\-]|$)').hasMatch(
    _normalizeFullWidthDigits(value),
  );
}

bool _looksLikeSpecialSeasonLabel(String value) {
  final asciiCompact = _normalizeFullWidthDigits(value)
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s._-]+'), '');
  if (RegExp(r'^(specials?|extras?|sp|ova|oad)\d*$').hasMatch(asciiCompact)) {
    return true;
  }

  final chineseCompact = _normalizeFullWidthDigits(value)
      .trim()
      .replaceAll(RegExp(r'[\s._-]+'), '');
  return RegExp(r'^(特别篇|特别篇合集|番外|花絮|幕后|加更|特典)\d*$').hasMatch(chineseCompact);
}

int? _parseFlexibleSeasonNumber(String? value) {
  final normalized = _normalizeFullWidthDigits(value ?? '').trim();
  if (normalized.isEmpty) {
    return null;
  }
  if (RegExp(r'^\d+$').hasMatch(normalized)) {
    return int.tryParse(normalized);
  }
  return _parseChineseNumber(normalized);
}

int? _parseChineseNumber(String value) {
  const digitMap = <String, int>{
    '零': 0,
    '〇': 0,
    '一': 1,
    '二': 2,
    '两': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  const unitMap = <String, int>{
    '十': 10,
    '百': 100,
    '千': 1000,
  };

  if (value.isEmpty) {
    return null;
  }

  final containsUnit = value.split('').any(unitMap.containsKey);
  if (!containsUnit) {
    final buffer = StringBuffer();
    for (final char in value.split('')) {
      final digit = digitMap[char];
      if (digit == null) {
        return null;
      }
      buffer.write(digit);
    }
    return int.tryParse(buffer.toString());
  }

  var total = 0;
  var currentDigit = 0;
  for (final char in value.split('')) {
    final digit = digitMap[char];
    if (digit != null) {
      currentDigit = digit;
      continue;
    }

    final unit = unitMap[char];
    if (unit == null) {
      return null;
    }
    total += (currentDigit == 0 ? 1 : currentDigit) * unit;
    currentDigit = 0;
  }
  return total + currentDigit;
}

String _normalizeFullWidthDigits(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    if (rune >= 0xFF10 && rune <= 0xFF19) {
      buffer.writeCharCode(rune - 0xFF10 + 0x30);
      continue;
    }
    buffer.writeCharCode(rune);
  }
  return buffer.toString();
}
