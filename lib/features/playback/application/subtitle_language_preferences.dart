import 'dart:ui';

List<String> resolveEffectiveSubtitleSearchLanguages(
  Iterable<String> configuredLanguages, {
  Locale? systemLocale,
}) {
  final tags = <String>[];
  final seen = <String>{};
  for (final key in _buildSubtitlePreferenceKeys(
    configuredLanguages,
    systemLocale: systemLocale,
  )) {
    for (final tag in _subtitleSearchTagsForPreferenceKey(key)) {
      final normalized = _normalizeSubtitleLanguageTag(tag);
      if (normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      tags.add(normalized);
    }
  }
  return tags;
}

int scorePreferredSubtitleText(
  String text, {
  Iterable<String> configuredLanguages = const <String>[],
  Locale? systemLocale,
}) {
  final normalizedText = normalizeSubtitlePreferenceText(text);
  if (normalizedText.isEmpty) {
    return 0;
  }
  final normalizedTokens = _tokenizeSubtitlePreferenceText(text);

  var score = 0;
  final preferenceKeys = _buildSubtitlePreferenceKeys(
    configuredLanguages,
    systemLocale: systemLocale,
  );
  for (var index = 0; index < preferenceKeys.length; index++) {
    final weight = switch (index) {
      0 => 120,
      1 => 84,
      2 => 60,
      _ => 40,
    };
    if (_containsPreferredToken(
      normalizedText,
      normalizedTokens,
      _subtitleMatchTokensForPreferenceKey(preferenceKeys[index]),
    )) {
      score += weight;
    }
  }

  if (_containsPreferredToken(
    normalizedText,
    normalizedTokens,
    const ['双语', '雙語', '中英', 'bilingual'],
  )) {
    score += 12;
  }
  if (_containsPreferredToken(
    normalizedText,
    normalizedTokens,
    const ['commentary', 'sdh', 'forced', 'signs'],
  )) {
    score -= 18;
  }
  return score;
}

String normalizeSubtitlePreferenceText(String value) {
  return value.trim().toLowerCase().replaceAll(
        RegExp(r'[\s\-_.,:;!?/\\|()\[\]{}<>《》【】"“”·]+'),
        '',
      );
}

List<String> _buildSubtitlePreferenceKeys(
  Iterable<String> configuredLanguages, {
  Locale? systemLocale,
}) {
  final keys = <String>[];
  final seen = <String>{};

  void addKey(String raw) {
    final normalized = _canonicalSubtitlePreferenceKey(
      raw,
      systemLocale: systemLocale,
    );
    if (normalized.isEmpty || !seen.add(normalized)) {
      return;
    }
    keys.add(normalized);
  }

  final locale = _resolvePrimarySystemLocale(systemLocale);
  if (locale != null) {
    for (final key in _subtitlePreferenceKeysForLocale(locale)) {
      addKey(key);
    }
  }
  for (final language in configuredLanguages) {
    addKey(language);
  }
  return keys;
}

Locale? _resolvePrimarySystemLocale(Locale? overrideLocale) {
  if (overrideLocale != null && overrideLocale.languageCode.trim().isNotEmpty) {
    return overrideLocale;
  }
  for (final locale in PlatformDispatcher.instance.locales) {
    if (locale.languageCode.trim().isNotEmpty) {
      return locale;
    }
  }
  final fallback = PlatformDispatcher.instance.locale;
  if (fallback.languageCode.trim().isNotEmpty) {
    return fallback;
  }
  return null;
}

List<String> _subtitlePreferenceKeysForLocale(Locale locale) {
  final languageCode = locale.languageCode.trim().toLowerCase();
  if (languageCode.isEmpty) {
    return const <String>[];
  }
  if (languageCode == 'zh') {
    if (_isTraditionalChineseLocale(locale)) {
      return const <String>['zh-tw', 'zh'];
    }
    return const <String>['zh-cn', 'zh'];
  }

  final countryCode = locale.countryCode?.trim().toLowerCase() ?? '';
  if (countryCode.isNotEmpty) {
    return <String>['$languageCode-$countryCode', languageCode];
  }
  return <String>[languageCode];
}

bool _isTraditionalChineseLocale(Locale locale) {
  final scriptCode = locale.scriptCode?.trim().toLowerCase() ?? '';
  if (scriptCode == 'hant') {
    return true;
  }
  if (scriptCode == 'hans') {
    return false;
  }
  final countryCode = locale.countryCode?.trim().toLowerCase() ?? '';
  return countryCode == 'tw' || countryCode == 'hk' || countryCode == 'mo';
}

String _canonicalSubtitlePreferenceKey(
  String raw, {
  Locale? systemLocale,
}) {
  final normalized = _normalizeSubtitleLanguageTag(raw);
  if (normalized.isEmpty) {
    return '';
  }

  if (_isSimplifiedChinesePreference(normalized)) {
    return 'zh-cn';
  }
  if (_isTraditionalChinesePreference(normalized)) {
    return 'zh-tw';
  }
  if (_isGenericChinesePreference(normalized)) {
    final locale = _resolvePrimarySystemLocale(systemLocale);
    if (locale != null && locale.languageCode.trim().toLowerCase() == 'zh') {
      return _isTraditionalChineseLocale(locale) ? 'zh-tw' : 'zh-cn';
    }
    return 'zh';
  }

  return switch (normalized) {
    'eng' || 'english' || '英语' || '英文' => 'en',
    'jpn' || 'japanese' || '日语' || '日文' || '日本語' => 'ja',
    'kor' || 'korean' || '韩语' || '韓語' || '韩文' || '韓文' => 'ko',
    'fre' || 'fra' || 'french' || '法语' || '法文' => 'fr',
    'ger' || 'deu' || 'german' || '德语' || '德文' => 'de',
    'spa' || 'spanish' || '西班牙语' => 'es',
    'por' || 'portuguese' || '葡萄牙语' => 'pt',
    'rus' || 'russian' || '俄语' || '俄文' => 'ru',
    _ => normalized,
  };
}

bool _isSimplifiedChinesePreference(String normalized) {
  return normalized == 'zh-cn' ||
      normalized == 'zh-sg' ||
      normalized == 'zh-hans' ||
      normalized == 'chs' ||
      normalized == 'chn' ||
      normalized == 'cn' ||
      normalized == 'sc' ||
      normalized == 'gb' ||
      normalized == '简中' ||
      normalized == '简体' ||
      normalized == '简体中文';
}

bool _isTraditionalChinesePreference(String normalized) {
  return normalized == 'zh-tw' ||
      normalized == 'zh-hk' ||
      normalized == 'zh-mo' ||
      normalized == 'zh-hant' ||
      normalized == 'cht' ||
      normalized == 'tc' ||
      normalized == 'big5' ||
      normalized == '繁中' ||
      normalized == '繁体' ||
      normalized == '繁體' ||
      normalized == '繁体中文' ||
      normalized == '繁體中文';
}

bool _isGenericChinesePreference(String normalized) {
  return normalized == 'zh' ||
      normalized == 'ch' ||
      normalized == 'chi' ||
      normalized == 'zho' ||
      normalized == 'chn' ||
      normalized == 'chinese' ||
      normalized == '中文' ||
      normalized == '中文字幕';
}

List<String> _subtitleSearchTagsForPreferenceKey(String key) {
  return switch (key) {
    'zh-cn' => const <String>['zh-cn', 'zh-hans', 'zh'],
    'zh-tw' => const <String>['zh-tw', 'zh-hant', 'zh'],
    'zh' => const <String>['zh'],
    'pt-br' => const <String>['pt-br', 'pt'],
    _ =>
      key.contains('-') ? <String>[key, key.split('-').first] : <String>[key],
  };
}

List<String> _subtitleMatchTokensForPreferenceKey(String key) {
  return switch (key) {
    'zh-cn' => const <String>[
        'zh-cn',
        'zh-hans',
        'chs',
        'chn',
        'cn',
        'sc',
        'gb',
        '简中',
        '简体',
        '简体中文',
        '中文字幕',
        '中文',
        'ch',
        'chinese',
        '中英',
        '双语',
        '雙語',
      ],
    'zh-tw' => const <String>[
        'zh-tw',
        'zh-hant',
        'zh-hk',
        'zh-mo',
        'cht',
        'tc',
        'big5',
        '繁中',
        '繁体',
        '繁體',
        '繁体中文',
        '繁體中文',
        '中文字幕',
        '中文',
        'ch',
        'chinese',
        '中英',
        '双语',
        '雙語',
      ],
    'zh' => const <String>[
        'ch',
        'chi',
        'zho',
        'chn',
        'cn',
        '中文字幕',
        '中文',
        'chinese',
        '中英',
        '双语',
        '雙語',
      ],
    'en' => const <String>['eng', 'english', '英语', '英文'],
    'ja' => const <String>['jpn', 'japanese', '日本語', '日语', '日文'],
    'ko' => const <String>['kor', 'korean', '韩语', '韓語', '韩文', '韓文'],
    'fr' => const <String>['fre', 'fra', 'french', '法语', '法文'],
    'de' => const <String>['ger', 'deu', 'german', '德语', '德文'],
    'es' => const <String>['spa', 'spanish', '西班牙语'],
    'pt-br' => const <String>[
        'pt-br',
        'ptbr',
        'brazilianportuguese',
        'portuguesebrazil',
        '巴葡',
        '巴西葡语',
      ],
    'pt' => const <String>['por', 'portuguese', '葡萄牙语'],
    'ru' => const <String>['rus', 'russian', '俄语', '俄文'],
    _ =>
      key.contains('-') ? <String>[key, key.split('-').first] : <String>[key],
  };
}

Set<String> _tokenizeSubtitlePreferenceText(String value) {
  return value
      .trim()
      .toLowerCase()
      .split(RegExp(r'[\s\-_.,:;!?/\\|()\[\]{}<>《》【】"“”·]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet();
}

bool _containsPreferredToken(
  String normalizedText,
  Set<String> normalizedTokens,
  Iterable<String> tokens,
) {
  for (final token in tokens) {
    final normalizedToken = normalizeSubtitlePreferenceText(token);
    if (normalizedToken.isEmpty) {
      continue;
    }
    if (normalizedToken.length <= 2) {
      if (normalizedTokens.contains(normalizedToken)) {
        return true;
      }
      continue;
    }
    if (normalizedText.contains(normalizedToken)) {
      return true;
    }
  }
  return false;
}

String _normalizeSubtitleLanguageTag(String value) {
  return value.trim().toLowerCase().replaceAll('_', '-');
}
