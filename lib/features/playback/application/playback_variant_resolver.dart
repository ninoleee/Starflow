import 'package:riverpod/misc.dart';
import 'package:starflow/core/storage/resource_path_identity.dart';
import 'package:starflow/features/library/data/media_server_client.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

bool supportsPlaybackVariants(PlaybackTarget target) =>
    target.sourceId.isNotEmpty &&
    target.itemId.isNotEmpty &&
    (target.isMovie || target.isEpisode) &&
    (target.sourceKind.isMediaServer ||
        target.sourceKind == MediaSourceKind.nas ||
        target.sourceKind == MediaSourceKind.quark);

bool isSamePlaybackVariant(PlaybackTarget left, PlaybackTarget right) {
  if (identical(left, right)) return true;
  if (left.sourceId != right.sourceId) return false;
  if (!left.sourceKind.isMediaServer &&
      left.itemId.isNotEmpty &&
      right.itemId.isNotEmpty) {
    return left.itemId == right.itemId;
  }
  if (left.preferredMediaSourceId.isNotEmpty &&
      right.preferredMediaSourceId.isNotEmpty) {
    return left.itemId == right.itemId &&
        left.preferredMediaSourceId == right.preferredMediaSourceId;
  }
  if (left.actualAddress.isNotEmpty && right.actualAddress.isNotEmpty) {
    return resourcePathKey(left.actualAddress) ==
        resourcePathKey(right.actualAddress);
  }
  return left.itemId.isNotEmpty && left.itemId == right.itemId;
}

String playbackVariantLabel(PlaybackTarget target) {
  final address = target.actualAddress.trim();
  final uri = Uri.tryParse(address);
  final segments = uri?.pathSegments ?? const <String>[];
  final filename = segments.where((part) => part.isNotEmpty).lastOrNull ?? '';
  return filename.isNotEmpty
      ? filename
      : target.preferredMediaSourceId.isNotEmpty
          ? '${target.title} · ${target.preferredMediaSourceId}'
          : target.title;
}

class PlaybackVariantResolver {
  const PlaybackVariantResolver({required this.read});

  final T Function<T>(ProviderListenable<T> provider) read;

  Future<List<PlaybackTarget>> load(PlaybackTarget target) async {
    if (!supportsPlaybackVariants(target)) return [target];
    final source = read(appSettingsProvider)
        .mediaSources
        .where((source) =>
            source.enabled &&
            source.id == target.sourceId &&
            source.kind == target.sourceKind)
        .firstOrNull;
    if (source == null) throw StateError('媒体源不可用');
    final List<PlaybackTarget> variants;
    if (source.kind.isMediaServer) {
      variants = await read(mediaServerClientProvider(source.kind))
          .fetchPlaybackVariants(source: source, target: target);
    } else {
      final indexer = read(nasMediaIndexerProvider);
      final items = target.isMovie
          ? await indexer.loadMovieVariants(source, itemId: target.itemId)
          : await indexer.loadEpisodeVariants(source, itemId: target.itemId);
      variants = items.map((item) {
        final playback = PlaybackTarget.fromMediaItem(item);
        // Indexed files may only have a resource ID, not a server playback ID.
        // Keep the selected file addressable for the next version lookup.
        return playback.copyWith(
          itemId: playback.itemId.trim().isNotEmpty ? playback.itemId : item.id,
          itemType: playback.itemType.trim().isNotEmpty
              ? playback.itemType
              : target.itemType,
          seasonNumber: playback.seasonNumber ?? target.seasonNumber,
          episodeNumber: playback.episodeNumber ?? target.episodeNumber,
        );
      }).toList();
    }
    final result = <PlaybackTarget>[];
    for (final variant in variants) {
      if (!variant.canPlay || variant.sourceId != target.sourceId) continue;
      if (result.any((entry) => isSamePlaybackVariant(entry, variant))) {
        continue;
      }
      // File versions must not inherit the previous file's track GUIDs or
      // transcoding session. Resolve only the chosen file when switching.
      final clean = variant.sourceKind == MediaSourceKind.fntv
          ? PlaybackTarget.fromJson({
              ...variant.toJson(),
              'audioStreams': <Object>[],
              'subtitleStreams': <Object>[],
              'playbackQualities': <Object>[],
              'preferredAudioStreamId': '',
              'preferredSubtitleStreamId': '',
              'videoStreamId': '',
              'preferredPlaybackQualityIndex': 0,
              'fntvSessionLink': '',
              'fntvStartPositionMs': 0,
              'fntvTrackSelectionExplicit': false,
            })
          : variant;
      result.add(clean.copyWith(
        seriesId: target.seriesId,
        seriesTitle: target.seriesTitle,
        allowResume: target.allowResume,
      ));
    }
    if (!result.any((entry) => isSamePlaybackVariant(entry, target))) {
      result.insert(0, target);
    }
    return result;
  }
}
