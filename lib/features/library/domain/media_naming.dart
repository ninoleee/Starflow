String stripEmbeddedExternalIdTags(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return trimmed.replaceAll(
    RegExp(
      r'\{\s*(?:tmdb(?:id)?|tmbid|tvdb(?:id)?|imdb(?:id)?|douban(?:id)?)\s*[-:=]?\s*[\w.-]+\s*\}',
      caseSensitive: false,
    ),
    ' ',
  );
}

const List<String> kDefaultVarietySpecialEpisodeKeywords = <String>[
  '先导片',
  '先导篇',
  '先导',
  '特别篇',
  '特辑',
  '番外',
  '彩蛋',
  '加更',
  '加更版',
  '精编版',
  '超前',
  '超前营业',
  '纯享',
  '纯享版',
  '舞台纯享',
  '舞台纯享版',
  '直拍',
  '直拍版',
  '连麦',
  '连麦大会',
  'reaction',
  '小考',
  '训练室',
  '训练室全纪录',
  '练习室',
  '见面会',
  '未播',
  '未播片段',
  '未公开',
  '未公开片段',
  '幕后',
  '幕后花絮',
  '制作特辑',
  '直播回顾',
  '预告',
  '预告片',
  '采访',
  '访谈',
  '删减片段',
  'trailers',
  'trailer',
  'samples',
  'sample',
  'clips',
  'clip',
  'interviews',
  'interview',
  'featurettes',
  'featurette',
  'behind the scenes',
  'behindthescenes',
  'deleted scenes',
  'deleted scene',
  'deletedscenes',
  'deletedscene',
  'making of',
  'makingof',
  'bonus material',
  'bonus',
  'unaired',
];

class MediaNaming {
  const MediaNaming._();

  static const List<String> subtitleDescriptorKeywords = <String>[
    '中字',
    '中文字幕',
    '中英字幕',
    '双语',
    '双字幕',
    '简繁',
    '内封',
    '外挂',
    '内嵌字幕',
    '内置字幕',
    '软字幕',
    '硬字幕',
    '特效中字',
    '特效字幕',
  ];

  static const List<String> subtitlePackagingDescriptorKeywords = <String>[
    '字幕版',
    '双语字幕',
    '简繁字幕',
    '内封中字',
    '外挂字幕',
  ];

  static const List<String> audioLanguageDescriptorKeywords = <String>[
    '国语版',
    '粤语版',
    '国粤版',
    '国粤双语',
    '国语',
    '粤语',
    '原声',
    '双音轨',
    '双语音轨',
    'dual audio',
    'dualaudio',
    'dubbed',
  ];

  static const List<String> videoPresentationDescriptorKeywords = <String>[
    '高码率',
    '原画',
    '杜比视界',
    '杜比全景声',
    '蓝光原盘',
    '原盘',
  ];

  static const List<String> editionDescriptorKeywords = <String>[
    '分段版',
    '会员版',
    '纯享版',
    '导演剪辑版',
    '导演版',
    '加长版',
    '未删减版',
    '完整版',
    '删减版',
    '花絮',
    '幕后',
    '加更',
    '彩蛋',
    '番外',
    '特别篇',
    '剧场版',
    'director\'s cut',
    'directors cut',
    'special edition',
    'theatrical cut',
    'unrated',
    'uncut',
  ];

  static const List<String> collectionEditionDescriptorKeywords = <String>[
    '重剪版',
    '重制版',
    '珍藏版',
    '纪念版',
    '特典',
    '收藏版',
    '典藏版',
    '终极版',
    '周年版',
    'collector edition',
    'criterion edition',
    'deluxe edition',
    'limited edition',
    'ultimate edition',
    'anniversary edition',
  ];

  static const List<String> cleanTitleOnlyDescriptorKeywords = <String>[
    '国粤',
  ];

  static const List<String> sharedDescriptorKeywords = <String>[
    ...subtitleDescriptorKeywords,
    ...videoPresentationDescriptorKeywords,
    ...editionDescriptorKeywords,
  ];

  static const List<String> wrapperOnlyDescriptorKeywords = <String>[
    ...subtitlePackagingDescriptorKeywords,
    ...audioLanguageDescriptorKeywords,
    ...collectionEditionDescriptorKeywords,
  ];

  static const List<String> displayTokenPatterns = <String>[
    r'2160p',
    r'1440p',
    r'1080p',
    r'1080i',
    r'900p',
    r'720p',
    r'576p',
    r'480p',
    r'360p',
    r'4k',
    r'8k',
    r'uhd',
    r'hdr10\+?',
    r'hdr',
    r'sdr',
    r'hqsdr',
    r'\d{2,3}fps',
    r'3d',
    r'hsbs',
    r'fsbs',
    r'htab',
    r'ftab',
    r'mvc',
    r'dovi',
    r'dv',
    r'dolby[ ._\-]?vision',
  ];

  static const List<String> sourceTokenPatterns = <String>[
    r'web[ ._\-]?dl',
    r'web[ ._\-]?rip',
    r'hdtv',
    r'hdrip',
    r'blu[ ._\-]?ray',
    r'remux',
    r'bdrip',
    r'brrip',
    r'dvd',
    r'dvdrip',
    r'dvdscr',
    r'dvb',
    r'vod',
    r'vhs',
    r'cam',
    r'hdcam',
    r'hdts',
    r'telesync',
    r'telecine',
    r'ppv',
    r'umd',
    r'workprint',
  ];

  static const List<String> codecTokenPatterns = <String>[
    r'x264',
    r'x265',
    r'xvid',
    r'divx',
    r'h264',
    r'h265',
    r'hevc',
    r'av1',
    r'avc',
    r'mpeg2',
    r'hi10p',
    r'hi422p',
    r'hi444pp',
    r'aac',
    r'ac3',
    r'eac3',
    r'dd(?: ?(?:2[ .]?0|5[ .]?1|7[ .]?1))?',
    r'ddp(?: ?(?:2[ .]?0|5[ .]?1|7[ .]?1))?',
    r'dts(?:[ ._\-]?hd)?',
    r'truehd',
    r'flac',
    r'mp3',
    r'opus',
    r'pcm',
    r'lpcm',
    r'atmos',
    r'10bit',
    r'8bit',
  ];

  static const List<String> releaseTagTokenPatterns = <String>[
    r'proper',
    r'repack',
    r'complete',
    r'multi',
    r'internal',
    r'extended',
    r'limited',
    r'dubbed',
    r'subbed',
    r'subs?',
    r'dual[ ._\-]?audio',
  ];

  static const List<String> platformTokenPatterns = <String>[
    r'nf',
    r'amzn',
    r'dsnp',
    r'max',
    r'hmax',
  ];

  static const List<String> sharedTechnicalTokenPatterns = <String>[
    ...displayTokenPatterns,
    ...sourceTokenPatterns,
    ...codecTokenPatterns,
    ...releaseTagTokenPatterns,
    ...platformTokenPatterns,
  ];

  static const List<String> titleNoiseDescriptorKeywords = <String>[
    ...sharedDescriptorKeywords,
    ...wrapperOnlyDescriptorKeywords,
    ...cleanTitleOnlyDescriptorKeywords,
  ];

  static final RegExp _commonTitleNoiseTokenPattern = RegExp(
    '\\b(?:${_joinPatterns(sharedTechnicalTokenPatterns)})\\b',
    caseSensitive: false,
  );

  static final RegExp _commonTitleNoiseDescriptorPattern = RegExp(
    _joinPatterns(escapePatternKeywords(titleNoiseDescriptorKeywords)),
    caseSensitive: false,
  );

  static final RegExp _lookupEpisodeTokenPattern = RegExp(
    r'\bS\d{1,2}E\d{1,2}\b',
    caseSensitive: false,
  );

  static final RegExp _wrapperDescriptorSeparatorPattern = RegExp(
    r'[【】\[\]\(\)（）{}<>《》"“”‘’·_.\-\s+&/\\|,:;]+',
  );

  static final Map<String, RegExp> _asciiKeywordPatternCache =
      <String, RegExp>{};
  static final Map<String, RegExp> _asciiCompactKeywordPatternCache =
      <String, RegExp>{};

  static List<String> normalizeKeywords(Iterable<String> values) {
    return values
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> escapePatternKeywords(Iterable<String> values) {
    return values.map(RegExp.escape).toList(growable: false);
  }

  static String buildAlternationPattern(Iterable<String> values) {
    return _joinPatterns(values);
  }

  static String compactKeywordLabel(String input) {
    return stripEmbeddedExternalIdTags(input).trim().toLowerCase().replaceAll(
          _wrapperDescriptorSeparatorPattern,
          '',
        );
  }

  static Set<String> keywordMatchForms(String raw) {
    final value = stripEmbeddedExternalIdTags(raw).trim();
    if (value.isEmpty) {
      return const <String>{};
    }
    final lowered = value.toLowerCase();
    final strippedExtension = lowered.replaceAll(
      RegExp(r'\.[a-z0-9]{1,6}$', caseSensitive: false),
      '',
    );
    return <String>{
      lowered,
      strippedExtension.trim(),
      compactKeywordLabel(lowered),
      compactKeywordLabel(strippedExtension),
    }..removeWhere((item) => item.isEmpty);
  }

  static bool matchesAnyKeyword(
    Iterable<String> rawValues, {
    required Iterable<String> keywords,
  }) {
    final haystacks = <String>{};
    for (final rawValue in rawValues) {
      haystacks.addAll(keywordMatchForms(rawValue));
    }
    if (haystacks.isEmpty) {
      return false;
    }
    for (final keyword in keywords) {
      if (_matchesKeywordAcrossForms(haystacks, keyword)) {
        return true;
      }
    }
    return false;
  }

  static String? bestMatchedKeyword(
    Iterable<String> rawValues, {
    required Iterable<String> keywords,
  }) {
    final haystacks = <String>{};
    for (final rawValue in rawValues) {
      haystacks.addAll(keywordMatchForms(rawValue));
    }
    if (haystacks.isEmpty) {
      return null;
    }

    String? bestMatch;
    var bestLength = -1;
    for (final keyword in keywords) {
      if (!_matchesKeywordAcrossForms(haystacks, keyword)) {
        continue;
      }
      final normalizedLength = compactKeywordLabel(keyword).length;
      if (normalizedLength > bestLength) {
        bestMatch = keyword;
        bestLength = normalizedLength;
      }
    }
    return bestMatch;
  }

  static String stripCommonTitleNoiseTokens(String value) {
    var cleaned = value.replaceAll(_commonTitleNoiseTokenPattern, ' ');
    cleaned = cleaned.replaceAll(_commonTitleNoiseDescriptorPattern, ' ');
    return cleaned;
  }

  static String cleanLookupQuery(String value) {
    return stripCommonTitleNoiseTokens(
      value
          .replaceAll(RegExp(r'[._]+'), ' ')
          .replaceAll(RegExp(r'\[[^\]]*\]|\([^\)]*\)'), ' '),
    )
        .replaceAll(_lookupEpisodeTokenPattern, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String normalizeLookupTitle(String value) {
    return cleanLookupQuery(value)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '');
  }

  static bool _matchesKeywordAcrossForms(
    Set<String> haystacks,
    String rawKeyword,
  ) {
    final loweredKeyword = rawKeyword.trim().toLowerCase();
    if (loweredKeyword.isEmpty) {
      return false;
    }
    final compactKeyword = compactKeywordLabel(loweredKeyword);
    if (compactKeyword.isEmpty) {
      return false;
    }
    if (_looksLikeAsciiKeyword(loweredKeyword)) {
      final directPattern = _asciiKeywordPatternCache.putIfAbsent(
        loweredKeyword,
        () => _buildAsciiKeywordPattern(loweredKeyword),
      );
      if (haystacks.any(directPattern.hasMatch)) {
        return true;
      }
      final compactPattern = _asciiCompactKeywordPatternCache.putIfAbsent(
        compactKeyword,
        () => RegExp(
          '(^|[^a-z0-9])${RegExp.escape(compactKeyword)}(?=[^a-z0-9]|\\\$)',
          caseSensitive: false,
        ),
      );
      return haystacks.any(compactPattern.hasMatch);
    }
    return haystacks.any(
      (haystack) =>
          haystack.contains(loweredKeyword) || haystack.contains(compactKeyword),
    );
  }

  static bool _looksLikeAsciiKeyword(String keyword) {
    return RegExp(r"^[a-z0-9][a-z0-9\s._\-/&+']*$").hasMatch(keyword);
  }

  static RegExp _buildAsciiKeywordPattern(String keyword) {
    final normalized = keyword.trim().toLowerCase();
    final parts = normalized
        .split(RegExp(r'[\s._\-/&+]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map(RegExp.escape)
        .toList(growable: false);
    final pattern = parts.isEmpty
        ? RegExp.escape(normalized)
        : parts.join(r'[\s._\-/&+]+');
    return RegExp(
      '(^|[^a-z0-9])$pattern(?=[^a-z0-9]|\\\$)',
      caseSensitive: false,
    );
  }

  static String _joinPatterns(Iterable<String> values) {
    return values.join('|');
  }
}
