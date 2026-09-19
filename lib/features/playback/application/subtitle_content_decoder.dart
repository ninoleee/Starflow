import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart';

const _subtitleExtensions = <String>{'.srt', '.ass', '.ssa', '.vtt'};

String decodeSubtitleBytes(List<int> bytes) {
  if (bytes.isEmpty) return '';
  if (isSubtitleZipBytes(bytes)) {
    throw const SubtitleContentException('字幕是压缩包，请先选择其中的文本字幕文件');
  }
  final input = _stripUtf8Bom(bytes);
  if (_hasPrefix(bytes, const [0xff, 0xfe]) ||
      _hasPrefix(bytes, const [0xfe, 0xff])) {
    return utf16.decode(bytes);
  }
  try {
    return utf8.decode(input);
  } catch (_) {
    final detected = Charset.detect(
      input,
      orders: [gbk, utf8, latin1],
      defaultEncoding: gbk,
    );
    return (detected ?? gbk).decode(input);
  }
}

bool isSubtitleZipBytes(List<int> bytes) {
  return _hasPrefix(bytes, const [0x50, 0x4b, 0x03, 0x04]) ||
      _hasPrefix(bytes, const [0x50, 0x4b, 0x05, 0x06]) ||
      _hasPrefix(bytes, const [0x50, 0x4b, 0x07, 0x08]);
}

List<int> extractSubtitleBytesFromZip(
  List<int> bytes, {
  String preferredName = '',
}) {
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  final entries = archive.files
      .where((file) => file.isFile && _isSubtitleFile(file.name))
      .toList();
  if (entries.isEmpty) {
    throw const SubtitleContentException('压缩包内没有可用的文本字幕');
  }
  final normalizedPreferred = preferredName.trim().toLowerCase();
  entries.sort((left, right) {
    int score(String name) {
      final normalized = name.toLowerCase();
      return normalizedPreferred.isNotEmpty &&
              (normalized.contains(normalizedPreferred) ||
                  normalizedPreferred.contains(normalized))
          ? 1
          : 0;
    }

    return score(right.name).compareTo(score(left.name));
  });
  return List<int>.from(entries.first.content as List<int>);
}

bool _isSubtitleFile(String name) {
  final lower = name.toLowerCase();
  return _subtitleExtensions.any(lower.endsWith);
}

bool _hasPrefix(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var index = 0; index < prefix.length; index++) {
    if (bytes[index] != prefix[index]) return false;
  }
  return true;
}

List<int> _stripUtf8Bom(List<int> bytes) {
  return _hasPrefix(bytes, const [0xef, 0xbb, 0xbf]) ? bytes.sublist(3) : bytes;
}

class SubtitleContentException implements Exception {
  const SubtitleContentException(this.message);
  final String message;
  @override
  String toString() => message;
}
