import 'package:starflow/core/utils/media_rating_labels.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/data/douban_api_client.dart';

Future<MediaDetailTarget> enrichDetailTargetWithDoubanRatingStats({
  required MediaDetailTarget target,
  required DoubanApiClient doubanApiClient,
  String cookie = '',
  bool propagateErrors = false,
}) async {
  final doubanId = target.doubanId.trim();
  if (doubanId.isEmpty) {
    return target;
  }
  try {
    final stats = await doubanApiClient.fetchSubjectRatingStats(
      doubanId: doubanId,
      cookie: cookie,
    );
    if (stats == null) {
      return target;
    }
    final ratingLabel =
        stats.hasRating ? '豆瓣 ${stats.value.toStringAsFixed(1)}' : '';
    return target.copyWith(
      ratingLabels: ratingLabel.isEmpty
          ? target.ratingLabels
          : _replaceDoubanRatingLabel(target.ratingLabels, ratingLabel),
      ratingCount:
          stats.ratingCount > 0 ? stats.ratingCount : target.ratingCount,
    );
  } catch (_) {
    if (propagateErrors) rethrow;
    return target;
  }
}

List<String> _replaceDoubanRatingLabel(
  Iterable<String> labels,
  String ratingLabel,
) {
  return <String>[
    ratingLabel,
    ...labels.where(
      (label) => resolveMediaRatingSource(label) != MediaRatingSource.douban,
    ),
  ];
}
