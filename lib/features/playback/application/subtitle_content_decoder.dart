import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart';

const _subtitleExtensions = <String>{'.srt', '.ass', '.ssa', '.vtt'};
const maxSubtitleBytes = 16 * 1024 * 1024;
const maxSubtitleArchiveBytes = 64 * 1024 * 1024;
const maxSubtitleArchiveEntries = 256;

List<int> readBoundedSubtitleEntry(ArchiveFile entry) {
  final output = _BoundedSubtitleOutput();
  final raw = entry.rawContent;
  if (raw is ZipFile && entry.compression == CompressionType.deflate) {
    // The native archive decoder buffers all chunks before forwarding them.
    // Inflate writes through our bounded output as each block is expanded.
    Inflate.stream(raw.getStream(decompress: false), output: output);
  } else if (entry.compression == CompressionType.none) {
    entry.writeContent(output);
  } else {
    throw const SubtitleContentException('字幕 ZIP 使用不支持的压缩方法');
  }
  final bytes = output.getBytes();
  if (bytes.length != entry.size || getCrc32(bytes) != entry.crc32) {
    throw const SubtitleContentException('字幕压缩包校验失败');
  }
  return bytes;
}

class _BoundedSubtitleOutput extends OutputMemoryStream {
  void _check(int count) {
    if (length + count > maxSubtitleBytes) {
      throw const SubtitleContentException('字幕解压超过 16 MiB 限制');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }
}

/// Inspect ZIP metadata before decoding, including entries the caller will skip.
Archive decodeBoundedSubtitleArchive(List<int> bytes) {
  if (bytes.length > maxSubtitleBytes) {
    throw const SubtitleContentException('字幕下载超过 16 MiB 限制');
  }
  final directory = ZipDirectory()..read(InputMemoryStream(bytes));
  if (directory.fileHeaders.length > maxSubtitleArchiveEntries) {
    throw const SubtitleContentException('字幕压缩包文件过多');
  }
  var total = 0;
  for (final header in directory.fileHeaders) {
    final size = header.uncompressedSize;
    total += size;
    if (size > maxSubtitleBytes ||
        total > maxSubtitleArchiveBytes ||
        ((header.externalFileAttributes >> 16) & 0xf000) == 0xa000) {
      throw const SubtitleContentException('字幕压缩包超出解压限制或包含符号链接');
    }
  }
  return ZipDecoder().decodeBytes(bytes);
}

String detectSubtitleFormat(String content) {
  final text = content.trimLeft();
  if (text.isEmpty ||
      text.contains('\u0000') ||
      RegExp(r'<(?:!doctype|html)\b', caseSensitive: false).hasMatch(text)) {
    throw const SubtitleContentException('下载内容不是有效文本字幕');
  }
  if (RegExp(r'^WEBVTT(?:\s|$)').hasMatch(text)) return 'vtt';
  if (RegExp(r'^\[Events\]\s*$', multiLine: true, caseSensitive: false)
          .hasMatch(text) &&
      RegExp(r'^Dialogue\s*:', multiLine: true, caseSensitive: false)
          .hasMatch(text)) {
    return 'ass';
  }
  if (RegExp(
          r'\d{1,3}:\d{2}:\d{2}[,.]\d{3}\s*-->\s*\d{1,3}:\d{2}:\d{2}[,.]\d{3}')
      .hasMatch(text)) {
    return 'srt';
  }
  throw const SubtitleContentException('未识别到 SRT、ASS/SSA 或 WebVTT 字幕内容');
}

String decodeSubtitleBytes(List<int> bytes) {
  if (bytes.length > maxSubtitleBytes) {
    throw const SubtitleContentException('字幕超过 16 MiB 限制');
  }
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
  final archive = decodeBoundedSubtitleArchive(bytes);
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
  return readBoundedSubtitleEntry(entries.first);
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
