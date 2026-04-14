import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/utils/network_image_headers.dart';

void main() {
  group('networkImageHeadersForUrl', () {
    test('returns Douban headers for Douban image hosts', () {
      final headers = networkImageHeadersForUrl(
        'https://img9.doubanio.com/view/photo/l_ratio_poster/public/p123.webp',
      );

      expect(headers, isNotNull);
      expect(headers!['Referer'], 'https://m.douban.com/');
      expect(headers['Accept'], contains('image/webp'));
    });

    test('returns null for unrelated hosts', () {
      final headers = networkImageHeadersForUrl(
        'https://image.tmdb.org/t/p/w500/sample.jpg',
      );

      expect(headers, isNull);
    });
  });

  group('validateNetworkImageHttpResponse', () {
    test('accepts image content-type responses without extra byte sniffing',
        () {
      final bytes = Uint8List.fromList(List<int>.filled(16, 0x41));
      final response = http.Response.bytes(
        bytes,
        200,
        headers: const <String, String>{'content-type': 'image/png'},
      );

      expect(
        validateNetworkImageHttpResponse(
          response,
          url: 'https://example.com/poster.png',
        ),
        same(bytes),
      );
    });

    test('accepts magic-byte image responses when content-type is generic', () {
      final bytes = Uint8List.fromList(<int>[
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
      final response = http.Response.bytes(
        bytes,
        200,
        headers: const <String, String>{
          'content-type': 'application/octet-stream',
        },
      );

      expect(
        validateNetworkImageHttpResponse(
          response,
          url: 'https://example.com/poster',
        ),
        same(bytes),
      );
    });

    test('rejects non-2xx responses', () {
      final response = http.Response.bytes(
        Uint8List.fromList(<int>[0x01]),
        404,
      );

      expect(
        () => validateNetworkImageHttpResponse(
          response,
          url: 'https://example.com/missing.png',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects empty bodies', () {
      final response = http.Response.bytes(
        Uint8List(0),
        200,
        headers: const <String, String>{'content-type': 'image/png'},
      );

      expect(
        () => validateNetworkImageHttpResponse(
          response,
          url: 'https://example.com/empty.png',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects non-image content without recognizable bytes', () {
      final response = http.Response.bytes(
        Uint8List.fromList(utf8.encode('not an image')),
        200,
        headers: const <String, String>{'content-type': 'text/plain'},
      );

      expect(
        () => validateNetworkImageHttpResponse(
          response,
          url: 'https://example.com/not-image.txt',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
