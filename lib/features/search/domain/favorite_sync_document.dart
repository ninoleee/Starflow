import 'dart:convert';
import 'dart:math';

import 'package:starflow/features/search/domain/favorite_sync_payload.dart';
import 'package:starflow/features/search/domain/search_models.dart';

const maxFavoriteResults = 200;

class FavoriteSyncEntry {
  const FavoriteSyncEntry({
    required this.key,
    required this.generation,
    required this.revision,
    required this.operation,
    required this.position,
    this.result,
  });

  final String key;
  // Membership and metadata clocks are separate: artwork cannot undo a delete.
  final int generation;
  final int revision;
  final String operation;
  final int position;
  final SearchResult? result;
  bool get deleted => result == null;

  Map<String, dynamic> toJson({bool forSync = false}) => {
        'key': key,
        'generation': generation,
        'revision': revision,
        'operation': operation,
        'position': position,
        'result': result == null
            ? null
            : forSync
                ? favoriteSyncResultJson(result!)
                : result!.toJson(),
      };

  FavoriteSyncEntry withResult(SearchResult? value) => FavoriteSyncEntry(
      key: key,
      generation: generation,
      revision: revision,
      operation: operation,
      position: position,
      result: value);

  factory FavoriteSyncEntry.fromJson(Map<String, dynamic> json) {
    final key = json['key'];
    final generation = json['generation'];
    final revision = json['revision'];
    final operation = json['operation'];
    final position = json['position'];
    if (key is! String ||
        key.isEmpty ||
        generation is! int ||
        generation < 0 ||
        generation > 1 << 50 ||
        revision is! int ||
        revision < 0 ||
        revision > 1 << 50 ||
        operation is! String ||
        position is! int ||
        position < 0 ||
        position > (1 << 50) ||
        !json.containsKey('result')) {
      throw const FormatException('Invalid favorite entry');
    }
    final result = json['result'] == null
        ? null
        : SearchResult.fromJson(json['result'] as Map<String, dynamic>);
    if (result != null &&
        (result.title.trim().isEmpty ||
            searchResultFavoriteKey(result) != key)) {
      throw const FormatException('Invalid favorite identity');
    }
    return FavoriteSyncEntry(
        key: key,
        generation: generation,
        revision: revision,
        operation: operation,
        position: position,
        result: result);
  }
}

class FavoriteSyncDocument {
  FavoriteSyncDocument([Map<String, FavoriteSyncEntry> entries = const {}])
      : entries = Map.unmodifiable(entries);

  final Map<String, FavoriteSyncEntry> entries;

  List<SearchResult> get favorites {
    final live = entries.values.where((e) => !e.deleted).toList()
      ..sort((a, b) {
        final order = b.position.compareTo(a.position);
        return order != 0 ? order : a.key.compareTo(b.key);
      });
    return live.map((e) => e.result!).toList();
  }

  void validateCapacity() {
    if (favorites.length > maxFavoriteResults) {
      throw StateError('收藏合并后超过 200 条，请先清理收藏后重试；未丢弃任何条目');
    }
    if (entries.length > 20000) {
      throw StateError('收藏同步记录过多，已停止同步以保留数据');
    }
  }

  FavoriteSyncDocument merge(FavoriteSyncDocument other) => mergeAll([other]);

  FavoriteSyncDocument withLocalPresentation(FavoriteSyncDocument local) =>
      FavoriteSyncDocument({
        for (final entry in entries.values)
          entry.key:
              entry.result != null && local.entries[entry.key]?.result != null
                  ? entry.withResult(preserveFavoritePresentation(
                      entry.result!, local.entries[entry.key]!.result!))
                  : entry,
      });

  FavoriteSyncDocument mergeAll(Iterable<FavoriteSyncDocument> others) {
    final merged = {...entries};
    for (final other in others) {
      for (final incoming in other.entries.values) {
        final local = merged[incoming.key];
        if (local == null || _compare(incoming, local) > 0) {
          merged[incoming.key] = incoming;
        }
      }
    }
    final result = FavoriteSyncDocument(merged);
    result.validateCapacity();
    return result;
  }

  static int _compare(FavoriteSyncEntry a, FavoriteSyncEntry b) {
    var order = a.generation.compareTo(b.generation);
    if (order != 0) return order;
    if (a.deleted != b.deleted) return a.deleted ? 1 : -1;
    order = a.revision.compareTo(b.revision);
    if (order != 0) return order;
    order = a.operation.compareTo(b.operation);
    return order != 0
        ? order
        : jsonEncode(a.toJson(forSync: true))
            .compareTo(jsonEncode(b.toJson(forSync: true)));
  }

  FavoriteSyncDocument setFavorite(String key, SearchResult? result) {
    final previous = entries[key];
    if (previous == null && result == null) return this;
    if (previous?.deleted == true && result == null) return this;
    if (result != null && searchResultFavoriteKey(result) != key) {
      throw const FormatException('Invalid favorite identity');
    }
    if (previous != null &&
        jsonEncode(previous.result?.toJson()) == jsonEncode(result?.toJson())) {
      return this;
    }
    final membershipChanged =
        previous == null || previous.deleted != (result == null);
    if (!membershipChanged &&
        result != null &&
        jsonEncode(favoriteSyncResultJson(previous.result!)) ==
            jsonEncode(favoriteSyncResultJson(result))) {
      return FavoriteSyncDocument(
          {...entries, key: previous.withResult(result)});
    }
    final revision = entries.values
            .fold<int>(0, (value, entry) => max(value, entry.revision)) +
        1;
    final random = Random.secure();
    final next = FavoriteSyncDocument({
      ...entries,
      key: FavoriteSyncEntry(
        key: key,
        generation: (previous?.generation ?? 0) + (membershipChanged ? 1 : 0),
        revision: revision,
        position: membershipChanged ? revision : previous.position,
        operation:
            base64UrlEncode(List.generate(16, (_) => random.nextInt(256))),
        result: result,
      ),
    });
    next.validateCapacity();
    return next;
  }

  String encodeForSync() => encode(forSync: true);

  String encode({bool forSync = false}) {
    final keys = entries.keys.toList()..sort();
    return jsonEncode({
      'format': 'starflow-favorites',
      'version': 2,
      'entries': [
        for (final key in keys) entries[key]!.toJson(forSync: forSync)
      ],
    });
  }

  factory FavoriteSyncDocument.decode(String raw) =>
      FavoriteSyncDocument.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  factory FavoriteSyncDocument.fromJson(Map<String, dynamic> json) {
    if (json['format'] != 'starflow-favorites' ||
        json['version'] != 2 ||
        json['entries'] is! List) {
      throw const FormatException('Invalid favorite sync document');
    }
    final entries = <String, FavoriteSyncEntry>{};
    for (final item in json['entries'] as List) {
      final entry = FavoriteSyncEntry.fromJson(item as Map<String, dynamic>);
      if (entries.containsKey(entry.key)) {
        throw const FormatException('Duplicate favorite identity');
      }
      entries[entry.key] = entry;
    }
    final result = FavoriteSyncDocument(entries);
    result.validateCapacity();
    return result;
  }
}
