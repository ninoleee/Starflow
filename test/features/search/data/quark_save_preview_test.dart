import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';

http.Response _response(Object value) => http.Response.bytes(
      utf8.encode(jsonEncode(value)),
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  for (final result in ['complete', 'missing', 'duplicate', 'malformed']) {
    test('Quark share preview pagination: $result', () async {
      var pages = 0;
      final client = QuarkSaveClient(MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          expect(request.method, 'POST');
          expect((jsonDecode(request.body) as Map)['passcode'], 'abcd');
          return _response({
            'code': 0,
            'data': {'stoken': 'token'}
          });
        }
        expect(request.method, 'GET');
        if (request.url.path.endsWith('/sort')) {
          expect(request.url.queryParameters['pdir_fid'], 'selected-root');
          return _response({
            'code': 0,
            'data': {'list': []}
          });
        }
        expect(request.url.path, '/1/clouddrive/share/sharepage/detail');
        pages++;
        expect(request.url.queryParameters['_page'], '$pages');
        return _response({
          'code': 0,
          'metadata': {'_total': '2'},
          'data': {
            'list': result == 'malformed'
                ? [null]
                : [
                    if (pages == 1 || result != 'missing')
                      {
                        'fid': result == 'duplicate' ? '1' : '$pages',
                        'file_name': 'E0$pages.mkv',
                        'share_fid_token': 'file-token',
                      },
                  ],
          }
        });
      }));
      final preview = client.previewSave(
          shareUrl: 'https://pan.quark.cn/s/abc?pwd=abcd',
          cookie: 'quark-cookie',
          folderId: 'selected-root',
          folderPath: '/Library',
          saveFolderName: 'Show');
      if (result == 'complete') {
        final value = await preview;
        expect(value.missingVideos, hasLength(2));
        expect(value.localFolderExists, isFalse);
        expect(value.targetFolderPath, '/Library/Show');
      } else {
        await expectLater(preview, throwsA(isA<QuarkSaveException>()));
      }
      expect(pages, result == 'malformed' ? 1 : 2);
    });
  }
}
