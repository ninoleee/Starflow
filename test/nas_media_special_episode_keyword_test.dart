import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_naming.dart';

const _root = 'https://nas.example.com/dav/Shows/';

String _collectionEntry(String href, String displayName) {
  return '''
  <d:response>
    <d:href>$href</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>$displayName</d:displayname>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>''';
}

String _fileEntry(String href, String displayName) {
  return '''
  <d:response>
    <d:href>$href</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>$displayName</d:displayname>
        <d:resourcetype/>
        <d:getcontenttype>video/x-matroska</d:getcontenttype>
        <d:getcontentlength>1048576</d:getcontentlength>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>''';
}

/// Builds a PROPFIND body for [directoryPath] (relative to [_root]) listing
/// [fileNames] and [childDirectories].
String _propfind(
  String directoryPath, {
  List<String> fileNames = const <String>[],
  List<String> childDirectories = const <String>[],
}) {
  final base = directoryPath.isEmpty ? '/dav/Shows/' : '/dav/Shows/$directoryPath/';
  final displayName = directoryPath.isEmpty
      ? 'Shows'
      : directoryPath.split('/').last;
  final entries = <String>[
    _collectionEntry(base, displayName),
    for (final child in childDirectories)
      _collectionEntry('$base${Uri.encodeComponent(child)}/', child),
    for (final fileName in fileNames)
      _fileEntry('$base${Uri.encodeComponent(fileName)}', fileName),
  ];
  return '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
${entries.join('\n')}
</d:multistatus>
''';
}

/// Serves a whole tree: keys are directory paths relative to [_root].
WebDavNasClient _clientFor(Map<String, String> directories) {
  return WebDavNasClient(
    MockClient((request) async {
      if (request.method != 'PROPFIND') {
        return http.Response('Not Found', 404);
      }
      final url = request.url.toString();
      for (final entry in directories.entries) {
        final expected =
            entry.key.isEmpty ? _root : '$_root${Uri.encodeComponent(entry.key).replaceAll('%2F', '/')}/';
        if (url == expected) {
          return http.Response.bytes(
            utf8.encode(entry.value),
            207,
            headers: const {'content-type': 'application/xml; charset=utf-8'},
          );
        }
      }
      return http.Response('Not Found', 404);
    }),
  );
}

Future<List<MediaItem>> _scan(Map<String, String> directories) {
  return _clientFor(directories).fetchLibrary(
    const MediaSourceConfig(
      id: 'nas-shows',
      name: 'Shows NAS',
      kind: MediaSourceKind.nas,
      endpoint: _root,
      enabled: true,
      webDavStructureInferenceEnabled: true,
    ),
    limit: 50,
  );
}

void main() {
  final keywords = MediaNaming.normalizeKeywords(<String>[
    ...kDefaultVarietySpecialEpisodeKeywords,
    ...kDefaultVarietyExtraKeywords,
  ]);

  bool matches(String value) {
    return MediaNaming.matchesAnySpecialCategoryKeyword(
      <String>[value],
      keywords: keywords,
    );
  }

  group('special category keyword matching', () {
    test('ambiguous english keywords only count at the end of a name', () {
      // Ordinary titles that merely contain the word.
      expect(matches('Interview with the Vampire'), isFalse);
      expect(matches('The.Interview.2014.1080p.BluRay.mkv'), isFalse);
      expect(matches('Trailer Park Boys'), isFalse);
      expect(matches('Bonus.Family.S01E01.mkv'), isFalse);
      expect(matches('Sample This 2013.mkv'), isFalse);
      expect(matches('The Clip Show S01E01.mkv'), isFalse);
      expect(matches('Run BTS! E120.mp4'), isFalse);
      expect(matches('Burn.the.Stage.BTS.2018.mkv'), isFalse);

      // Dedicated folders and Kodi-style suffixes still match.
      expect(matches('Trailers'), isTrue);
      expect(matches('clips'), isTrue);
      expect(matches('sample.mkv'), isTrue);
      expect(matches('Show S01E01-trailer.mkv'), isTrue);
      expect(matches('Movie.Name.bts.mkv'), isTrue);
    });

    test('chinese keywords are not swallowed by longer words', () {
      expect(matches('斗罗大陆 第100集 超前点播版.mp4'), isFalse);
      expect(matches('某综艺 第3期 大连麦当劳探店.mp4'), isFalse);
      expect(matches('某综艺 第2期 小考核现场.mp4'), isFalse);
      expect(matches('偶像练习生 第1期 练习室初评级.mp4'), isFalse);
      expect(matches('某剧 第5集 精彩片段回顾.mp4'), isFalse);
      expect(matches('某综艺 第1期 先导预热.mp4'), isFalse);

      expect(matches('某综艺 第5期 加更版.mp4'), isTrue);
      expect(matches('第7期 纯享版.mp4'), isTrue);
      expect(matches('先导片.mp4'), isTrue);
      expect(matches('第0期 超前营业.mp4'), isTrue);
      expect(matches('训练室全纪录.mp4'), isTrue);
    });

    test('keywords that extend into packaging suffixes still match', () {
      expect(matches('花絮合集'), isTrue);
      expect(matches('预告合集'), isTrue);
      expect(matches('番外篇.mp4'), isTrue);
      expect(matches('特别篇合集'), isTrue);
      expect(matches('制作特辑第1期.mp4'), isTrue);
    });

    test('multi word english keywords match at the end of a name', () {
      // Regression: the end-of-string alternative used to be escaped into a
      // literal `$`, so a keyword ending the name never matched.
      expect(matches('Deleted Scenes'), isTrue);
      expect(matches('Behind The Scenes'), isTrue);
      expect(matches('Featurettes'), isTrue);
    });
  });

  group('special episode season assignment', () {
    test('an explicit season survives a keyword hit in the title', () async {
      final items = await _scan(<String, String>{
        '': _propfind('', childDirectories: <String>['Trailer Park Boys']),
        'Trailer Park Boys': _propfind(
          'Trailer Park Boys',
          childDirectories: <String>['Season 2'],
        ),
        'Trailer Park Boys/Season 2': _propfind(
          'Trailer Park Boys/Season 2',
          fileNames: <String>[
            'Trailer Park Boys S02E01.mkv',
            'Trailer Park Boys S02E02.mkv',
          ],
        ),
      });

      expect(items, hasLength(2));
      expect(items.every((item) => item.seasonNumber == 2), isTrue);
      expect(items.map((item) => item.episodeNumber), containsAll(<int>[1, 2]));
    });

    test('a keyword still routes an unnumbered file into season zero',
        () async {
      final items = await _scan(<String, String>{
        '': _propfind('', childDirectories: <String>['某综艺']),
        '某综艺': _propfind(
          '某综艺',
          fileNames: <String>['某综艺 第1期.mkv', '某综艺 加更版.mkv'],
        ),
      });

      expect(items, hasLength(2));
      final special = items.firstWhere((item) => item.title.contains('加更版'));
      expect(special.seasonNumber, 0);
      final regular = items.firstWhere((item) => item.title.contains('第1期'));
      expect(regular.seasonNumber, isNot(0));
    });

    test('a keyword in an ancestor directory does not reclassify episodes',
        () async {
      final items = await _scan(<String, String>{
        '': _propfind('', childDirectories: <String>['clips']),
        'clips': _propfind('clips', childDirectories: <String>['某剧']),
        '某剧': _propfind('某剧', fileNames: <String>['某剧 S01E01.mkv']),
        'clips/某剧': _propfind(
          'clips/某剧',
          fileNames: <String>['某剧 S01E01.mkv', '某剧 S01E02.mkv'],
        ),
      });

      expect(items, hasLength(2));
      expect(items.every((item) => item.seasonNumber == 1), isTrue);
      expect(items.map((item) => item.episodeNumber), containsAll(<int>[1, 2]));
    });
  });
}
