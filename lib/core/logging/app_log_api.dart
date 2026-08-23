import 'dart:convert';

enum AppLogLevel {
  trace,
  info,
  warning,
  error,
}

const Set<AppLogLevel> kDefaultRecordedAppLogLevels = <AppLogLevel>{
  AppLogLevel.trace,
  AppLogLevel.info,
  AppLogLevel.warning,
  AppLogLevel.error,
};

class AppLogEntry {
  const AppLogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.fields = const <String, Object?>{},
    this.error = '',
    this.stackTrace = '',
  });

  final DateTime timestamp;
  final AppLogLevel level;
  final String category;
  final String message;
  final Map<String, Object?> fields;
  final String error;
  final String stackTrace;

  static AppLogEntry? tryParse(String line) {
    try {
      final json = Map<String, dynamic>.from(jsonDecode(line) as Map);
      final rawLevel = json['level'] as String? ?? '';
      final level = AppLogLevel.values.where(
        (candidate) => candidate.name == rawLevel,
      );
      if (level.isEmpty) {
        return null;
      }
      return AppLogEntry(
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        level: level.first,
        category: json['category'] as String? ?? '',
        message: json['message'] as String? ?? '',
        fields: Map<String, Object?>.from(
          (json['fields'] as Map?) ?? const <String, Object?>{},
        ),
        error: json['error'] as String? ?? '',
        stackTrace: json['stackTrace'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

class AppLogSummary {
  const AppLogSummary({
    required this.supported,
    required this.fileCount,
    required this.totalBytes,
    this.directoryPath = '',
  });

  final bool supported;
  final int fileCount;
  final int totalBytes;
  final String directoryPath;
}

class AppLogExportData {
  const AppLogExportData({
    required this.bytes,
    required this.fileCount,
  });

  final List<int> bytes;
  final int fileCount;

  bool get isEmpty => bytes.isEmpty;
}

abstract class AppLogService {
  bool get isSupported;

  bool get isEnabled;

  int get maxBytes;

  Set<AppLogLevel> get recordedLevels;

  Future<void> configure({
    required bool enabled,
    required int maxBytes,
    required Set<AppLogLevel> recordedLevels,
  });

  void log(
    AppLogLevel level,
    String category,
    String message, {
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  });

  Future<void> logCritical(
    String category,
    String message, {
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  });

  Future<void> flush();

  Future<AppLogSummary> inspect();

  Future<List<AppLogEntry>> read({int limit = 300});

  Future<AppLogExportData> export();

  Future<void> clear();
}

class AppLogFormatter {
  const AppLogFormatter._();

  static const String redactedValue = '<redacted>';
  static final RegExp _sensitiveKey = RegExp(
    r'(authorization|cookie|password|passwd|token|api[-_]?key|auth[-_]?key|secret|credential|signature|session)',
    caseSensitive: false,
  );
  static final RegExp _bearerValue = RegExp(
    r'Bearer\s+[A-Za-z0-9._~+\-/]+=*',
    caseSensitive: false,
  );
  static final RegExp _inlineSecret = RegExp(
    r'((?:access[_-]?token|token|api[_-]?key|auth[_-]?key|password|cookie|authorization|secret|sign(?:ature)?|session|x-amz-(?:credential|signature|security-token))=)[^&\s,;]+',
    caseSensitive: false,
  );

  static String format({
    required AppLogLevel level,
    required String category,
    required String message,
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
    DateTime? timestamp,
  }) {
    final record = <String, Object?>{
      'timestamp': (timestamp ?? DateTime.now()).toIso8601String(),
      'level': level.name,
      'category': _sanitizeString(category, maxLength: 160),
      'message': _sanitizeString(message, maxLength: 4000),
      if (fields.isNotEmpty) 'fields': sanitizeFields(fields),
      if (error != null)
        'error': _sanitizeString(error.toString(), maxLength: 8000),
      if (stackTrace != null)
        'stackTrace': _sanitizeString(
          stackTrace.toString(),
          maxLength: 12000,
        ),
    };
    return '${jsonEncode(record)}\n';
  }

  static Map<String, Object?> sanitizeFields(Map<String, Object?> fields) {
    return <String, Object?>{
      for (final entry in fields.entries)
        entry.key: _sensitiveKey.hasMatch(entry.key)
            ? redactedValue
            : _sanitizeValue(entry.value),
    };
  }

  static Object? _sanitizeValue(Object? value) {
    if (value == null || value is num || value is bool) {
      return value;
    }
    if (value is Map) {
      return sanitizeFields(<String, Object?>{
        for (final entry in value.entries) entry.key.toString(): entry.value,
      });
    }
    if (value is Iterable) {
      return value.take(100).map(_sanitizeValue).toList(growable: false);
    }
    return _sanitizeString(value.toString(), maxLength: 4000);
  }

  static String _sanitizeString(String value, {required int maxLength}) {
    var sanitized = value.replaceAll(_bearerValue, 'Bearer $redactedValue');
    sanitized = sanitized.replaceAllMapped(
      _inlineSecret,
      (match) => '${match.group(1)}$redactedValue',
    );
    if (sanitized.length <= maxLength) {
      return sanitized;
    }
    return '${sanitized.substring(0, maxLength)}…';
  }
}
