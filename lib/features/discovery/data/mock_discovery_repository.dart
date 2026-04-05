import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/discovery/data/douban_api_client.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

abstract class DiscoveryRepository {
  Future<List<DoubanEntry>> fetchEntries(
    HomeModuleConfig module, {
    int page = 1,
    int? pageSize,
  });

  Future<List<DoubanCarouselEntry>> fetchCarouselItems();
}

final discoveryRepositoryProvider = Provider<DiscoveryRepository>(
  (ref) => AppDiscoveryRepository(
    ref,
    ref.read(doubanApiClientProvider),
  ),
);

class AppDiscoveryRepository implements DiscoveryRepository {
  AppDiscoveryRepository(this.ref, this._apiClient);

  final Ref ref;
  final DoubanApiClient _apiClient;

  DoubanAccountConfig get _config =>
      ref.read(appSettingsProvider).doubanAccount;

  @override
  Future<List<DoubanEntry>> fetchEntries(
    HomeModuleConfig module, {
    int page = 1,
    int? pageSize,
  }) async {
    if (!_config.enabled) {
      return const [];
    }

    switch (module.type) {
      case HomeModuleType.doubanInterest:
        return _apiClient.fetchInterestItems(
          userId: _config.userId,
          status: module.doubanInterestStatus,
          page: page,
          pageSize: pageSize,
        );
      case HomeModuleType.doubanSuggestion:
        return _apiClient.fetchSuggestionItems(
          cookie: _config.sessionCookie,
          mediaType: module.doubanSuggestionType,
          page: page,
          pageSize: pageSize,
        );
      case HomeModuleType.doubanList:
        return _apiClient.fetchListItems(
          url: module.doubanListUrl,
          page: page,
          pageSize: pageSize,
        );
      case HomeModuleType.recentlyAdded:
      case HomeModuleType.hero:
      case HomeModuleType.librarySection:
      case HomeModuleType.doubanCarousel:
        return const [];
    }
  }

  @override
  Future<List<DoubanCarouselEntry>> fetchCarouselItems() async {
    if (!_config.enabled) {
      return const [];
    }
    return _apiClient.fetchCarouselItems();
  }
}
