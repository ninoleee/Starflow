import 'package:starflow/features/library/domain/media_models.dart';

/// A read-only card projection. Resource identity and persisted rows stay intact.
List<MediaItem> aggregateMediaWorks(List<MediaItem> items) {
  final groups = <_WorkGroup>[];
  final byId = <String, Set<_WorkGroup>>{};
  for (final card in items) {
    for (final item
        in card.workResources.isEmpty ? [card] : card.workResources) {
      final identity = _WorkIdentity(item);
      final candidates = <_WorkGroup>{
        for (final key in identity.idKeys) ...?byId[key],
      }.where((group) => group.active).toList();
      final compatible = candidates
          .where(
            (group) => group.identities.every(identity.idsCompatible),
          )
          .toList();
      // Contradictory bridges must not join otherwise independent works.
      final canJoin = compatible.length == candidates.length &&
          compatible.every((a) => compatible.every(a.idsCompatible));
      final group =
          canJoin && compatible.isNotEmpty ? compatible.first : _WorkGroup();
      if (group.items.isEmpty) groups.add(group);
      if (canJoin) {
        for (final other in compatible.skip(1)) {
          group.absorb(other);
        }
      }
      group.add(item, identity);
      for (final key in group.identities.expand((value) => value.idKeys)) {
        (byId[key] ??= {}).add(group);
      }
    }
  }

  final byTitle = <String, Set<_WorkGroup>>{};
  for (final group in groups.where((group) => group.active)) {
    for (final key in group.identities.expand((value) => value.titleKeys)) {
      (byTitle[key] ??= {}).add(group);
    }
  }
  for (final bucket in byTitle.values) {
    final candidates = bucket.map((group) => group.root).toSet().toList();
    if (candidates.length < 2) continue;
    // A title-only resource cannot bridge two conflicting identified works.
    if (!candidates.every((a) => candidates.every(a.idsCompatible))) continue;
    final identified = candidates.where((group) => group.hasIds).toList();
    if (identified.length > 1) continue;
    final group = candidates.first;
    for (final other in candidates.skip(1)) {
      group.absorb(other);
    }
  }

  final order = <MediaItem, int>{};
  var index = 0;
  for (final card in items) {
    for (final item
        in card.workResources.isEmpty ? [card] : card.workResources) {
      order.putIfAbsent(item, () => index++);
    }
  }
  final active = groups.where((group) => group.active).toList();
  for (final group in active) {
    group.items.sort((a, b) => order[a]!.compareTo(order[b]!));
  }
  active.sort((a, b) => order[a.items.first]!.compareTo(order[b.items.first]!));
  return List.unmodifiable(active.map((group) => group.items.length == 1
      ? group.items.single
      : group.items.first.copyWith(
          workResources: List.unmodifiable(group.items),
        )));
}

class _WorkIdentity {
  _WorkIdentity(MediaItem item)
      : type = switch (item.itemType.trim().toLowerCase()) {
          'movie' || 'film' => 'movie',
          'series' || 'tv' || 'show' => 'tv',
          _ => '',
        },
        tmdb = item.tmdbId.trim(),
        imdb = item.imdbId.trim().toLowerCase(),
        year = item.year,
        titles = {item.title, item.originalTitle}
            .map(_normalizeTitle)
            .where((title) => title.isNotEmpty)
            .toSet();

  final String type;
  final String tmdb;
  final String imdb;
  final int year;
  final Set<String> titles;

  Iterable<String> get idKeys sync* {
    if (type.isEmpty) return;
    if (tmdb.isNotEmpty) yield '$type|tmdb|$tmdb';
    if (imdb.isNotEmpty) yield '$type|imdb|$imdb';
  }

  Iterable<String> get titleKeys sync* {
    if (type.isEmpty || year <= 0) return;
    for (final title in titles) {
      yield '$type|$year|$title';
    }
  }

  bool idsCompatible(_WorkIdentity other) =>
      type == other.type &&
      (tmdb.isEmpty || other.tmdb.isEmpty || tmdb == other.tmdb) &&
      (imdb.isEmpty || other.imdb.isEmpty || imdb == other.imdb);

  static String _normalizeTitle(String title) =>
      title.trim().toLowerCase().replaceAll(
          RegExp(
              r'[\s\-_.:;!?/\\|()\[\]{}<>"\x27,\u300a\u300b\u3010\u3011\uff08\uff09\u201c\u201d\u00b7]+'),
          '');
}

class _WorkGroup {
  final items = <MediaItem>[];
  final identities = <_WorkIdentity>[];
  _WorkGroup? _parent;
  bool get active => _parent == null;
  _WorkGroup get root => _parent?.root ?? this;
  bool get hasIds => identities.any((identity) => identity.idKeys.isNotEmpty);

  void add(MediaItem item, _WorkIdentity identity) {
    if (items.any((existing) =>
        existing.sourceKind == item.sourceKind &&
        existing.sourceId == item.sourceId &&
        existing.id == item.id &&
        existing.playbackItemId == item.playbackItemId &&
        existing.preferredMediaSourceId == item.preferredMediaSourceId &&
        existing.actualAddress == item.actualAddress &&
        existing.streamUrl == item.streamUrl)) {
      return;
    }
    items.add(item);
    identities.add(identity);
  }

  bool idsCompatible(_WorkGroup other) => identities
      .every((identity) => other.identities.every(identity.idsCompatible));

  void absorb(_WorkGroup other) {
    if (identical(this, other)) return;
    for (var i = 0; i < other.items.length; i++) {
      add(other.items[i], other.identities[i]);
    }
    other._parent = this;
  }
}
