import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

bool _metadataSearchTraceEnabled = false;
const bool _metadataSearchTraceRuntimeEnabled = true;
const String _metadataSearchTraceName = 'Starflow.MetadataSearch';

bool get metadataSearchTraceEnabled => _metadataSearchTraceEnabled;

void setMetadataSearchTraceEnabled(bool enabled) {
  _metadataSearchTraceEnabled = enabled;
}

void metadataSearchTrace(
  String stage, {
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  if (!_metadataSearchTraceRuntimeEnabled || !_metadataSearchTraceEnabled) {
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
    name: _metadataSearchTraceName,
    error: error,
    stackTrace: stackTrace,
  );
  debugPrint('[MetadataSearch] $message');
}

String _stringifyTraceValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  final text = value.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length <= 320) {
    return text;
  }
  return '${text.substring(0, 317)}...';
}
