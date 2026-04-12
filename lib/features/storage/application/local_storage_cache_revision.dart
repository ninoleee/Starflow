import 'package:flutter_riverpod/flutter_riverpod.dart';

class LocalStorageDetailCacheScope {
  const LocalStorageDetailCacheScope({
    this.sourceIds = const <String>{},
    this.lookupKeys = const <String>{},
  });

  final Set<String> sourceIds;
  final Set<String> lookupKeys;

  bool get isEmpty => sourceIds.isEmpty && lookupKeys.isEmpty;
}

class LocalStorageDetailCacheChangeEvent {
  const LocalStorageDetailCacheChangeEvent({
    this.scope = const LocalStorageDetailCacheScope(),
    this.invalidateAll = false,
  });

  final LocalStorageDetailCacheScope scope;
  final bool invalidateAll;
}

class LocalStorageDetailCacheRevisionState {
  const LocalStorageDetailCacheRevisionState({
    this.revision = 0,
    this.globalRevision = 0,
    this.sourceRevisions = const {},
    this.lookupKeyRevisions = const {},
  });

  final int revision;
  final int globalRevision;
  final Map<String, int> sourceRevisions;
  final Map<String, int> lookupKeyRevisions;

  int revisionForScope(LocalStorageDetailCacheScope scope) {
    var resolvedRevision = globalRevision;
    for (final sourceId in scope.sourceIds) {
      final candidateRevision = sourceRevisions[sourceId.trim()];
      if (candidateRevision != null && candidateRevision > resolvedRevision) {
        resolvedRevision = candidateRevision;
      }
    }
    for (final lookupKey in scope.lookupKeys) {
      final candidateRevision = lookupKeyRevisions[lookupKey.trim()];
      if (candidateRevision != null && candidateRevision > resolvedRevision) {
        resolvedRevision = candidateRevision;
      }
    }
    return resolvedRevision;
  }

  LocalStorageDetailCacheRevisionState next(
    LocalStorageDetailCacheChangeEvent event,
  ) {
    final nextRevision = revision + 1;
    if (event.invalidateAll) {
      return LocalStorageDetailCacheRevisionState(
        revision: nextRevision,
        globalRevision: nextRevision,
      );
    }

    final normalizedSourceIds = event.scope.sourceIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    final normalizedLookupKeys = event.scope.lookupKeys
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (normalizedSourceIds.isEmpty && normalizedLookupKeys.isEmpty) {
      return this;
    }

    final nextSourceRevisions = Map<String, int>.from(sourceRevisions);
    for (final sourceId in normalizedSourceIds) {
      nextSourceRevisions[sourceId] = nextRevision;
    }
    final nextLookupKeyRevisions = Map<String, int>.from(lookupKeyRevisions);
    for (final lookupKey in normalizedLookupKeys) {
      nextLookupKeyRevisions[lookupKey] = nextRevision;
    }
    return LocalStorageDetailCacheRevisionState(
      revision: nextRevision,
      globalRevision: globalRevision,
      sourceRevisions: nextSourceRevisions,
      lookupKeyRevisions: nextLookupKeyRevisions,
    );
  }
}

final localStorageDetailCacheChangeProvider = NotifierProvider<
    LocalStorageDetailCacheRevisionController,
    LocalStorageDetailCacheRevisionState>(
  LocalStorageDetailCacheRevisionController.new,
);

final localStorageDetailCacheRevisionProvider = Provider<int>((ref) {
  return ref.watch(localStorageDetailCacheChangeProvider).revision;
});

class LocalStorageDetailCacheRevisionController
    extends Notifier<LocalStorageDetailCacheRevisionState> {
  @override
  LocalStorageDetailCacheRevisionState build() {
    return const LocalStorageDetailCacheRevisionState();
  }

  void apply(LocalStorageDetailCacheChangeEvent event) {
    state = state.next(event);
  }
}
