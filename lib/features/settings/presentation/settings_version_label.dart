import 'package:package_info_plus/package_info_plus.dart';

const String _starflowBuildDate = String.fromEnvironment(
  'STARFLOW_BUILD_DATE',
  defaultValue: '2026-04-13',
);

class SettingsVersionFooterInfo {
  const SettingsVersionFooterInfo({
    required this.author,
    required this.version,
    required this.buildDate,
  });

  final String author;
  final String version;
  final String buildDate;
}

SettingsVersionFooterInfo? resolveSettingsVersionFooterInfo(PackageInfo info) {
  final version = info.version.trim();
  if (version.isEmpty) {
    return null;
  }

  return SettingsVersionFooterInfo(
    author: 'Nino',
    version: version,
    buildDate: _normalizeBuildDate(_starflowBuildDate),
  );
}

String _normalizeBuildDate(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length != 8) {
    return trimmed;
  }
  final year = digits.substring(0, 4);
  final month = digits.substring(4, 6);
  final day = digits.substring(6, 8);
  return '$year-$month-$day';
}
