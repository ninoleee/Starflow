import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

const bool kWebDavTraceEnabled = true;

void webDavTrace(
  String stage, {
  Map<String, Object?> fields = const <String, Object?>{},
}) {
  if (!kWebDavTraceEnabled) {
    return;
  }
  final buffer = StringBuffer('[WebDavTrace][$stage]');
  for (final entry in fields.entries) {
    buffer.write(' ${entry.key}=');
    buffer.write(_stringifyTraceValue(entry.value));
  }
  final message = buffer.toString();
  developer.log(message, name: 'WebDavTrace');
  debugPrint(message);
}

String _stringifyTraceValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is Iterable<Object?>) {
    return '[${value.map(_stringifyTraceValue).join(', ')}]';
  }
  if (value is Map<Object?, Object?>) {
    return '{${value.entries.map((entry) => '${entry.key}:${_stringifyTraceValue(entry.value)}').join(', ')}}';
  }
  return value.toString().replaceAll('\n', ' ');
}
