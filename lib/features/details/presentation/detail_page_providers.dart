import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/details/application/detail_enrichment_settings.dart';
import 'package:starflow/features/details/application/detail_target_resolver.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';

final enrichedDetailTargetProvider =
    FutureProvider.autoDispose.family<MediaDetailTarget, MediaDetailTarget>(
  (ref, target) async {
    ref.watch(detailEnrichmentSettingsProvider);
    return ref.read(detailTargetResolverProvider).resolve(
          target: target,
          backgroundWorkSuspended: false,
        );
  },
);
