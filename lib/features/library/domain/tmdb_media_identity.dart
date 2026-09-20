enum TmdbMediaType {
  movie,
  tv;

  static TmdbMediaType? fromItemType(String raw) =>
      switch (raw.trim().toLowerCase()) {
        'movie' || 'film' => movie,
        'tv' || 'series' || 'show' || 'season' || 'episode' => tv,
        _ => null,
      };
}

/// Unknown legacy types can still match by title or other external IDs, but
/// cannot establish an exact TMDB identity from a bare ID.
class TmdbMediaIdentity {
  const TmdbMediaIdentity({required this.mediaType, required this.id});

  final TmdbMediaType mediaType;
  final String id;

  static TmdbMediaIdentity? fromRaw(String id, String itemType) {
    final mediaType = TmdbMediaType.fromItemType(itemType);
    final normalizedId = id.trim();
    if (mediaType == null || normalizedId.isEmpty) return null;
    return TmdbMediaIdentity(mediaType: mediaType, id: normalizedId);
  }

  String get key => '${mediaType.name}|$id';

  @override
  bool operator ==(Object other) =>
      other is TmdbMediaIdentity &&
      other.mediaType == mediaType &&
      other.id == id;

  @override
  int get hashCode => Object.hash(mediaType, id);
}
