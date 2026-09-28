import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/discovery/data/douban_api_client.dart';
import 'package:starflow/features/discovery/domain/douban_browse_models.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';

final doubanBrowseRepositoryProvider = Provider<DoubanBrowseRepository>((ref) {
  return DoubanBrowseRepository(ref.watch(doubanApiClientProvider));
});

class DoubanBrowseRepository {
  DoubanBrowseRepository(this._client);

  final DoubanApiClient _client;
  final _cache = <String, (DateTime, DoubanBrowsePageData)>{};
  final _inFlight = <String, Future<DoubanBrowsePageData>>{};
  final _candidateCache = <String, (DateTime, List<DoubanEntry>)>{};
  final _candidateInFlight = <String, Future<List<DoubanEntry>>>{};
  int _epoch = 0;

  Future<DoubanBrowsePageData> fetch(DoubanBrowseQuery query,
      {int start = 0, bool refresh = false}) {
    final effectiveQuery = query.copyWith(minRatingCount: 0);
    final key = '${effectiveQuery.cacheKey}|$start';
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
    final future = _client.fetchBrowsePage(effectiveQuery, start: start);
    _inFlight[key] = future;
    future.then((value) {
      if (epoch != _epoch) return;
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

  Future<List<DoubanEntry>> fetchMatchingEntries(
    DoubanBrowseQuery query, {
    required int minimumRatingCount,
    bool refresh = false,
  }) {
    final effectiveQuery = query.copyWith(minRatingCount: 0);
    final key = effectiveQuery.cacheKey;
    if (refresh) _candidateCache.remove(key);
    final cached = _candidateCache.remove(key);
    if (cached != null &&
        !refresh &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 10)) {
      _candidateCache[key] = cached;
      return Future.value(cached.$2
          .where((entry) => entry.ratingCount >= minimumRatingCount)
          .toList(growable: false));
    }
    final pending = _candidateInFlight[key];
    if (pending != null) {
      return pending.then((entries) => entries
          .where((entry) => entry.ratingCount >= minimumRatingCount)
          .toList(growable: false));
    }
    final epoch = _epoch;
    final future =
        _client.fetchBrowseEntries(effectiveQuery, minimumRatingCount: 1);
    _candidateInFlight[key] = future;
    future.then((value) {
      if (epoch != _epoch) return;
      _candidateCache.remove(key);
      _candidateCache[key] = (DateTime.now(), value);
      while (_candidateCache.length > 12) {
        _candidateCache.remove(_candidateCache.keys.first);
      }
    }, onError: (Object _) {}).whenComplete(() {
      if (identical(_candidateInFlight[key], future)) {
        _candidateInFlight.remove(key);
      }
    });
    return future.then((entries) => entries
        .where((entry) => entry.ratingCount >= minimumRatingCount)
        .toList(growable: false));
  }

  void clear() {
    _epoch++;
    _cache.clear();
    _inFlight.clear();
    _candidateCache.clear();
    _candidateInFlight.clear();
  }
}
