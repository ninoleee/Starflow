import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

bool _detailResourceSwitchTraceEnabled = true;
const bool _detailResourceSwitchTraceRuntimeEnabled = true;
const String _detailResourceSwitchTraceName = 'Starflow.DetailResourceSwitch';
final Map<String, String> _detailResourceSwitchLastMessages =
    <String, String>{};

bool get detailResourceSwitchTraceEnabled => _detailResourceSwitchTraceEnabled;

void setDetailResourceSwitchTraceEnabled(bool enabled) {
  _detailResourceSwitchTraceEnabled = enabled;
  if (!enabled) {
    _detailResourceSwitchLastMessages.clear();
  }
}

void detailResourceSwitchTrace(
  String stage, {
  String dedupeKey = '',
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  if (!_detailResourceSwitchTraceRuntimeEnabled ||
      !_detailResourceSwitchTraceEnabled) {
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
  final resolvedDedupeKey = dedupeKey.trim().isEmpty ? stage : dedupeKey.trim();
  if (_detailResourceSwitchLastMessages[resolvedDedupeKey] == message) {
    return;
  }
  _detailResourceSwitchLastMessages[resolvedDedupeKey] = message;

  developer.log(
    message,
    name: _detailResourceSwitchTraceName,
    error: error,
    stackTrace: stackTrace,
  );
  debugPrint('[DetailResourceSwitch] $message');
}

String _stringifyTraceValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  final text = value.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length <= 240) {
    return text;
  }
  return '${text.substring(0, 237)}...';
}
