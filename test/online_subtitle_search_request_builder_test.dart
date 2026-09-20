import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/online_subtitle_search_request_builder_io.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<String> hash(Uint8List bytes) async {
    final root = await Directory.systemTemp.createTemp('subtitle-hash-');
    try {
      final file = await File('${root.path}/movie.mkv').writeAsBytes(bytes);
      return (await buildOnlineSubtitleSearchRequestForRoute(
              SubtitleSearchRequest(query: 'Movie', filePath: file.path)))
          .fileHash;
    } finally {
      await root.delete(recursive: true);
    }
  }

  test('hash formats the unsigned high bit as sixteen hex digits', () async {
    final bytes = Uint8List(128 * 1024)..[7] = 0x80;
    expect(await hash(bytes), '8000000000020000');
  });

  test('hash carries across words and wraps modulo 64 bits', () async {
    final bytes = Uint8List(128 * 1024);
    final words = ByteData.sublistView(bytes);
    words.setUint32(0, 0xffffffff, Endian.little);
    expect(await hash(bytes), '000000010001ffff');
    words.setUint32(4, 0xffffffff, Endian.little);
    expect(await hash(bytes), '000000000001ffff');
  });

  test('short overlapping blocks are skipped, adjacent blocks counted once',
      () async {
    expect(await hash(Uint8List(128 * 1024 - 1)), isEmpty);
    final bytes = Uint8List(128 * 1024);
    final words = ByteData.sublistView(bytes);
    words.setUint32(64 * 1024 - 8, 1, Endian.little);
    words.setUint32(64 * 1024, 2, Endian.little);
    expect(await hash(bytes), '0000000000020003');
  });
}
