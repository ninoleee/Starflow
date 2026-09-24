import 'structure_evidence.dart';

export 'structure_evidence.dart';

enum ExternalResourceRole { video, episode, special, extra, audio, unknown }

/// Directory ownership is independent of provider metadata and browse views.
class ExternalMediaStructure {
  const ExternalMediaStructure({
    required this.rootPath,
    required this.rootTitle,
    required this.itemType,
    this.role = ExternalResourceRole.video,
    this.seasonNumber,
    this.episodeNumber,
    StructureEvidence seasonEvidence = StructureEvidence.unknown,
    StructureEvidence episodeEvidence = StructureEvidence.unknown,
    this.fieldEvidence = const {},
    this.conflicts = const [],
  })  : _seasonEvidence = seasonEvidence,
        _episodeEvidence = episodeEvidence;

  final String rootPath;
  final String rootTitle;
  final String itemType;
  final ExternalResourceRole role;
  final int? seasonNumber;
  final int? episodeNumber;
  final StructureEvidence _seasonEvidence;
  final StructureEvidence _episodeEvidence;
  StructureEvidence get seasonEvidence =>
      evidenceFor(StructureField.seasonNumber).source;
  StructureEvidence get episodeEvidence =>
      evidenceFor(StructureField.episodeNumber).source;
  final Map<StructureField, StructureFieldEvidence> fieldEvidence;
  final List<StructureConflict> conflicts;

  StructureFieldEvidence evidenceFor(StructureField field) {
    final value = fieldEvidence[field];
    if (value != null) return value;
    final legacy = switch (field) {
      StructureField.seasonNumber => _seasonEvidence,
      StructureField.episodeNumber => _episodeEvidence,
      _ => StructureEvidence.unknown,
    };
    return legacy == StructureEvidence.unknown
        ? StructureFieldEvidence.unknown
        : StructureFieldEvidence(legacy, StructureRule.legacy);
  }

  @override
  bool operator ==(Object other) =>
      other is ExternalMediaStructure &&
      rootPath == other.rootPath &&
      rootTitle == other.rootTitle &&
      itemType == other.itemType &&
      role == other.role &&
      seasonNumber == other.seasonNumber &&
      episodeNumber == other.episodeNumber &&
      seasonEvidence == other.seasonEvidence &&
      episodeEvidence == other.episodeEvidence &&
      StructureField.values
          .every((field) => evidenceFor(field) == other.evidenceFor(field)) &&
      conflicts.length == other.conflicts.length &&
      conflicts
          .asMap()
          .entries
          .every((entry) => entry.value == other.conflicts[entry.key]);

  @override
  int get hashCode => Object.hash(
      rootPath,
      rootTitle,
      itemType,
      role,
      seasonNumber,
      episodeNumber,
      seasonEvidence,
      episodeEvidence,
      Object.hashAll(StructureField.values.map(evidenceFor)),
      Object.hashAll(conflicts));

  ExternalMediaStructure withSidecarNumbers({int? season, int? episode}) {
    const sidecar = StructureFieldEvidence(
        StructureEvidence.sidecar, StructureRule.sidecarNumber);
    final next = ExternalMediaStructure(
      rootPath: rootPath,
      rootTitle: rootTitle,
      itemType: episode != null ? 'episode' : itemType,
      role: episode != null && role != ExternalResourceRole.extra
          ? (season ?? seasonNumber) == 0
              ? ExternalResourceRole.special
              : ExternalResourceRole.episode
          : role,
      seasonNumber: season ?? seasonNumber,
      episodeNumber: episode ?? episodeNumber,
      seasonEvidence:
          season != null ? StructureEvidence.sidecar : seasonEvidence,
      episodeEvidence:
          episode != null ? StructureEvidence.sidecar : episodeEvidence,
      fieldEvidence: Map.unmodifiable({
        ...fieldEvidence,
        if (season != null) StructureField.seasonNumber: sidecar,
        if (episode != null) StructureField.episodeNumber: sidecar,
        if (episode != null)
          StructureField.itemType: const StructureFieldEvidence(
              StructureEvidence.sidecar, StructureRule.sidecarType),
        if (episode != null && role != ExternalResourceRole.extra)
          StructureField.role: sidecar,
      }),
      conflicts: conflicts,
    );
    final merged = next.preservingStrongerNumbers(this);
    return merged.withConflicts([
      if (merged.itemType != itemType && itemType.isNotEmpty)
        StructureConflict(
            field: StructureField.itemType,
            selectedValue: merged.itemType,
            rejectedValue: itemType,
            selectedEvidence: merged.evidenceFor(StructureField.itemType),
            rejectedEvidence: evidenceFor(StructureField.itemType)),
      if (merged.role != role)
        StructureConflict(
            field: StructureField.role,
            selectedValue: merged.role.name,
            rejectedValue: role.name,
            selectedEvidence: merged.evidenceFor(StructureField.role),
            rejectedEvidence: evidenceFor(StructureField.role)),
    ]);
  }

  ExternalMediaStructure preservingStrongerNumbers(
      ExternalMediaStructure? old) {
    final season = old != null &&
            old.seasonNumber != null &&
            old.seasonEvidence.priority > seasonEvidence.priority
        ? old
        : this;
    final episode = old != null &&
            old.episodeNumber != null &&
            old.episodeEvidence.priority > episodeEvidence.priority
        ? old
        : this;
    final keepEpisodeType = episode.episodeEvidence.priority >=
            StructureEvidence.sidecar.priority &&
        episode.episodeNumber != null &&
        episode.itemType == 'episode';
    return ExternalMediaStructure(
      rootPath: rootPath,
      rootTitle: rootTitle,
      itemType: keepEpisodeType ? 'episode' : itemType,
      role: keepEpisodeType && role != ExternalResourceRole.extra
          ? season.seasonNumber == 0
              ? ExternalResourceRole.special
              : ExternalResourceRole.episode
          : role,
      seasonNumber: season.seasonNumber,
      episodeNumber: episode.episodeNumber,
      seasonEvidence: season.seasonEvidence,
      episodeEvidence: episode.episodeEvidence,
      fieldEvidence: Map.unmodifiable({
        ...fieldEvidence,
        StructureField.seasonNumber:
            season.evidenceFor(StructureField.seasonNumber),
        StructureField.episodeNumber:
            episode.evidenceFor(StructureField.episodeNumber),
        if (keepEpisodeType)
          StructureField.itemType: episode.evidenceFor(StructureField.itemType),
        if (keepEpisodeType && role != ExternalResourceRole.extra)
          StructureField.role:
              episode.evidenceFor(StructureField.episodeNumber),
      }),
      conflicts: boundedConflicts([
        ...?old?.conflicts,
        ...conflicts,
        if (old != null &&
            seasonNumber != null &&
            old.seasonNumber != null &&
            seasonNumber != old.seasonNumber)
          StructureConflict(
              field: StructureField.seasonNumber,
              selectedValue: '${season.seasonNumber}',
              rejectedValue:
                  '${identical(season, this) ? old.seasonNumber : seasonNumber}',
              selectedEvidence: season.evidenceFor(StructureField.seasonNumber),
              rejectedEvidence: (identical(season, this) ? old : this)
                  .evidenceFor(StructureField.seasonNumber)),
        if (old != null &&
            episodeNumber != null &&
            old.episodeNumber != null &&
            episodeNumber != old.episodeNumber)
          StructureConflict(
              field: StructureField.episodeNumber,
              selectedValue: '${episode.episodeNumber}',
              rejectedValue:
                  '${identical(episode, this) ? old.episodeNumber : episodeNumber}',
              selectedEvidence:
                  episode.evidenceFor(StructureField.episodeNumber),
              rejectedEvidence: (identical(episode, this) ? old : this)
                  .evidenceFor(StructureField.episodeNumber)),
      ]),
    );
  }

  ExternalMediaStructure withConflicts(
          Iterable<StructureConflict> observations) =>
      ExternalMediaStructure(
          rootPath: rootPath,
          rootTitle: rootTitle,
          itemType: itemType,
          role: role,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
          seasonEvidence: seasonEvidence,
          episodeEvidence: episodeEvidence,
          fieldEvidence: fieldEvidence,
          conflicts: boundedConflicts([...conflicts, ...observations]));

  // Bound repeated incremental observations without storing raw paths or NFO.
  static List<StructureConflict> boundedConflicts(
      Iterable<StructureConflict> values) {
    final distinct = values.toSet().toList();
    return List.unmodifiable(
        distinct.skip(distinct.length > 32 ? distinct.length - 32 : 0));
  }

  Map<String, dynamic> toJson() => {
        'rootPath': rootPath,
        'rootTitle': rootTitle,
        'itemType': itemType,
        'role': role.name,
        'seasonNumber': seasonNumber,
        'episodeNumber': episodeNumber,
        'seasonEvidence': seasonEvidence.name,
        'episodeEvidence': episodeEvidence.name,
        'fieldEvidence': {
          for (final field in StructureField.values)
            field.name: evidenceFor(field).toJson(),
        },
        'conflicts': conflicts.map((value) => value.toJson()).toList(),
      };

  factory ExternalMediaStructure.fromJson(Map<String, dynamic> json) {
    final evidence = <StructureField, StructureFieldEvidence>{};
    final rawEvidence = json['fieldEvidence'];
    if (rawEvidence is Map) {
      for (final entry in rawEvidence.entries) {
        final field = parseStructureField(entry.key);
        if (field != null) {
          evidence[field] = StructureFieldEvidence.fromJson(entry.value);
        }
      }
    }
    final rawConflicts = json['conflicts'];
    return ExternalMediaStructure(
      rootPath: json['rootPath'] as String? ?? '',
      rootTitle: json['rootTitle'] as String? ?? '',
      itemType: json['itemType'] as String? ?? '',
      role: ExternalResourceRole.values.firstWhere(
        (value) => value.name == json['role'],
        orElse: () => ExternalResourceRole.unknown,
      ),
      seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
      episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
      seasonEvidence: StructureEvidence.values.firstWhere(
        (value) => value.name == json['seasonEvidence'],
        orElse: () => StructureEvidence.unknown,
      ),
      episodeEvidence: StructureEvidence.values.firstWhere(
        (value) => value.name == json['episodeEvidence'],
        orElse: () => StructureEvidence.unknown,
      ),
      fieldEvidence: Map.unmodifiable(evidence),
      conflicts: boundedConflicts(rawConflicts is List
          ? rawConflicts
              .map(StructureConflict.fromJson)
              .whereType<StructureConflict>()
          : const <StructureConflict>[]),
    );
  }

  static bool isKnownAudio(String name) => RegExp(
        r'\.[(（]?(?:mp3|flac|m4a|aac|wav|ogg|opus|wma|ape|aiff|alac)[)）]?(?:\.strm)?$',
        caseSensitive: false,
      ).hasMatch(name.trim());
}
