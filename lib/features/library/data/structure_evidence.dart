enum StructureEvidence {
  unknown,
  inferred,
  filename,
  sidecar,
  manual,
  directory
}

enum StructureConfidence { unknown, inferred, explicit }

extension StructureEvidencePriority on StructureEvidence {
  // Precedence must not depend on enum declaration/serialization order.
  int get priority => switch (this) {
        StructureEvidence.unknown => 0,
        StructureEvidence.inferred => 10,
        StructureEvidence.directory => 20,
        StructureEvidence.filename => 30,
        StructureEvidence.sidecar => 40,
        StructureEvidence.manual => 50,
      };

  StructureConfidence get confidence => switch (this) {
        StructureEvidence.unknown => StructureConfidence.unknown,
        StructureEvidence.inferred => StructureConfidence.inferred,
        _ => StructureConfidence.explicit,
      };
}

enum StructureField {
  rootPath,
  rootTitle,
  itemType,
  role,
  seasonNumber,
  episodeNumber
}

/// Stable identifiers for the branches that produced a decision.
abstract final class StructureRule {
  static const unknown = 'unknown';
  static const legacy = 'legacy.evidence';
  static const ownedDirectory = 'root.first-media-directory';
  static const scopedDirectory = 'root.scoped-media-directory';
  static const looseFile = 'root.loose-file';
  static const filenameNumber = 'number.filename';
  static const directoryNumber = 'number.directory';
  static const seedNumber = 'number.seed';
  static const sidecarNumber = 'number.sidecar';
  static const titleSuffixNumber = 'episode.title-suffix';
  static const groupedLeadingNumber = 'episode.grouped-leading-number';
  static const orderedEpisode = 'episode.unnumbered-order';
  static const siblingSeason = 'season.sibling-directory';
  static const defaultSeason = 'season.default';
  static const specialKeyword = 'role.special-keyword';
  static const rootSpecial = 'season.root-special';
  static const collapsedSeason = 'season.collapsed-wrapper';
  static const sidecarType = 'type.sidecar';
  static const seedType = 'type.seed';
  static const numberedType = 'type.numbered-resource';
  static const seriesStructure = 'type.series-structure';
  static const movieVersions = 'type.movie-versions';
  static const singleFile = 'type.single-file';
  static const extraKeyword = 'role.extra-keyword';
  static const inheritedType = 'type.owner';
  static const resolvedType = 'role.resolved-type';
}

class StructureFieldEvidence {
  const StructureFieldEvidence(this.source, this.ruleId);

  static const unknown = StructureFieldEvidence(
    StructureEvidence.unknown,
    StructureRule.unknown,
  );
  final StructureEvidence source;
  final String ruleId;
  StructureConfidence get confidence => source.confidence;

  Map<String, dynamic> toJson() => {'source': source.name, 'ruleId': ruleId};

  static StructureFieldEvidence fromJson(Object? value) {
    if (value is! Map) return unknown;
    return StructureFieldEvidence(parseStructureEvidence(value['source']),
        value['ruleId'] as String? ?? StructureRule.unknown);
  }

  @override
  bool operator ==(Object other) =>
      other is StructureFieldEvidence &&
      source == other.source &&
      ruleId == other.ruleId;
  @override
  int get hashCode => Object.hash(source, ruleId);
}

/// Conflicts record past decisions; they do not change directory ownership.
class StructureConflict {
  const StructureConflict(
      {required this.field,
      required this.selectedValue,
      required this.rejectedValue,
      required this.selectedEvidence,
      required this.rejectedEvidence});

  final StructureField field;
  final String selectedValue;
  final String rejectedValue;
  final StructureFieldEvidence selectedEvidence;
  final StructureFieldEvidence rejectedEvidence;

  Map<String, dynamic> toJson() => {
        'field': field.name,
        'selectedValue': selectedValue,
        'rejectedValue': rejectedValue,
        'selectedEvidence': selectedEvidence.toJson(),
        'rejectedEvidence': rejectedEvidence.toJson(),
      };

  static StructureConflict? fromJson(Object? value) {
    if (value is! Map) return null;
    final field = parseStructureField(value['field']);
    if (field == null) return null;
    return StructureConflict(
        field: field,
        selectedValue: value['selectedValue'] as String? ?? '',
        rejectedValue: value['rejectedValue'] as String? ?? '',
        selectedEvidence:
            StructureFieldEvidence.fromJson(value['selectedEvidence']),
        rejectedEvidence:
            StructureFieldEvidence.fromJson(value['rejectedEvidence']));
  }

  @override
  bool operator ==(Object other) =>
      other is StructureConflict &&
      field == other.field &&
      selectedValue == other.selectedValue &&
      rejectedValue == other.rejectedValue &&
      selectedEvidence == other.selectedEvidence &&
      rejectedEvidence == other.rejectedEvidence;
  @override
  int get hashCode => Object.hash(
      field, selectedValue, rejectedValue, selectedEvidence, rejectedEvidence);
}

StructureEvidence parseStructureEvidence(Object? value) =>
    StructureEvidence.values.firstWhere((entry) => entry.name == value,
        orElse: () => StructureEvidence.unknown);

StructureField? parseStructureField(Object? value) {
  for (final field in StructureField.values) {
    if (field.name == value) return field;
  }
  return null;
}
