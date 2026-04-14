import 'dart:typed_data';

import 'package:http/http.dart' as http;

const Map<String, String> _doubanNetworkImageHeaders = <String, String>{
  'Referer': 'https://m.douban.com/',
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
  'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
};

Map<String, String>? networkImageHeadersForUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) {
    return null;
  }

  final host = uri.host.toLowerCase();
  if (host.isEmpty) {
    return null;
  }

  if (host == 'img1.doubanio.com' ||
      host == 'img2.doubanio.com' ||
      host == 'img3.doubanio.com' ||
      host == 'img9.doubanio.com' ||
      host.endsWith('.doubanio.com')) {
    return _doubanNetworkImageHeaders;
  }

  return null;
}

Uint8List validateNetworkImageHttpResponse(
  http.Response response, {
  required String url,
}) {
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError(
      'HTTP request failed, statusCode: ${response.statusCode}, $url',
    );
  }

  final bytes = response.bodyBytes;
  if (bytes.isEmpty) {
    throw StateError('Image response body is empty: $url');
  }

  final contentType = _headerValue(response.headers, 'content-type');
  if (!looksLikeNetworkImageResponse(contentType, bytes)) {
    throw StateError('Image response is not a decodable image: $url');
  }

  return bytes;
}

bool looksLikeNetworkImageResponse(String contentType, Uint8List bytes) {
  final normalized = contentType.toLowerCase();
  if (normalized.startsWith('image/')) {
    return true;
  }
  return looksLikeNetworkImageBytes(bytes);
}

bool looksLikeNetworkImageBytes(Uint8List bytes) {
  if (bytes.length < 12) {
    return false;
  }

  final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
  final isPng = bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47;
  final isGif = bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38;
  final isBmp = bytes[0] == 0x42 && bytes[1] == 0x4D;
  final isWebp = bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50;
  final isAvif = bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70 &&
      ((bytes[8] == 0x61 &&
              bytes[9] == 0x76 &&
              bytes[10] == 0x69 &&
              bytes[11] == 0x66) ||
          (bytes[8] == 0x61 &&
              bytes[9] == 0x76 &&
              bytes[10] == 0x69 &&
              bytes[11] == 0x73));
  return isJpeg || isPng || isGif || isBmp || isWebp || isAvif;
}

String _headerValue(Map<String, String> headers, String key) {
  final directValue = headers[key];
  if (directValue != null) {
    return directValue;
  }

  final normalizedKey = key.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == normalizedKey) {
      return entry.value;
    }
  }
  return '';
}
