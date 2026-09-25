enum MediaRatingSource {
  douban,
  imdb,
  tmdb,
  other,
}

bool hasUsableRatingForSource(
    Iterable<String> labels, MediaRatingSource source) {
  return labels.any((label) =>
      resolveMediaRatingSource(label) == source && _isUsableRatingLabel(label));
}

String formatRatingCountLabel(int count) {
  if (count <= 0) {
    return '';
  }
  if (count >= 100000000) {
    return '${_formatCompactUnit(count / 100000000)}亿';
  }
  if (count >= 10000) {
    return '${_formatCompactUnit(count / 10000)}万';
  }
  return '$count';
}

String buildRatingCountLabel(int count) {
  final value = formatRatingCountLabel(count);
  return value.isEmpty ? '' : '☆$value';
}

String _formatCompactUnit(double value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

String resolvePreferredPosterRatingLabel(
  Iterable<String> labels, {
  bool preferDoubanOnly = false,
}) {
  final normalized = labels
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (normalized.isEmpty) {
    return '';
  }

  if (preferDoubanOnly) {
    return _resolveFirstUsableRatingLabelBySource(
      normalized,
      MediaRatingSource.douban,
    );
  }

  for (final source in const [
    MediaRatingSource.douban,
    MediaRatingSource.imdb,
    MediaRatingSource.tmdb,
  ]) {
    final matched = _resolveFirstUsableRatingLabelBySource(normalized, source);
    if (matched.isNotEmpty) {
      return matched;
    }
  }

  for (final label in normalized) {
    if (_isUsableRatingLabel(label)) {
      return label;
    }
  }
  return '';
}

List<String> mergeDistinctRatingLabels(
  Iterable<String> primary,
  Iterable<String> secondary,
) {
  final orderedKeys = <String>[];
  final valuesByKey = <String, String>{};

  void collect(Iterable<String> values) {
    for (final raw in values) {
      final label = raw.trim();
      if (label.isEmpty) {
        continue;
      }
      final key = _labelMergeKey(label);
      final existing = valuesByKey[key];
      if (existing == null) {
        valuesByKey[key] = label;
        orderedKeys.add(key);
        continue;
      }
      if (!_isUsableRatingLabel(existing) && _isUsableRatingLabel(label)) {
        valuesByKey[key] = label;
      }
    }
  }

  collect(primary);
  collect(secondary);
  final labels = orderedKeys
      .map((key) => valuesByKey[key] ?? '')
      .where((label) => label.trim().isNotEmpty)
      .toList(growable: false);
  return _orderRatingLabels(labels);
}

List<String> _orderRatingLabels(Iterable<String> labels) {
  final indexed = labels
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty)
      .indexed
      .toList(growable: false);
  indexed.sort((left, right) {
    final sourceComparison = _ratingSourcePriority(
      resolveMediaRatingSource(left.$2),
    ).compareTo(_ratingSourcePriority(resolveMediaRatingSource(right.$2)));
    if (sourceComparison != 0) {
      return sourceComparison;
    }
    return left.$1.compareTo(right.$1);
  });
  return indexed.map((entry) => entry.$2).toList(growable: false);
}

MediaRatingSource resolveMediaRatingSource(String label) {
  final normalized = label.trim().toLowerCase();
  if (normalized.isEmpty) {
    return MediaRatingSource.other;
  }
  if (normalized.contains('豆瓣') || normalized.contains('douban')) {
    return MediaRatingSource.douban;
  }
  if (normalized.contains('imdb')) {
    return MediaRatingSource.imdb;
  }
  if (normalized.contains('tmdb')) {
    return MediaRatingSource.tmdb;
  }
  return MediaRatingSource.other;
}

String _resolveFirstUsableRatingLabelBySource(
  Iterable<String> labels,
  MediaRatingSource source,
) {
  for (final label in labels) {
    if (resolveMediaRatingSource(label) != source) {
      continue;
    }
    if (_isUsableRatingLabel(label)) {
      return label.trim();
    }
  }
  return '';
}

String _labelMergeKey(String value) {
  return switch (resolveMediaRatingSource(value)) {
    MediaRatingSource.douban => 'rating:douban',
    MediaRatingSource.imdb => 'rating:imdb',
    MediaRatingSource.tmdb => 'rating:tmdb',
    MediaRatingSource.other => value.trim().toLowerCase(),
  };
}

int _ratingSourcePriority(MediaRatingSource source) {
  return switch (source) {
    MediaRatingSource.douban => 0,
    MediaRatingSource.imdb => 1,
    MediaRatingSource.tmdb => 2,
    MediaRatingSource.other => 3,
  };
}

bool _isUsableRatingLabel(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final numericMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(trimmed);
  if (numericMatch == null) {
    return true;
  }
  return (double.tryParse(numericMatch.group(1) ?? '') ?? 0) > 0;
}
