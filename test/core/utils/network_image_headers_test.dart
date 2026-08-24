import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/utils/network_image_headers.dart';

void main() {
  test('networkImageHeadersForUrl only adds headers for Douban images', () {
    final headers = networkImageHeadersForUrl(
      'https://img9.doubanio.com/view/photo/l_ratio_poster/public/p123.webp',
    );

    expect(headers, isNotNull);
    expect(headers!['Referer'], 'https://m.douban.com/');
    expect(headers['Accept'], contains('image/webp'));
    expect(
      networkImageHeadersForUrl(
        'https://image.tmdb.org/t/p/w500/sample.jpg',
      ),
      isNull,
    );
  });

  group('validateNetworkImageHttpResponse', () {
    test('accepts image content type or recognizable image bytes', () {
      final contentTypeBytes = Uint8List.fromList(List<int>.filled(16, 0x41));
      final contentTypeResponse = http.Response.bytes(
        contentTypeBytes,
        200,
        headers: const <String, String>{'content-type': 'image/png'},
      );

      expect(
        validateNetworkImageHttpResponse(
          contentTypeResponse,
          url: 'https://example.com/poster.png',
        ),
        same(contentTypeBytes),
      );

      final magicBytes = Uint8List.fromList(<int>[
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);
      final magicResponse = http.Response.bytes(
        magicBytes,
        200,
        headers: const <String, String>{
          'content-type': 'application/octet-stream',
        },
      );

      expect(
        validateNetworkImageHttpResponse(
          magicResponse,
          url: 'https://example.com/poster',
        ),
        same(magicBytes),
      );
    });

    test('rejects failed, empty, and non-image responses', () {
      final cases = <({String name, String url, http.Response response})>[
        (
          name: 'non-2xx status',
          url: 'https://example.com/missing.png',
          response: http.Response.bytes(Uint8List.fromList(<int>[0x01]), 404),
        ),
        (
          name: 'empty body',
          url: 'https://example.com/empty.png',
          response: http.Response.bytes(
            Uint8List(0),
            200,
            headers: const <String, String>{'content-type': 'image/png'},
          ),
        ),
        (
          name: 'unrecognized non-image body',
          url: 'https://example.com/not-image.txt',
          response: http.Response.bytes(
            Uint8List.fromList(utf8.encode('not an image')),
            200,
            headers: const <String, String>{'content-type': 'text/plain'},
          ),
        ),
      ];

      for (final scenario in cases) {
        expect(
          () => validateNetworkImageHttpResponse(
            scenario.response,
            url: scenario.url,
          ),
          throwsA(isA<StateError>()),
          reason: scenario.name,
        );
      }
    });
  });
}
