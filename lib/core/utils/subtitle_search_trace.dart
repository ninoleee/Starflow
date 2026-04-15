import 'package:flutter/foundation.dart';

bool _subtitleSearchTraceEnabled = false;

bool get subtitleSearchTraceEnabled => _subtitleSearchTraceEnabled;

void setSubtitleSearchTraceEnabled(bool enabled) {
  _subtitleSearchTraceEnabled = enabled;
}

void subtitleSearchTrace(
  String stage, {
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  if (!_subtitleSearchTraceEnabled) {
    return;
  }
  final formattedFields = fields.entries
      .map((entry) => '${entry.key}=${_stringifyTraceValue(entry.value)}')
      .join(', ');
  final suffix = formattedFields.isEmpty ? '' : ' | $formattedFields';
  final line = '$stage$suffix';
  debugPrint('[SubtitleTrace] $line');
  debugPrint('[Starflow.Subtitle] $line');
  if (error != null) {
    debugPrint('[SubtitleTrace] error=$error');
    debugPrint('[Starflow.Subtitle] error=$error');
  }
  if (stackTrace != null) {
    final lines = stackTrace
        .toString()
        .trim()
        .split('\n')
        .take(6)
        .map((line) => line.trim());
    for (final line in lines) {
      debugPrint('[SubtitleTrace] stack=$line');
    }
  }
}

String _stringifyTraceValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is num || value is bool) {
    return '$value';
  }
  final text = '$value'.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length <= 180) {
    return text;
  }
  return '${text.substring(0, 177)}...';
}
