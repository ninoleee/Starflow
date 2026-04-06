enum LocalStorageCacheType {
  nasMetadataIndex,
  detailData,
  playbackMemory,
  televisionSearchPreferences,
  images,
}

extension LocalStorageCacheTypeX on LocalStorageCacheType {
  String get label {
    switch (this) {
      case LocalStorageCacheType.nasMetadataIndex:
        return 'WebDAV 元数据索引';
      case LocalStorageCacheType.detailData:
        return '资源关联与刮削信息';
      case LocalStorageCacheType.playbackMemory:
        return '播放记录与续播';
      case LocalStorageCacheType.televisionSearchPreferences:
        return 'TV 搜索历史与来源记忆';
      case LocalStorageCacheType.images:
        return '图片';
    }
  }

  String get description {
    switch (this) {
      case LocalStorageCacheType.nasMetadataIndex:
        return '本地 WebDAV 媒体索引与扫描状态';
      case LocalStorageCacheType.detailData:
        return '详情页资源命中、刮削结果与手动修正缓存';
      case LocalStorageCacheType.playbackMemory:
        return '播放历史、续播进度与按剧跳过规则';
      case LocalStorageCacheType.televisionSearchPreferences:
        return 'TV 端最近搜索词和搜索来源选择记忆';
      case LocalStorageCacheType.images:
        return '详情页、豆瓣等图片的本地复用缓存';
    }
  }
}

class LocalStorageCacheSummary {
  const LocalStorageCacheSummary({
    required this.type,
    required this.entryCount,
    required this.totalBytes,
  });

  final LocalStorageCacheType type;
  final int entryCount;
  final int totalBytes;
}
