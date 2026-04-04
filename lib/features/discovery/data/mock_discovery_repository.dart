import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

abstract class DiscoveryRepository {
  Future<List<DoubanEntry>> fetchRecommendations();

  Future<List<DoubanEntry>> fetchWishList();
}

final discoveryRepositoryProvider = Provider<DiscoveryRepository>(
  (ref) => MockDiscoveryRepository(ref),
);

class MockDiscoveryRepository implements DiscoveryRepository {
  MockDiscoveryRepository(this.ref);

  final Ref ref;

  bool get _doubanEnabled => ref.read(appSettingsProvider).doubanAccount.enabled;

  @override
  Future<List<DoubanEntry>> fetchRecommendations() async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!_doubanEnabled) {
      return const [];
    }
    return SeedData.seedDoubanRecommendations;
  }

  @override
  Future<List<DoubanEntry>> fetchWishList() async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!_doubanEnabled) {
      return const [];
    }
    return SeedData.seedDoubanWishList;
  }
}
