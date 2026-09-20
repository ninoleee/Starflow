import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/details/application/detail_enrichment_settings.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  test('NAS IMDb preference does not invalidate detail enrichment settings',
      () async {
    final source = StateProvider((ref) => AppSettings.fromJson(const {}));
    final container = ProviderContainer(overrides: [
      appSettingsProvider.overrideWith((ref) => ref.watch(source)),
    ]);
    addTearDown(container.dispose);
    final subscription =
        container.listen(detailEnrichmentSettingsProvider, (previous, next) {});
    addTearDown(subscription.close);
    final initial = subscription.read();
    container.read(source.notifier).state = container.read(source).copyWith(
          imdbRatingMatchEnabled: true,
        );
    await container.pump();
    expect(identical(subscription.read(), initial), isTrue);
    container.read(source.notifier).state = container.read(source).copyWith(
          tmdbReadAccessToken: 'changed',
        );
    await container.pump();
    expect(subscription.read().tmdbReadAccessToken, 'changed');
  });
}
