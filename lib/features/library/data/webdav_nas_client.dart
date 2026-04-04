import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:xml/xml.dart';

final webDavNasClientProvider = Provider<WebDavNasClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return WebDavNasClient(client);
});

class WebDavNasClient {
  WebDavNasClient(this._client);

  final http.Client _client;

  Future<List<MediaCollection>> fetchCollections(
      MediaSourceConfig source) async {
    final endpoint = source.endpoint.trim();
    if (endpoint.isEmpty) {
      return const [];
    }

    final rootUri = Uri.parse(endpoint);
    final entries = await _propfind(rootUri, source: source);
    return entries
        .where((entry) => !entry.isSelf && entry.isCollection)
        .map(
          (entry) => MediaCollection(
            id: entry.uri.toString(),
            title: entry.name,
            sourceId: source.id,
            sourceName: source.name,
            sourceKind: source.kind,
            subtitle: 'WebDAV 目录',
          ),
        )
        .toList();
  }

  Future<List<MediaItem>> fetchLibrary(
    MediaSourceConfig source, {
    String? sectionId,
    String sectionName = '',
    int limit = 200,
  }) async {
    final endpoint = source.endpoint.trim();
    if (endpoint.isEmpty) {
      return const [];
    }

    final rootUri = Uri.parse(
        sectionId?.trim().isNotEmpty == true ? sectionId!.trim() : endpoint);
    final collectionId = rootUri.toString();
    final collectionName = sectionName.trim().isEmpty
        ? _displayNameFromUri(rootUri, fallback: source.name)
        : sectionName.trim();
    final items = <MediaItem>[];
    final visited = <String>{};

    Future<void> walk(Uri uri, int depth) async {
      if (items.length >= limit || depth > 8 || !visited.add(uri.toString())) {
        return;
      }

      final entries = await _propfind(uri, source: source);
      for (final entry in entries) {
        if (items.length >= limit) {
          return;
        }
        if (entry.isSelf) {
          continue;
        }
        if (entry.isCollection) {
          await walk(entry.uri, depth + 1);
          continue;
        }
        if (!_isPlayableVideo(entry)) {
          continue;
        }
        items.add(
          MediaItem(
            id: entry.uri.toString(),
            title: _stripExtension(entry.name),
            overview: entry.uri.toString(),
            posterUrl: '',
            year: 0,
            durationLabel: '文件',
            genres: const [],
            sectionId: collectionId,
            sectionName: collectionName,
            sourceId: source.id,
            sourceName: source.name,
            sourceKind: source.kind,
            streamUrl: entry.uri.toString(),
            streamHeaders: _headers(source),
            addedAt: entry.modifiedAt ?? DateTime.now(),
          ),
        );
      }
    }

    await walk(rootUri, 0);
    items.sort((left, right) => right.addedAt.compareTo(left.addedAt));
    return items;
  }

  Future<List<_WebDavEntry>> _propfind(
    Uri uri, {
    required MediaSourceConfig source,
  }) async {
    final request = http.Request('PROPFIND', uri)
      ..headers.addAll({
        ..._headers(source),
        'Depth': '1',
        'Content-Type': 'application/xml; charset=utf-8',
      })
      ..body = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname />
    <d:getcontentlength />
    <d:getcontenttype />
    <d:getlastmodified />
    <d:resourcetype />
  </d:prop>
</d:propfind>''';

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 207 && response.statusCode != 200) {
      throw WebDavNasException('WebDAV 请求失败：HTTP ${response.statusCode}');
    }
    if (response.body.trim().isEmpty) {
      return const [];
    }

    final document = XmlDocument.parse(response.body);
    final responses = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'response');
    final normalizedSelf = _normalizeUri(uri);

    return responses.map((node) {
      final href = _childText(node, 'href');
      final resolvedUri = _resolveHref(uri, href);
      final prop = node.descendants.whereType<XmlElement>().firstWhere(
            (element) => element.name.local == 'prop',
            orElse: () => XmlElement(XmlName('prop')),
          );
      final isCollection = prop.descendants
          .whereType<XmlElement>()
          .any((element) => element.name.local == 'collection');
      final displayName = _childText(prop, 'displayname');
      final contentType = _childText(prop, 'getcontenttype');
      final modifiedAt = DateTime.tryParse(_childText(prop, 'getlastmodified'));

      return _WebDavEntry(
        uri: resolvedUri,
        name: displayName.trim().isEmpty
            ? _displayNameFromUri(resolvedUri, fallback: source.name)
            : displayName.trim(),
        isCollection: isCollection,
        contentType: contentType.trim(),
        modifiedAt: modifiedAt,
        isSelf: _normalizeUri(resolvedUri) == normalizedSelf,
      );
    }).toList();
  }

  Map<String, String> _headers(MediaSourceConfig source) {
    final username = source.username.trim();
    final password = source.password;
    if (username.isEmpty) {
      return const {
        'Accept': '*/*',
      };
    }

    final token = base64Encode(utf8.encode('$username:$password'));
    return {
      'Accept': '*/*',
      'Authorization': 'Basic $token',
    };
  }

  bool _isPlayableVideo(_WebDavEntry entry) {
    final type = entry.contentType.toLowerCase();
    if (type.startsWith('video/')) {
      return true;
    }

    final path = entry.uri.path.toLowerCase();
    return const [
      '.mp4',
      '.m4v',
      '.mov',
      '.mkv',
      '.avi',
      '.ts',
      '.webm',
      '.flv',
      '.wmv',
      '.mpg',
      '.mpeg',
    ].any(path.endsWith);
  }

  Uri _resolveHref(Uri requestUri, String href) {
    final trimmed = href.trim();
    if (trimmed.isEmpty) {
      return requestUri;
    }
    final decoded = Uri.decodeFull(trimmed);
    final parsed = Uri.tryParse(decoded);
    if (parsed != null && parsed.hasScheme) {
      return parsed;
    }
    return requestUri.resolve(decoded);
  }

  String _childText(XmlElement node, String localName) {
    final match = node.children.whereType<XmlElement>().firstWhere(
          (element) => element.name.local == localName,
          orElse: () => XmlElement(XmlName(localName)),
        );
    return match.innerText.trim();
  }

  String _displayNameFromUri(Uri uri, {required String fallback}) {
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
    if (segments.isEmpty) {
      return fallback;
    }
    return Uri.decodeComponent(segments.last);
  }

  String _normalizeUri(Uri uri) {
    final path = uri.path.endsWith('/') && uri.path.length > 1
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return uri.replace(path: path, query: null, fragment: null).toString();
  }

  String _stripExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) {
      return fileName;
    }
    return fileName.substring(0, dotIndex);
  }
}

class WebDavNasException implements Exception {
  const WebDavNasException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _WebDavEntry {
  const _WebDavEntry({
    required this.uri,
    required this.name,
    required this.isCollection,
    required this.contentType,
    required this.modifiedAt,
    required this.isSelf,
  });

  final Uri uri;
  final String name;
  final bool isCollection;
  final String contentType;
  final DateTime? modifiedAt;
  final bool isSelf;
}
