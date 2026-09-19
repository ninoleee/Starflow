import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/subtitle_content_decoder.dart';

void main() {
  test('decodes UTF-8, UTF-16 and GBK subtitle bytes', () {
    const text = '你好，Starflow';
    expect(decodeSubtitleBytes(utf8.encode(text)), text);
    expect(decodeSubtitleBytes(utf16.encode(text)), text);
    expect(decodeSubtitleBytes(gbk.encode(text)), text);
  });

  test('selects a text subtitle from a ZIP archive', () {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('cover.jpg', [1, 2, 3]))
      ..addFile(ArchiveFile.string('movie.en.srt', 'English'))
      ..addFile(ArchiveFile.string('movie.zh.srt', '中文'));
    final bytes = ZipEncoder().encode(archive);
    expect(
      utf8.decode(extractSubtitleBytesFromZip(bytes, preferredName: 'zh')),
      '中文',
    );
  });

  test('rejects archives without text subtitle files', () {
    final archive = Archive()..addFile(ArchiveFile.bytes('image.sup', [1]));
    final bytes = ZipEncoder().encode(archive);
    expect(
      () => extractSubtitleBytesFromZip(bytes),
      throwsA(isA<SubtitleContentException>()),
    );
  });
}
