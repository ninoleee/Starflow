enum LocalStorageCacheType {
  nasMetadataIndex,
  embyLibraryCache,
  detailData,
  subtitleCache,
  playbackMemory,
  televisionSearchPreferences,
  images,
}

extension LocalStorageCacheTypeX on LocalStorageCacheType {
  String get label {
    switch (this) {
      case LocalStorageCacheType.nasMetadataIndex:
        return '媒体库索引';
      case LocalStorageCacheType.embyLibraryCache:
        return 'Emby 媒体库缓存';
      case LocalStorageCacheType.detailData:
        return '详情匹配与刮削缓存';
      case LocalStorageCacheType.subtitleCache:
        return '字幕缓存';
      case LocalStorageCacheType.playbackMemory:
        return '播放记录与续播';
      case LocalStorageCacheType.televisionSearchPreferences:
        return '搜索历史与来源记忆';
      case LocalStorageCacheType.images:
        return '图片缓存';
    }
  }

  String get description {
    switch (this) {
      case LocalStorageCacheType.nasMetadataIndex:
        return '本地 WebDAV 索引、分区结果和扫描状态';
      case LocalStorageCacheType.embyLibraryCache:
        return 'Emby 已加载分区、列表条目和首页回退数据快照';
      case LocalStorageCacheType.detailData:
        return '详情页资源命中、刮削结果、字幕选择和手动修正';
      case LocalStorageCacheType.subtitleCache:
        return '在线字幕下载、解压结果和预验证缓存';
      case LocalStorageCacheType.playbackMemory:
        return '播放历史、续播进度与按剧跳过规则';
      case LocalStorageCacheType.televisionSearchPreferences:
        return '最近搜索词和搜索来源选择记忆，当前主要用于 TV';
      case LocalStorageCacheType.images:
        return '详情页、首页、豆瓣等图片的本地缓存';
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
