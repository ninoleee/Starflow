enum LocalStorageCacheType {
  detailData,
  images,
}

extension LocalStorageCacheTypeX on LocalStorageCacheType {
  String get label {
    switch (this) {
      case LocalStorageCacheType.detailData:
        return '资源关联与刮削信息';
      case LocalStorageCacheType.images:
        return '图片';
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
