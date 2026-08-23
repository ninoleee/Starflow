import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/logging/app_log_api.dart';

void main() {
  test('formatter emits JSON lines and redacts common secrets', () {
    final line = AppLogFormatter.format(
      level: AppLogLevel.error,
      category: 'network',
      message:
          'request failed authorization=Bearer secret-value&token=abc123',
      fields: const <String, Object?>{
        'cookie': 'session=secret',
        'url': 'https://example.test/video?access_token=url-secret&id=1',
        'headers': <String, Object?>{
          'Authorization': 'Bearer header-secret',
          'Accept': 'application/json',
        },
      },
      error: 'password=hunter2',
      timestamp: DateTime.utc(2026, 8, 23),
    );

    expect(line.endsWith('\n'), isTrue);
    final record = jsonDecode(line) as Map<String, dynamic>;
    final fields = record['fields'] as Map<String, dynamic>;
    final headers = fields['headers'] as Map<String, dynamic>;
    expect(record['timestamp'], '2026-08-23T00:00:00.000Z');
    expect(record['level'], 'error');
    expect(fields['cookie'], AppLogFormatter.redactedValue);
    expect(headers['Authorization'], AppLogFormatter.redactedValue);
    expect(headers['Accept'], 'application/json');
    expect(line, isNot(contains('secret-value')));
    expect(line, isNot(contains('abc123')));
    expect(line, isNot(contains('url-secret')));
    expect(line, isNot(contains('header-secret')));
    expect(line, isNot(contains('hunter2')));

    final entry = AppLogEntry.tryParse(line);
    expect(entry, isNotNull);
    expect(entry!.level, AppLogLevel.error);
    expect(entry.category, 'network');
    expect(entry.fields['cookie'], AppLogFormatter.redactedValue);
  });

  test('entry parser ignores malformed and unknown records', () {
    expect(AppLogEntry.tryParse('not-json'), isNull);
    expect(
      AppLogEntry.tryParse('{"level":"fatal","message":"boom"}'),
      isNull,
    );
  });
}
