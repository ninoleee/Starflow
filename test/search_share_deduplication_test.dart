import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/search/domain/search_models.dart';

SearchResult _result(String url, {String password = ''}) => SearchResult(
      id: 'first',
      title: 'same title',
      posterUrl: '',
      providerId: 'provider',
      providerName: 'Provider',
      quality: '',
      sizeLabel: '免提取码',
      seeders: 0,
      summary: '',
      resourceUrl: url,
      password: password,
    );

String _key(String url) => searchResultDeduplicationKey(_result(url));

void main() {
  test('115 domain, scheme, trailing slash and tracking variants deduplicate',
      () {
    final expected = _key('https://115.com/s/AbC123');
    for (final url in [
      'https://115cdn.com/s/AbC123?password=abcd',
      'http://www.115cdn.com/s/AbC123/?utm_source=search',
      'https://anxia.com/s/AbC123#from-search',
      'https://WWW.ANXIA.COM/s/AbC123',
      '115.com/s/AbC123',
      '//115cdn.com/s/AbC123',
    ]) {
      expect(_key(url), expected, reason: url);
    }
  });

  test('known Quark and Aliyun share links deduplicate by share code', () {
    expect(_key('https://pan.quark.cn/s/aB123?pwd=abcd&from=app'),
        _key('http://pan.quark.cn/s/aB123/'));
    expect(_key('https://www.aliyundrive.com/s/aB123'),
        _key('https://www.alipan.com/s/aB123?from=app'));
    expect(_key('https://www.123pan.com/s/aB-123'),
        _key('https://www.123684.com/s/aB-123'));
  });

  test('different shares, providers and case-sensitive codes remain distinct',
      () {
    final urls = [
      'https://115.com/s/AbC123',
      'https://115.com/s/abc123',
      'https://115.com/s/other',
      'https://pan.quark.cn/s/AbC123',
      'https://www.alipan.com/s/AbC123',
      'https://pan.baidu.com/s/AbC123',
      'https://drive.uc.cn/s/AbC123',
    ];
    expect(urls.map(_key).toSet(), hasLength(urls.length));
  });

  test('unknown domains and scoped folders do not merge as a whole share', () {
    final urls = [
      'https://115.com/s/abc',
      'https://115.com.evil.test/s/abc',
      'https://example.test/s/abc',
      'https://example.test/s/abc?file=2',
      'https://115.com/s/abc?cid=1',
      'https://115.com/s/abc?cid=2',
      'https://pan.quark.cn/s/abc/folder1',
      'https://pan.quark.cn/s/abc/folder2',
      'https://pan.quark.cn/s/abc#/folder/1',
      'https://pan.quark.cn/s/abc#/folder/2',
    ];
    expect(urls.map(_key).toSet(), hasLength(urls.length));
    expect(_key('https://example.test/s/abc?pwd=a'),
        _key('https://example.test/s/abc?pwd=b'));
  });

  test('merging retains metadata and fills missing embedded or separate code',
      () {
    for (final duplicate in [
      _result('https://anxia.com/s/AbC123?password=abcd'),
      _result('https://115cdn.com/s/AbC123', password: 'abcd'),
    ]) {
      final first = _result('https://115.com/s/AbC123');
      final merged = mergeSearchResultShareCredentials(first, duplicate);
      expect(merged.id, first.id);
      expect(merged.title, first.title);
      expect(merged.providerId, first.providerId);
      expect(merged.password, 'abcd');
      expect(Uri.parse(merged.resourceUrl).host, '115.com');
      expect(Uri.parse(merged.resourceUrl).queryParameters['password'], 'abcd');
      expect(merged.sizeLabel, '提取码 abcd');
      expect(searchResultDeduplicationKey(merged),
          searchResultDeduplicationKey(first));
    }
    final quark = mergeSearchResultShareCredentials(
      _result('https://pan.quark.cn/s/AbC123'),
      _result('https://pan.quark.cn/s/AbC123', password: 'abcd'),
    );
    expect(Uri.parse(quark.resourceUrl).queryParameters['pwd'], 'abcd');
  });

  test('existing credentials are never replaced by a conflicting duplicate',
      () {
    final first = _result('https://115.com/s/abc?password=first');
    final duplicate = _result('https://115cdn.com/s/abc?password=second');
    expect(mergeSearchResultShareCredentials(first, duplicate), same(first));
    final other = _result('https://115.com/s/other');
    expect(mergeSearchResultShareCredentials(other, duplicate), same(other));
  });

  test('separate Quark password is available to validation and save URL', () {
    final first = _result('https://pan.quark.cn/s/abc', password: 'abcd');
    final prepared = prepareSearchResultShareCredentials(first);
    expect(Uri.parse(prepared.resourceUrl).queryParameters['pwd'], 'abcd');
    expect(prepared.password, 'abcd');
    expect(searchResultFavoriteKey(prepared), searchResultFavoriteKey(first));
    expect(prepareSearchResultShareCredentials(prepared), same(prepared));
    final conflict = _result(
        'https://pan.quark.cn/s/abc?pwd=first&password=second',
        password: 'third');
    expect(searchResultSharePassword(conflict), 'first');
    expect(prepareSearchResultShareCredentials(conflict), same(conflict));
  });

  test('same-share identity does not migrate existing favorite keys', () {
    final first = _result('https://115.com/s/abc');
    final alias = _result('https://115cdn.com/s/abc');
    expect(searchResultDeduplicationKey(first),
        searchResultDeduplicationKey(alias));
    expect(
        searchResultFavoriteKey(first), isNot(searchResultFavoriteKey(alias)));
  });
}
