import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

const bool _subtitleSearchTraceEnabled = false;
const String _subtitleSearchTraceName = 'Starflow.SubtitleSearch';

void subtitleSearchTrace(
  String stage, {
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  if (!_subtitleSearchTraceEnabled) {
    return;
  }

  final buffer = StringBuffer(stage);
  if (fields.isNotEmpty) {
    buffer.write(' | ');
    var isFirst = true;
    fields.forEach((key, value) {
      if (!isFirst) {
        buffer.write(', ');
      }
      isFirst = false;
      buffer.write('$key=${_stringifyTraceValue(value)}');
    });
  }
  if (error != null) {
    buffer.write(' | error=${_stringifyTraceValue(error)}');
  }
  final message = buffer.toString();

  developer.log(
    message,
    name: _subtitleSearchTraceName,
    error: error,
    stackTrace: stackTrace,
  );
  debugPrint('[SubtitleSearch] $message');
}

String _stringifyTraceValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  final text = value.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length <= 220) {
    return text;
  }
  return '${text.substring(0, 217)}...';
}
