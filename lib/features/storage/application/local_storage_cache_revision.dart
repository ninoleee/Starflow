import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LocalStorageDetailCacheChangedField {
  artwork,
  summary,
  ratings,
  availability,
  playback,
  structure,
  choices,
  metadataStatus,
}

final Set<LocalStorageDetailCacheChangedField>
    allLocalStorageDetailCacheChangedFields =
    Set<LocalStorageDetailCacheChangedField>.unmodifiable(
  LocalStorageDetailCacheChangedField.values.toSet(),
);

class LocalStorageDetailCacheScope {
  const LocalStorageDetailCacheScope({
    this.sourceIds = const <String>{},
    this.lookupKeys = const <String>{},
    this.recordIds = const <String>{},
  });

  final Set<String> sourceIds;
  final Set<String> lookupKeys;
  final Set<String> recordIds;

  bool get isEmpty =>
      sourceIds.isEmpty && lookupKeys.isEmpty && recordIds.isEmpty;
}

class LocalStorageDetailCacheChangeEvent {
  const LocalStorageDetailCacheChangeEvent({
    this.scope = const LocalStorageDetailCacheScope(),
    this.invalidateAll = false,
    this.changedFields = const <LocalStorageDetailCacheChangedField>{},
  });

  final LocalStorageDetailCacheScope scope;
  final bool invalidateAll;
  final Set<LocalStorageDetailCacheChangedField> changedFields;

  Set<LocalStorageDetailCacheChangedField> get effectiveChangedFields =>
      changedFields.isEmpty
          ? allLocalStorageDetailCacheChangedFields
          : changedFields;
}

class LocalStorageDetailCacheRevisionState {
  const LocalStorageDetailCacheRevisionState({
    this.revision = 0,
    this.globalRevision = 0,
    this.sourceRevisions = const {},
    this.lookupKeyRevisions = const {},
    this.recordRevisions = const {},
    this.sourceFieldRevisions = const {},
    this.lookupKeyFieldRevisions = const {},
    this.recordFieldRevisions = const {},
  });

  final int revision;
  final int globalRevision;
  final Map<String, int> sourceRevisions;
  final Map<String, int> lookupKeyRevisions;
  final Map<String, int> recordRevisions;
  final Map<String, Map<LocalStorageDetailCacheChangedField, int>>
      sourceFieldRevisions;
  final Map<String, Map<LocalStorageDetailCacheChangedField, int>>
      lookupKeyFieldRevisions;
  final Map<String, Map<LocalStorageDetailCacheChangedField, int>>
      recordFieldRevisions;

  int revisionForScope(
    LocalStorageDetailCacheScope scope, {
    Set<LocalStorageDetailCacheChangedField>? changedFields,
  }) {
    var resolvedRevision = globalRevision;
    final normalizedChangedFields = changedFields
        ?.map((field) => field)
        .toSet();
    if (normalizedChangedFields == null || normalizedChangedFields.isEmpty) {
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
      for (final recordId in scope.recordIds) {
        final candidateRevision = recordRevisions[recordId.trim()];
        if (candidateRevision != null && candidateRevision > resolvedRevision) {
          resolvedRevision = candidateRevision;
        }
      }
      return resolvedRevision;
    }

    for (final sourceId in scope.sourceIds) {
      resolvedRevision = _maxFieldRevision(
        resolvedRevision,
        sourceFieldRevisions[sourceId.trim()],
        normalizedChangedFields,
      );
    }
    for (final lookupKey in scope.lookupKeys) {
      resolvedRevision = _maxFieldRevision(
        resolvedRevision,
        lookupKeyFieldRevisions[lookupKey.trim()],
        normalizedChangedFields,
      );
    }
    for (final recordId in scope.recordIds) {
      resolvedRevision = _maxFieldRevision(
        resolvedRevision,
        recordFieldRevisions[recordId.trim()],
        normalizedChangedFields,
      );
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
    final normalizedRecordIds = event.scope.recordIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (normalizedSourceIds.isEmpty &&
        normalizedLookupKeys.isEmpty &&
        normalizedRecordIds.isEmpty) {
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
    final nextRecordRevisions = Map<String, int>.from(recordRevisions);
    for (final recordId in normalizedRecordIds) {
      nextRecordRevisions[recordId] = nextRevision;
    }
    final effectiveChangedFields = event.effectiveChangedFields;
    final nextSourceFieldRevisions =
        _copyNestedFieldRevisions(sourceFieldRevisions);
    for (final sourceId in normalizedSourceIds) {
      _applyFieldRevision(
        nextSourceFieldRevisions,
        sourceId,
        nextRevision,
        effectiveChangedFields,
      );
    }
    final nextLookupKeyFieldRevisions =
        _copyNestedFieldRevisions(lookupKeyFieldRevisions);
    for (final lookupKey in normalizedLookupKeys) {
      _applyFieldRevision(
        nextLookupKeyFieldRevisions,
        lookupKey,
        nextRevision,
        effectiveChangedFields,
      );
    }
    final nextRecordFieldRevisions =
        _copyNestedFieldRevisions(recordFieldRevisions);
    for (final recordId in normalizedRecordIds) {
      _applyFieldRevision(
        nextRecordFieldRevisions,
        recordId,
        nextRevision,
        effectiveChangedFields,
      );
    }
    return LocalStorageDetailCacheRevisionState(
      revision: nextRevision,
      globalRevision: globalRevision,
      sourceRevisions: nextSourceRevisions,
      lookupKeyRevisions: nextLookupKeyRevisions,
      recordRevisions: nextRecordRevisions,
      sourceFieldRevisions: nextSourceFieldRevisions,
      lookupKeyFieldRevisions: nextLookupKeyFieldRevisions,
      recordFieldRevisions: nextRecordFieldRevisions,
    );
  }
}

int _maxFieldRevision(
  int current,
  Map<LocalStorageDetailCacheChangedField, int>? revisions,
  Set<LocalStorageDetailCacheChangedField> changedFields,
) {
  if (revisions == null || revisions.isEmpty) {
    return current;
  }
  var resolved = current;
  for (final field in changedFields) {
    final candidate = revisions[field];
    if (candidate != null && candidate > resolved) {
      resolved = candidate;
    }
  }
  return resolved;
}

Map<String, Map<LocalStorageDetailCacheChangedField, int>>
    _copyNestedFieldRevisions(
  Map<String, Map<LocalStorageDetailCacheChangedField, int>> source,
) {
  return {
    for (final entry in source.entries)
      entry.key: Map<LocalStorageDetailCacheChangedField, int>.from(
        entry.value,
      ),
  };
}

void _applyFieldRevision(
  Map<String, Map<LocalStorageDetailCacheChangedField, int>> target,
  String key,
  int revision,
  Set<LocalStorageDetailCacheChangedField> fields,
) {
  final nextFields = Map<LocalStorageDetailCacheChangedField, int>.from(
    target[key] ?? const <LocalStorageDetailCacheChangedField, int>{},
  );
  for (final field in fields) {
    nextFields[field] = revision;
  }
  target[key] = nextFields;
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
