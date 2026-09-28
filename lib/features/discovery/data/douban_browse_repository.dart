import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/discovery/data/douban_api_client.dart';
import 'package:starflow/features/discovery/domain/douban_browse_models.dart';

final doubanBrowseRepositoryProvider = Provider<DoubanBrowseRepository>((ref) {
  return DoubanBrowseRepository(ref.watch(doubanApiClientProvider));
});

class DoubanBrowseRepository {
  DoubanBrowseRepository(this._client);

  final DoubanApiClient _client;
  final _cache = <String, (DateTime, DoubanBrowsePageData)>{};
  final _inFlight = <String, Future<DoubanBrowsePageData>>{};
  int _epoch = 0;

  Future<DoubanBrowsePageData> fetch(DoubanBrowseQuery query,
      {int start = 0, bool refresh = false}) {
    final key = '${query.cacheKey}|$start';
    if (refresh) _cache.remove(key);
    final cached = _cache.remove(key);
    if (cached != null &&
        !refresh &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 10)) {
      _cache[key] = cached;
      return Future.value(cached.$2);
    }
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final epoch = _epoch;
    final future = _client.fetchBrowsePage(query, start: start);
    _inFlight[key] = future;
    future.then((value) {
      if (epoch != _epoch || !identical(_inFlight[key], future)) return;
      _cache.remove(key);
      _cache[key] = (DateTime.now(), value);
      while (_cache.length > 12) {
        _cache.remove(_cache.keys.first);
      }
    }, onError: (Object _) {}).whenComplete(() {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    });
    return future;
  }

  void invalidateQuery(DoubanBrowseQuery query) {
    final prefix = '${query.cacheKey}|';
    _cache.removeWhere((key, _) => key.startsWith(prefix));
    _inFlight.removeWhere((key, _) => key.startsWith(prefix));
  }

  void clear() {
    _epoch++;
    _cache.clear();
    _inFlight.clear();
  }
}
