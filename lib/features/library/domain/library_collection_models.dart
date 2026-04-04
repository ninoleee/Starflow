import 'package:starflow/features/library/domain/media_models.dart';

class LibraryCollectionTarget {
  const LibraryCollectionTarget({
    required this.title,
    required this.sourceId,
    required this.sourceName,
    required this.sourceKind,
    this.sectionId = '',
    this.subtitle = '',
  });

  final String title;
  final String sourceId;
  final String sourceName;
  final MediaSourceKind sourceKind;
  final String sectionId;
  final String subtitle;

  @override
  bool operator ==(Object other) {
    return other is LibraryCollectionTarget &&
        other.title == title &&
        other.sourceId == sourceId &&
        other.sourceName == sourceName &&
        other.sourceKind == sourceKind &&
        other.sectionId == sectionId &&
        other.subtitle == subtitle;
  }

  @override
  int get hashCode => Object.hash(
        title,
        sourceId,
        sourceName,
        sourceKind,
        sectionId,
        subtitle,
      );
}
