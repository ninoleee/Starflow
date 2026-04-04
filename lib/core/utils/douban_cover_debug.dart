import 'package:flutter/foundation.dart';

final Set<String> _doubanCoverDebugKeys = <String>{};
String? _trackedDoubanCoverId;
String? _trackedDoubanCoverTitle;
String? _trackedDoubanCoverUrl;

bool isDoubanImageUrl(String url) {
  final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
  if (host.isEmpty) {
    return false;
  }
  return host == 'img.douban.com' || host.endsWith('.doubanio.com');
}

void debugLogDoubanCover(
  String stage, {
  String? moduleTitle,
  String? title,
  String? doubanId,
  String? url,
  String? detail,
  bool dedupe = true,
}) {
  if (kReleaseMode) {
    return;
  }

  final normalizedModuleTitle = moduleTitle?.trim() ?? '';
  final normalizedTitle = title?.trim() ?? '';
  final normalizedId = doubanId?.trim() ?? '';
  final normalizedUrl = url?.trim() ?? '';
  final normalizedDetail = detail?.trim() ?? '';
  if (!_shouldTrackCurrentEntry(
    title: normalizedTitle,
    doubanId: normalizedId,
    url: normalizedUrl,
  )) {
    return;
  }
  final message = <String>[
    '[DoubanCover][$stage]',
    if (normalizedModuleTitle.isNotEmpty) 'module=$normalizedModuleTitle',
    if (normalizedTitle.isNotEmpty) 'title=$normalizedTitle',
    if (normalizedId.isNotEmpty) 'id=$normalizedId',
    if (normalizedUrl.isNotEmpty) 'url=$normalizedUrl',
    if (normalizedDetail.isNotEmpty) 'detail=$normalizedDetail',
  ].join(' ');

  final key = [
    stage,
    normalizedModuleTitle,
    normalizedTitle,
    normalizedId,
    normalizedUrl,
    normalizedDetail,
  ].join('|');

  if (!dedupe || _doubanCoverDebugKeys.add(key)) {
    debugPrint(message);
  }
}

bool _shouldTrackCurrentEntry({
  required String title,
  required String doubanId,
  required String url,
}) {
  if ((_trackedDoubanCoverId ?? '').isEmpty &&
      (_trackedDoubanCoverTitle ?? '').isEmpty &&
      (_trackedDoubanCoverUrl ?? '').isEmpty) {
    _trackedDoubanCoverId = doubanId;
    _trackedDoubanCoverTitle = title;
    _trackedDoubanCoverUrl = url;
    return true;
  }

  final trackedId = _trackedDoubanCoverId ?? '';
  final trackedTitle = _trackedDoubanCoverTitle ?? '';
  final trackedUrl = _trackedDoubanCoverUrl ?? '';

  if (trackedId.isNotEmpty && doubanId.isNotEmpty) {
    return trackedId == doubanId;
  }
  if (trackedUrl.isNotEmpty && url.isNotEmpty) {
    return trackedUrl == url;
  }
  if (trackedTitle.isNotEmpty && title.isNotEmpty) {
    return trackedTitle == title;
  }
  return false;
}
