import 'package:flutter/foundation.dart';

const bool _webDavTraceEnabled = false;
const bool _webDavTraceSummaryOnly = true;
const List<String> _webDavFocusedDetailKeywords = <String>[
  '请求救援',
  'send help',
  '%e8%af%b7%e6%b1%82%e6%95%91%e6%8f%b4',
];

const Set<String> _webDavSummaryStages = <String>{
  'indexer.refresh.start',
  'indexer.refresh.cancelAll',
  'indexer.refresh.done',
  'indexer.scanSource.scoped.start',
  'indexer.scanSource.scoped.done',
  'indexer.scanSource.root.start',
  'indexer.scanSource.root.done',
  'indexer.refresh.background.error',
  'indexer.refresh.autoRebuildOnEmpty',
};

void webDavTrace(
  String stage, {
  Map<String, Object?> fields = const <String, Object?>{},
}) {
  if (!_webDavTraceEnabled) {
    return;
  }
  final timestamp = DateTime.now().toIso8601String();
  final normalizedStage = stage.trim().isEmpty ? 'unknown' : stage.trim();
  if (_webDavTraceSummaryOnly &&
      !_webDavSummaryStages.contains(normalizedStage) &&
      !_matchesFocusedWebDavTrace(fields)) {
    return;
  }
  final normalizedFields = <String, String>{};
  for (final entry in fields.entries) {
    final key = entry.key.trim();
    if (key.isEmpty) {
      continue;
    }
    normalizedFields[key] = _formatTraceValue(entry.value);
  }

  final buffer = StringBuffer('[WebDAV][$timestamp] $normalizedStage');
  if (normalizedFields.isNotEmpty) {
    final sortedKeys = normalizedFields.keys.toList(growable: false)..sort();
    for (final key in sortedKeys) {
      buffer.write(' | $key=${normalizedFields[key]}');
    }
  }
  debugPrint(buffer.toString());
}

bool _matchesFocusedWebDavTrace(Map<String, Object?> fields) {
  for (final value in fields.values) {
    final normalizedValue = _formatTraceValue(value).toLowerCase();
    if (normalizedValue.isEmpty) {
      continue;
    }
    for (final keyword in _webDavFocusedDetailKeywords) {
      if (normalizedValue.contains(keyword)) {
        return true;
      }
    }
  }
  return false;
}

String _formatTraceValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is DateTime) {
    return value.toIso8601String();
  }
  if (value is Iterable) {
    final items = value
        .map((item) => _formatTraceValue(item))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return '[${items.join(', ')}]';
  }
  if (value is Map) {
    final entries = value.entries
        .map(
          (entry) => '${entry.key}:${_formatTraceValue(entry.value)}',
        )
        .toList(growable: false);
    return '{${entries.join(', ')}}';
  }
  return value.toString().replaceAll('\n', r'\n');
}
