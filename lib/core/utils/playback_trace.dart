import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

bool _playbackTraceEnabled = false;
const String _playbackTraceName = 'Starflow.Playback';

bool get playbackTraceEnabled => _playbackTraceEnabled;

void setPlaybackTraceEnabled(bool enabled) {
  _playbackTraceEnabled = enabled;
}

void playbackTrace(
  String stage, {
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  if (!_playbackTraceEnabled) {
    return;
  }

  final traceFields = <String, Object?>{
    'stage': stage,
    for (final entry in fields.entries)
      entry.key: _stringifyTraceValue(entry.value),
  };

  final buffer = StringBuffer(stage);
  if (fields.isNotEmpty) {
    buffer.write(' | ');
    var isFirst = true;
    for (final entry in fields.entries) {
      if (!isFirst) {
        buffer.write(', ');
      }
      isFirst = false;
      buffer.write('${entry.key}=${_stringifyTraceValue(entry.value)}');
    }
  }
  if (error != null) {
    buffer.write(' | error=${_stringifyTraceValue(error)}');
  }
  final message = buffer.toString();

  developer.log(
    message,
    name: _playbackTraceName,
    error: error,
    stackTrace: stackTrace,
  );
  developer.Timeline.instantSync(
    _playbackTraceName,
    arguments: traceFields,
  );
  debugPrint('[PlaybackTrace] $message');
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
