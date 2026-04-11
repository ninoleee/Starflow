import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

class DetailEnrichmentSettings {
  const DetailEnrichmentSettings({
    required this.mediaSources,
    required this.quarkCookie,
    required this.wmdbMetadataMatchEnabled,
    required this.tmdbMetadataMatchEnabled,
    required this.tmdbReadAccessToken,
    required this.imdbRatingMatchEnabled,
  });

  final List<MediaSourceConfig> mediaSources;
  final String quarkCookie;
  final bool wmdbMetadataMatchEnabled;
  final bool tmdbMetadataMatchEnabled;
  final String tmdbReadAccessToken;
  final bool imdbRatingMatchEnabled;
}

final detailEnrichmentSettingsProvider =
    Provider<DetailEnrichmentSettings>((ref) {
  return DetailEnrichmentSettings(
    mediaSources: ref.watch(
      appSettingsProvider.select((settings) => settings.mediaSources),
    ),
    quarkCookie: ref.watch(
      appSettingsProvider
          .select((settings) => settings.networkStorage.quarkCookie),
    ),
    wmdbMetadataMatchEnabled: ref.watch(
      appSettingsProvider.select(
        (settings) => settings.wmdbMetadataMatchEnabled,
      ),
    ),
    tmdbMetadataMatchEnabled: ref.watch(
      appSettingsProvider.select(
        (settings) => settings.tmdbMetadataMatchEnabled,
      ),
    ),
    tmdbReadAccessToken: ref.watch(
      appSettingsProvider.select((settings) => settings.tmdbReadAccessToken),
    ),
    imdbRatingMatchEnabled: ref.watch(
      appSettingsProvider.select((settings) => settings.imdbRatingMatchEnabled),
    ),
  );
});
