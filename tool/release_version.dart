import 'dart:convert';
import 'dart:io';

final class ReleaseVersion {
  const ReleaseVersion(this.major, this.month, this.sequence);
  final int major;
  final int month;
  final int sequence;

  factory ReleaseVersion.parse(String raw) {
    final match =
        RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$').firstMatch(raw.trim());
    if (match == null) {
      throw FormatException('Expected major.month.sequence: $raw');
    }
    final version = ReleaseVersion(
        int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!));
    if (version.month < 1 || version.month > 12) {
      throw FormatException('Invalid month: $raw');
    }
    return version;
  }

  ReleaseVersion next(DateTime now) =>
      ReleaseVersion(major, now.month, month == now.month ? sequence + 1 : 0);

  int androidCode(int year, Map<String, dynamic> policy) {
    final sequenceRadix = policy['sequenceRadix'] as int;
    final majorRadix = policy['majorRadix'] as int;
    final epochYear = policy['epochYear'] as int;
    if (major < 0 ||
        major >= majorRadix ||
        sequence < 0 ||
        sequence >= sequenceRadix ||
        month < 1 ||
        month > 12 ||
        year < epochYear) {
      throw RangeError('Release version exceeds the supported code range');
    }
    final code = (policy['baseCode'] as int) +
        ((year - epochYear) * 12 + month - 1) * majorRadix * sequenceRadix +
        major * sequenceRadix +
        sequence;
    if (code > (policy['maxCode'] as int)) {
      throw RangeError('Android versionCode exhausted');
    }
    return code;
  }

  @override
  String toString() => '$major.$month.$sequence';
}

void main(List<String> args) {
  try {
    final pubspec = File(args.isEmpty ? 'pubspec.yaml' : args.single);
    final raw = pubspec.readAsStringSync();
    final pattern = RegExp(
        r'^version:[ \t]*(\d+\.\d+\.\d+(?:\+\d+)?)[ \t]*\r?$',
        multiLine: true);
    final matches = pattern.allMatches(raw).toList();
    if (matches.length != 1) {
      throw const FormatException('Expected one pubspec version');
    }
    final current = ReleaseVersion.parse(matches.single[1]!);
    final fixed =
        Platform.environment['STARFLOW_RELEASE_VERSION']?.trim() ?? '';
    final keepCurrent =
        Platform.environment['STARFLOW_KEEP_RELEASE_VERSION'] == '1';
    final now = DateTime.now();
    final version = keepCurrent
        ? current
        : (fixed.isEmpty ? current.next(now) : ReleaseVersion.parse(fixed));
    final policy = jsonDecode(
        File.fromUri(Platform.script.resolve('../config/release_version.json'))
            .readAsStringSync()) as Map<String, dynamic>;
    version.androidCode(now.year, policy);
    pubspec.writeAsStringSync(raw.replaceFirst(
        pattern, 'version: $version${raw.contains('\r\n') ? '\r' : ''}'));
    stdout.writeln(version);
  } catch (error) {
    stderr.writeln('Release version: $error');
    exitCode = 1;
  }
}
