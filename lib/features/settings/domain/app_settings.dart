import 'package:starflow/core/logging/app_log_api.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';

enum HomeModuleType {
  hero,
  recentlyAdded,
  recentPlayback,
  librarySection,
  doubanInterest,
  doubanSuggestion,
  doubanList,
  doubanCarousel,
}

extension HomeModuleTypeX on HomeModuleType {
  String get label {
    switch (this) {
      case HomeModuleType.hero:
        return 'Hero';
      case HomeModuleType.recentlyAdded:
        return '最近新增';
      case HomeModuleType.recentPlayback:
        return '最近播放';
      case HomeModuleType.librarySection:
        return '来源分区';
      case HomeModuleType.doubanInterest:
        return '豆瓣我看';
      case HomeModuleType.doubanSuggestion:
        return '豆瓣个性化推荐';
      case HomeModuleType.doubanList:
        return '豆瓣片单';
      case HomeModuleType.doubanCarousel:
        return '豆瓣首页轮播';
    }
  }

  static HomeModuleType fromName(String raw) {
    return switch (raw) {
      'hero' => HomeModuleType.hero,
      'recentlyAdded' => HomeModuleType.recentlyAdded,
      'recentPlayback' => HomeModuleType.recentPlayback,
      'librarySection' => HomeModuleType.librarySection,
      'doubanInterest' => HomeModuleType.doubanInterest,
      'doubanSuggestion' => HomeModuleType.doubanSuggestion,
      'doubanList' => HomeModuleType.doubanList,
      'doubanCarousel' => HomeModuleType.doubanCarousel,
      _ => HomeModuleType.recentlyAdded,
    };
  }
}

enum HomeHeroDisplayMode { normal, borderless }

extension HomeHeroDisplayModeX on HomeHeroDisplayMode {
  String get label {
    switch (this) {
      case HomeHeroDisplayMode.normal:
        return 'normal';
      case HomeHeroDisplayMode.borderless:
        return 'borderless';
    }
  }

  static HomeHeroDisplayMode fromName(String raw) {
    return switch (raw) {
      'borderless' => HomeHeroDisplayMode.borderless,
      'normal' => HomeHeroDisplayMode.normal,
      _ => HomeHeroDisplayMode.normal,
    };
  }
}

enum HomeHeroStyle { composite, poster }

extension HomeHeroStyleX on HomeHeroStyle {
  String get label {
    switch (this) {
      case HomeHeroStyle.composite:
        return '复合';
      case HomeHeroStyle.poster:
        return '海报';
    }
  }

  static HomeHeroStyle fromName(String raw) {
    return switch (raw) {
      'composite' => HomeHeroStyle.composite,
      'poster' => HomeHeroStyle.poster,
      _ => HomeHeroStyle.composite,
    };
  }
}

enum PlaybackSubtitlePreference { auto, off }

extension PlaybackSubtitlePreferenceX on PlaybackSubtitlePreference {
  String get label {
    switch (this) {
      case PlaybackSubtitlePreference.auto:
        return '默认开启';
      case PlaybackSubtitlePreference.off:
        return '默认关闭';
    }
  }

  String get description {
    switch (this) {
      case PlaybackSubtitlePreference.auto:
        return '打开视频时按“默认字幕”自动选择字幕轨';
      case PlaybackSubtitlePreference.off:
        return '打开视频时默认不显示字幕';
    }
  }

  static PlaybackSubtitlePreference fromName(String raw) {
    return switch (raw) {
      'off' => PlaybackSubtitlePreference.off,
      'auto' => PlaybackSubtitlePreference.auto,
      _ => PlaybackSubtitlePreference.auto,
    };
  }
}

enum PlaybackDefaultSubtitle {
  dual,
  simplifiedChinese,
  traditionalChinese,
  english,
  japanese,
  systemLanguage,
}

enum PlaybackSubtitleLanguage {
  simplifiedChinese,
  traditionalChinese,
  english,
  japanese,
  systemLanguage,
}

extension PlaybackSubtitleLanguageX on PlaybackSubtitleLanguage {
  String get label => switch (this) {
        PlaybackSubtitleLanguage.simplifiedChinese => '简体中文',
        PlaybackSubtitleLanguage.traditionalChinese => '繁体中文',
        PlaybackSubtitleLanguage.english => '英语',
        PlaybackSubtitleLanguage.japanese => '日语',
        PlaybackSubtitleLanguage.systemLanguage => '系统语言',
      };

  List<String> get preferredLanguages => switch (this) {
        PlaybackSubtitleLanguage.simplifiedChinese => const ['zh-cn'],
        PlaybackSubtitleLanguage.traditionalChinese => const ['zh-tw'],
        PlaybackSubtitleLanguage.english => const ['en'],
        PlaybackSubtitleLanguage.japanese => const ['ja'],
        PlaybackSubtitleLanguage.systemLanguage => const [],
      };

  static PlaybackSubtitleLanguage fromName(
    String raw, {
    required PlaybackSubtitleLanguage fallback,
  }) {
    return switch (raw.trim()) {
      'simplifiedChinese' => PlaybackSubtitleLanguage.simplifiedChinese,
      'traditionalChinese' => PlaybackSubtitleLanguage.traditionalChinese,
      'english' => PlaybackSubtitleLanguage.english,
      'japanese' => PlaybackSubtitleLanguage.japanese,
      'systemLanguage' => PlaybackSubtitleLanguage.systemLanguage,
      _ => fallback,
    };
  }
}

extension PlaybackDefaultSubtitleX on PlaybackDefaultSubtitle {
  String get label => switch (this) {
        PlaybackDefaultSubtitle.dual => '双字幕',
        PlaybackDefaultSubtitle.simplifiedChinese => '简体中文',
        PlaybackDefaultSubtitle.traditionalChinese => '繁体中文',
        PlaybackDefaultSubtitle.english => '英语',
        PlaybackDefaultSubtitle.japanese => '日语',
        PlaybackDefaultSubtitle.systemLanguage => '系统语言',
      };

  String get description => switch (this) {
        PlaybackDefaultSubtitle.dual =>
          '按单独设置的主字幕语言和副字幕语言匹配；缺少对应轨道或播放器不支持时回退系统语言。',
        PlaybackDefaultSubtitle.systemLanguage => '按设备当前系统语言选择字幕。',
        _ => '优先选择$label；片源没有对应轨道时回退系统语言。',
      };

  List<String> get preferredLanguages => switch (this) {
        PlaybackDefaultSubtitle.simplifiedChinese => const ['zh-cn'],
        PlaybackDefaultSubtitle.traditionalChinese => const ['zh-tw'],
        PlaybackDefaultSubtitle.english => const ['en'],
        PlaybackDefaultSubtitle.japanese => const ['ja'],
        PlaybackDefaultSubtitle.dual ||
        PlaybackDefaultSubtitle.systemLanguage =>
          const [],
      };

  static PlaybackDefaultSubtitle fromName(String raw) {
    return switch (raw.trim()) {
      'dual' => PlaybackDefaultSubtitle.dual,
      'simplifiedChinese' => PlaybackDefaultSubtitle.simplifiedChinese,
      'traditionalChinese' => PlaybackDefaultSubtitle.traditionalChinese,
      'english' => PlaybackDefaultSubtitle.english,
      'japanese' => PlaybackDefaultSubtitle.japanese,
      'systemLanguage' => PlaybackDefaultSubtitle.systemLanguage,
      _ => PlaybackDefaultSubtitle.systemLanguage,
    };
  }
}

enum PlaybackEngine { embeddedMpv, nativeContainer, systemPlayer }

extension PlaybackEngineX on PlaybackEngine {
  String get label {
    switch (this) {
      case PlaybackEngine.embeddedMpv:
        return '内置 MPV';
      case PlaybackEngine.nativeContainer:
        return 'App 内原生播放器';
      case PlaybackEngine.systemPlayer:
        return '外部播放器';
    }
  }

  String get description {
    switch (this) {
      case PlaybackEngine.embeddedMpv:
        return '使用应用内置播放器，支持字幕、音轨和倍速控制。';
      case PlaybackEngine.nativeContainer:
        return 'Android / iOS 上使用系统原生播放内核，兼容性取决于终端；失败时可重试或退出，不会自动切换 MPV。';
      case PlaybackEngine.systemPlayer:
        return '交给系统默认的视频播放器处理。';
    }
  }

  static PlaybackEngine fromName(String raw) {
    return switch (raw) {
      'systemPlayer' => PlaybackEngine.systemPlayer,
      'nativeContainer' => PlaybackEngine.nativeContainer,
      'embeddedMpv' => PlaybackEngine.embeddedMpv,
      _ => PlaybackEngine.embeddedMpv,
    };
  }
}

enum PlaybackDecodeMode { auto, hardwarePreferred, softwarePreferred }

extension PlaybackDecodeModeX on PlaybackDecodeMode {
  String get label {
    switch (this) {
      case PlaybackDecodeMode.auto:
        return '自动';
      case PlaybackDecodeMode.hardwarePreferred:
        return '硬解优先';
      case PlaybackDecodeMode.softwarePreferred:
        return '软解优先';
    }
  }

  String get description {
    switch (this) {
      case PlaybackDecodeMode.auto:
        return '按设备能力自动选择；开启“更积极的解码与 MPV 调优”后会更积极地优先硬解。';
      case PlaybackDecodeMode.hardwarePreferred:
        return '尽量优先使用硬件解码，适合高码率和 4K 片源。';
      case PlaybackDecodeMode.softwarePreferred:
        return '尽量优先使用软件解码，兼容性更高，但更吃 CPU。';
    }
  }

  static PlaybackDecodeMode fromName(String raw) {
    return switch (raw) {
      'hardwarePreferred' => PlaybackDecodeMode.hardwarePreferred,
      'softwarePreferred' => PlaybackDecodeMode.softwarePreferred,
      'auto' => PlaybackDecodeMode.auto,
      _ => PlaybackDecodeMode.auto,
    };
  }
}

enum NativeAudioOutputMode { auto, pcmCompatibility, devicePassthrough }

extension NativeAudioOutputModeX on NativeAudioOutputMode {
  String get label {
    switch (this) {
      case NativeAudioOutputMode.auto:
        return '自动（推荐）';
      case NativeAudioOutputMode.pcmCompatibility:
        return 'PCM 兼容';
      case NativeAudioOutputMode.devicePassthrough:
        return '设备直通';
    }
  }

  String get description {
    switch (this) {
      case NativeAudioOutputMode.auto:
        return 'Android TV 上 DDP 自动转 PCM；TrueHD、DTS 等无法解码的格式自动软解出声。';
      case NativeAudioOutputMode.pcmCompatibility:
        return '强制解码后输出 PCM，适合电视或 HDMI 组合有画面但没有声音时使用。';
      case NativeAudioOutputMode.devicePassthrough:
        return '交给电视、回音壁或功放解码压缩音频；无法直通的格式（如 TrueHD）会自动软解出声。';
    }
  }

  static NativeAudioOutputMode fromName(String raw) {
    return switch (raw) {
      'pcmCompatibility' => NativeAudioOutputMode.pcmCompatibility,
      'devicePassthrough' => NativeAudioOutputMode.devicePassthrough,
      'auto' => NativeAudioOutputMode.auto,
      _ => NativeAudioOutputMode.auto,
    };
  }
}

enum PlaybackMpvQualityPreset { qualityFirst, balanced, performanceFirst }

extension PlaybackMpvQualityPresetX on PlaybackMpvQualityPreset {
  String get label {
    switch (this) {
      case PlaybackMpvQualityPreset.qualityFirst:
        return '画质优先';
      case PlaybackMpvQualityPreset.balanced:
        return '平衡';
      case PlaybackMpvQualityPreset.performanceFirst:
        return '性能优先';
    }
  }

  String get description {
    switch (this) {
      case PlaybackMpvQualityPreset.qualityFirst:
        return '优先保留去色带与更锐利的缩放策略，适合更在意观感的场景。';
      case PlaybackMpvQualityPreset.balanced:
        return '在清晰度、稳定性与设备负载之间取中间值。';
      case PlaybackMpvQualityPreset.performanceFirst:
        return '默认推荐，优先稳播并降低缩放与后处理压力。';
    }
  }

  static PlaybackMpvQualityPreset fromName(String _) {
    // Older settings may still contain removed presets; collapse everything
    // to the fixed runtime default to keep playback behavior predictable.
    return PlaybackMpvQualityPreset.performanceFirst;
  }
}

const double kPlaybackSubtitleScaleMin = 20.0;
const double kPlaybackSubtitleScaleMax = 78.0;
const double kPlaybackSubtitleScaleStep = 1.0;
const double kPlaybackSubtitleScaleDefault = 32.0;
const double kPlaybackSubtitlePositionMin = 50.0;
const double kPlaybackSubtitlePositionMax = 100.0;
const double kPlaybackSubtitlePositionStep = 1.0;
const double kPlaybackSubtitlePositionQuickStep = 5.0;
const double kPlaybackPrimarySubtitlePositionDefault = 80.0;
const double kPlaybackSecondarySubtitlePositionDefault = 90.0;
const double kPlaybackSecondarySubtitleScaleMin = 50.0;
const double kPlaybackSecondarySubtitleScaleMax = 120.0;
const double kPlaybackSecondarySubtitleScaleStep = 5.0;
const double kPlaybackSecondarySubtitleScaleDefault = 50.0;
const int kPlaybackSubtitleStyleDefaultsVersion = 1;
const int kSubtitleSearchMaxValidatedCandidatesMin = 1;
const int kSubtitleSearchMaxValidatedCandidatesMax = 20;
const int kSubtitleSearchMaxValidatedCandidatesDefault = 5;
const int kTaskMaxConcurrencyMin = 1;
const int kTaskMaxConcurrencyMax = 6;
const int kTaskMaxConcurrencyDefault = 2;
const int kMetadataPrefetchInitialBatchSizeMin = 6;
const int kMetadataPrefetchInitialBatchSizeMax = 24;
const int kMetadataPrefetchInitialBatchSizeStep = 6;
const int kMetadataPrefetchInitialBatchSizeDefault = 12;
const int kMetadataPrefetchBatchDelayMsMin = 0;
const int kMetadataPrefetchBatchDelayMsMax = 1000;
const int kMetadataPrefetchBatchDelayMsStep = 50;
const int kMetadataPrefetchBatchDelayMsDefault = 300;
const int kMetadataPrefetchForegroundResumeDelayMsMin = 0;
const int kMetadataPrefetchForegroundResumeDelayMsMax = 2000;
const int kMetadataPrefetchForegroundResumeDelayMsStep = 100;
const int kMetadataPrefetchForegroundResumeDelayMsDefault = 400;
const int kHomeFeedInitialBatchSizeMin = 1;
const int kHomeFeedInitialBatchSizeMax = 6;
const int kHomeFeedInitialBatchSizeDefault = 2;
const int kHomeFeedBatchDelayMsMin = 0;
const int kHomeFeedBatchDelayMsMax = 1000;
const int kHomeFeedBatchDelayMsStep = 50;
const int kHomeFeedBatchDelayMsDefault = 350;
const int kLocalLogMaxSizeMbDefault = 20;
const List<int> kLocalLogMaxSizeOptionsMb = <int>[5, 10, 20, 50, 100];
const Set<AppLogLevel> kDefaultLocalLogRecordedLevels =
    kDefaultRecordedAppLogLevels;
const Set<AppLogLevel> kDefaultLocalLogVisibleLevels =
    kDefaultRecordedAppLogLevels;

int normalizeLocalLogMaxSizeMb(int value) {
  if (kLocalLogMaxSizeOptionsMb.contains(value)) {
    return value;
  }
  return kLocalLogMaxSizeMbDefault;
}

int clampTaskMaxConcurrency(int value) {
  return value.clamp(
    kTaskMaxConcurrencyMin,
    kTaskMaxConcurrencyMax,
  );
}

int clampMetadataPrefetchInitialBatchSize(int value) {
  final clamped = value.clamp(
    kMetadataPrefetchInitialBatchSizeMin,
    kMetadataPrefetchInitialBatchSizeMax,
  );
  final steps = ((clamped - kMetadataPrefetchInitialBatchSizeMin) /
          kMetadataPrefetchInitialBatchSizeStep)
      .round();
  return kMetadataPrefetchInitialBatchSizeMin +
      steps * kMetadataPrefetchInitialBatchSizeStep;
}

int clampHomeFeedInitialBatchSize(int value) {
  return value.clamp(
    kHomeFeedInitialBatchSizeMin,
    kHomeFeedInitialBatchSizeMax,
  );
}

int clampMetadataPrefetchBatchDelayMs(int value) => value.clamp(
      kMetadataPrefetchBatchDelayMsMin,
      kMetadataPrefetchBatchDelayMsMax,
    );

int clampMetadataPrefetchForegroundResumeDelayMs(int value) => value.clamp(
      kMetadataPrefetchForegroundResumeDelayMsMin,
      kMetadataPrefetchForegroundResumeDelayMsMax,
    );

int clampHomeFeedBatchDelayMs(int value) => value.clamp(
      kHomeFeedBatchDelayMsMin,
      kHomeFeedBatchDelayMsMax,
    );

Set<AppLogLevel> parseLocalLogLevels(
  Object? value, {
  required Set<AppLogLevel> fallback,
}) {
  if (value is! List) {
    return Set<AppLogLevel>.from(fallback);
  }
  final names = value.whereType<String>().toSet();
  return <AppLogLevel>{
    for (final level in AppLogLevel.values)
      if (names.contains(level.name)) level,
  };
}

double clampPlaybackSubtitleScale(double value) {
  final clamped = value.clamp(
    kPlaybackSubtitleScaleMin,
    kPlaybackSubtitleScaleMax,
  );
  return clamped.toDouble().roundToDouble();
}

double stepPlaybackSubtitleScale(double current, int delta) {
  return clampPlaybackSubtitleScale(
    current + (delta * kPlaybackSubtitleScaleStep),
  );
}

String formatPlaybackSubtitleScaleLabel(double value) {
  final normalized = clampPlaybackSubtitleScale(value);
  return '${normalized.toStringAsFixed(0)}号';
}

double parsePlaybackSubtitleScale(Object? raw) {
  if (raw is num) {
    return clampPlaybackSubtitleScale(raw.toDouble());
  }
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return kPlaybackSubtitleScaleDefault;
    }
    final parsed = double.tryParse(trimmed);
    if (parsed != null) {
      return clampPlaybackSubtitleScale(parsed);
    }
    return switch (trimmed) {
      'compact' => 28.0,
      'large' => 36.0,
      'xLarge' => 40.0,
      'standard' => kPlaybackSubtitleScaleDefault,
      _ => kPlaybackSubtitleScaleDefault,
    };
  }
  return kPlaybackSubtitleScaleDefault;
}

double clampPlaybackSubtitlePosition(double value) {
  final clamped = value.clamp(
    kPlaybackSubtitlePositionMin,
    kPlaybackSubtitlePositionMax,
  );
  final steps =
      ((clamped - kPlaybackSubtitlePositionMin) / kPlaybackSubtitlePositionStep)
          .round();
  return kPlaybackSubtitlePositionMin + (steps * kPlaybackSubtitlePositionStep);
}

double stepPlaybackSubtitlePosition(double current, int delta) {
  return clampPlaybackSubtitlePosition(
    current + (delta * kPlaybackSubtitlePositionStep),
  );
}

double stepPlaybackSubtitlePositionQuick(double current, int delta) {
  return clampPlaybackSubtitlePosition(
    current + (delta * kPlaybackSubtitlePositionQuickStep),
  );
}

double parsePlaybackSubtitlePosition(Object? raw, double fallback) {
  return clampPlaybackSubtitlePosition(
    raw is num ? raw.toDouble() : fallback,
  );
}

String formatPlaybackSubtitlePositionLabel(double value) {
  return '${clampPlaybackSubtitlePosition(value).toStringAsFixed(0)}%';
}

double clampPlaybackSecondarySubtitleScale(double value) {
  final clamped = value.clamp(
    kPlaybackSecondarySubtitleScaleMin,
    kPlaybackSecondarySubtitleScaleMax,
  );
  final steps = ((clamped - kPlaybackSecondarySubtitleScaleMin) /
          kPlaybackSecondarySubtitleScaleStep)
      .round();
  return kPlaybackSecondarySubtitleScaleMin +
      (steps * kPlaybackSecondarySubtitleScaleStep);
}

double stepPlaybackSecondarySubtitleScale(double current, int delta) {
  return clampPlaybackSecondarySubtitleScale(
    current + (delta * kPlaybackSecondarySubtitleScaleStep),
  );
}

String formatPlaybackSecondarySubtitleScaleLabel(double value) {
  return '${clampPlaybackSecondarySubtitleScale(value).toStringAsFixed(0)}%';
}

int clampSubtitleSearchMaxValidatedCandidates(int value) {
  return value.clamp(
    kSubtitleSearchMaxValidatedCandidatesMin,
    kSubtitleSearchMaxValidatedCandidatesMax,
  );
}

List<String> parseSubtitlePreferredLanguages(Object? raw) {
  const removedKoreanAliases = <String>{
    'ko',
    'kr',
    'kor',
    'korean',
    '韩语',
    '韓語',
    '韩文',
    '韓文',
  };
  return (raw as List<dynamic>? ?? const <dynamic>[])
      .whereType<String>()
      .map((item) => item.trim().toLowerCase())
      .where((item) => item.isNotEmpty && !removedKoreanAliases.contains(item))
      .toSet()
      .toList(growable: false);
}

class HomeModuleConfig {
  const HomeModuleConfig({
    required this.id,
    required this.type,
    required this.title,
    required this.enabled,
    this.sourceId = '',
    this.sourceName = '',
    this.sectionId = '',
    this.sectionName = '',
    this.doubanInterestStatus = DoubanInterestStatus.mark,
    this.doubanSuggestionType = DoubanSuggestionMediaType.movie,
    this.doubanListUrl = '',
  });

  final String id;
  final HomeModuleType type;
  final String title;
  final bool enabled;
  final String sourceId;
  final String sourceName;
  final String sectionId;
  final String sectionName;
  final DoubanInterestStatus doubanInterestStatus;
  final DoubanSuggestionMediaType doubanSuggestionType;
  final String doubanListUrl;

  static const heroModuleId = 'home-module-hero';

  String get description {
    switch (type) {
      case HomeModuleType.hero:
        return '首页 Hero';
      case HomeModuleType.recentlyAdded:
        return '展示最近同步进来的内容';
      case HomeModuleType.recentPlayback:
        return '展示最近播放过的内容';
      case HomeModuleType.librarySection:
        final sourcePart = sourceName.trim().isEmpty ? '资源来源' : sourceName;
        final sectionPart = sectionId.trim().isEmpty
            ? '全部内容'
            : (sectionName.trim().isEmpty ? '分区' : sectionName);
        return '$sourcePart · $sectionPart';
      case HomeModuleType.doubanInterest:
        return doubanInterestStatus.label;
      case HomeModuleType.doubanSuggestion:
        return '个性化推荐 · ${doubanSuggestionType.label}';
      case HomeModuleType.doubanList:
        return doubanListUrl.trim().isEmpty ? '未填写片单地址' : doubanListUrl;
      case HomeModuleType.doubanCarousel:
        return '首页轮播';
    }
  }

  bool get isLibrarySection =>
      type == HomeModuleType.librarySection && sourceId.trim().isNotEmpty;

  HomeModuleConfig copyWith({
    String? id,
    HomeModuleType? type,
    String? title,
    bool? enabled,
    String? sourceId,
    String? sourceName,
    String? sectionId,
    String? sectionName,
    DoubanInterestStatus? doubanInterestStatus,
    DoubanSuggestionMediaType? doubanSuggestionType,
    String? doubanListUrl,
  }) {
    return HomeModuleConfig(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      enabled: enabled ?? this.enabled,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      sectionId: sectionId ?? this.sectionId,
      sectionName: sectionName ?? this.sectionName,
      doubanInterestStatus: doubanInterestStatus ?? this.doubanInterestStatus,
      doubanSuggestionType: doubanSuggestionType ?? this.doubanSuggestionType,
      doubanListUrl: doubanListUrl ?? this.doubanListUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'enabled': enabled,
      'sourceId': sourceId,
      'sourceName': sourceName,
      'sectionId': sectionId,
      'sectionName': sectionName,
      'doubanInterestStatus': doubanInterestStatus.value,
      'doubanSuggestionType': doubanSuggestionType.value,
      'doubanListUrl': doubanListUrl,
    };
  }

  factory HomeModuleConfig.fromJson(Map<String, dynamic> json) {
    final type = HomeModuleTypeX.fromName(json['type'] as String? ?? '');
    final id = json['id'] as String? ?? '';

    return HomeModuleConfig(
      id: id,
      type: type,
      title: (json['title'] as String? ?? '').trim().isEmpty
          ? _fallbackTitle(type, json)
          : (json['title'] as String? ?? '').trim(),
      enabled: json['enabled'] as bool? ?? false,
      sourceId: json['sourceId'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? '',
      sectionId: json['sectionId'] as String? ?? '',
      sectionName: json['sectionName'] as String? ?? '',
      doubanInterestStatus: DoubanInterestStatusX.fromValue(
        json['doubanInterestStatus'] as String? ??
            DoubanInterestStatus.mark.value,
      ),
      doubanSuggestionType: DoubanSuggestionMediaTypeX.fromValue(
        json['doubanSuggestionType'] as String? ??
            DoubanSuggestionMediaType.movie.value,
      ),
      doubanListUrl: json['doubanListUrl'] as String? ?? '',
    );
  }

  static String _fallbackTitle(HomeModuleType type, Map<String, dynamic> json) {
    return switch (type) {
      HomeModuleType.hero => 'Hero',
      HomeModuleType.recentlyAdded => '最近新增',
      HomeModuleType.recentPlayback => '最近播放',
      HomeModuleType.librarySection =>
        (json['sectionName'] as String? ?? '').trim().isEmpty
            ? '来源分区'
            : (json['sectionName'] as String? ?? '').trim(),
      HomeModuleType.doubanInterest => DoubanInterestStatusX.fromValue(
          json['doubanInterestStatus'] as String? ??
              DoubanInterestStatus.mark.value,
        ).label,
      HomeModuleType.doubanSuggestion => '豆瓣个性化推荐',
      HomeModuleType.doubanList => '豆瓣片单',
      HomeModuleType.doubanCarousel => '豆瓣轮播',
    };
  }

  static HomeModuleConfig recentlyAdded() {
    return HomeModuleConfig(
      id: 'home-module-${DateTime.now().millisecondsSinceEpoch}',
      type: HomeModuleType.recentlyAdded,
      title: '最近新增',
      enabled: true,
    );
  }

  static HomeModuleConfig recentPlayback() {
    return HomeModuleConfig(
      id: 'home-module-${DateTime.now().millisecondsSinceEpoch}',
      type: HomeModuleType.recentPlayback,
      title: '最近播放',
      enabled: true,
    );
  }

  static HomeModuleConfig libraryCollection(MediaCollection collection) {
    return HomeModuleConfig(
      id: 'home-module-${DateTime.now().millisecondsSinceEpoch}',
      type: HomeModuleType.librarySection,
      title: collection.title,
      enabled: true,
      sourceId: collection.sourceId,
      sourceName: collection.sourceName,
      sectionId: collection.id,
      sectionName: collection.title,
    );
  }

  static HomeModuleConfig librarySource(MediaSourceConfig source) {
    return HomeModuleConfig(
      id: 'home-module-${DateTime.now().millisecondsSinceEpoch}',
      type: HomeModuleType.librarySection,
      title: source.name.trim().isEmpty ? '媒体库' : source.name.trim(),
      enabled: true,
      sourceId: source.id,
      sourceName: source.name,
      sectionId: '',
      sectionName: '全部内容',
    );
  }

  static HomeModuleConfig doubanInterest(DoubanInterestStatus status) {
    return HomeModuleConfig(
      id: 'home-module-${DateTime.now().millisecondsSinceEpoch}',
      type: HomeModuleType.doubanInterest,
      title: status.label,
      enabled: true,
      doubanInterestStatus: status,
    );
  }

  static HomeModuleConfig doubanSuggestion(
    DoubanSuggestionMediaType mediaType,
  ) {
    return HomeModuleConfig(
      id: 'home-module-${DateTime.now().millisecondsSinceEpoch}',
      type: HomeModuleType.doubanSuggestion,
      title: '豆瓣个性化推荐 · ${mediaType.label}',
      enabled: true,
      doubanSuggestionType: mediaType,
    );
  }

  static HomeModuleConfig doubanList({
    required String title,
    required String url,
  }) {
    return HomeModuleConfig(
      id: 'home-module-${DateTime.now().millisecondsSinceEpoch}',
      type: HomeModuleType.doubanList,
      title: title,
      enabled: true,
      doubanListUrl: url,
    );
  }

  static HomeModuleConfig doubanCarousel() {
    return HomeModuleConfig(
      id: 'home-module-${DateTime.now().millisecondsSinceEpoch}',
      type: HomeModuleType.doubanCarousel,
      title: '豆瓣轮播',
      enabled: true,
    );
  }

  static HomeModuleConfig hero({bool enabled = true}) {
    return HomeModuleConfig(
      id: heroModuleId,
      type: HomeModuleType.hero,
      title: 'Hero',
      enabled: enabled,
    );
  }
}

class NetworkStorageConfig {
  const NetworkStorageConfig({
    this.quarkCookie = '',
    this.quarkSaveFolderId = '0',
    this.quarkSaveFolderPath = '/',
    this.syncDeleteQuarkEnabled = false,
    this.syncDeleteQuarkWebDavDirectories = const [],
    this.smartStrmWebhookUrl = '',
    this.smartStrmTaskName = '',
    this.smartStrmDelaySeconds = 1,
    this.refreshMediaSourceIds = const [],
    this.refreshDelaySeconds = 1,
  });

  final String quarkCookie;
  final String quarkSaveFolderId;
  final String quarkSaveFolderPath;
  final bool syncDeleteQuarkEnabled;
  final List<NetworkStorageWebDavDirectory> syncDeleteQuarkWebDavDirectories;
  final String smartStrmWebhookUrl;
  final String smartStrmTaskName;
  final int smartStrmDelaySeconds;
  final List<String> refreshMediaSourceIds;
  final int refreshDelaySeconds;

  bool get hasAnyConfigured {
    return quarkCookie.trim().isNotEmpty ||
        smartStrmWebhookUrl.trim().isNotEmpty ||
        smartStrmTaskName.trim().isNotEmpty ||
        smartStrmDelaySeconds != 1 ||
        quarkSaveFolderId.trim() != '0' ||
        quarkSaveFolderPath.trim() != '/' ||
        syncDeleteQuarkEnabled ||
        syncDeleteQuarkWebDavDirectories.isNotEmpty ||
        refreshMediaSourceIds.isNotEmpty ||
        refreshDelaySeconds != 1;
  }

  NetworkStorageConfig copyWith({
    String? quarkCookie,
    String? quarkSaveFolderId,
    String? quarkSaveFolderPath,
    bool? syncDeleteQuarkEnabled,
    List<NetworkStorageWebDavDirectory>? syncDeleteQuarkWebDavDirectories,
    String? smartStrmWebhookUrl,
    String? smartStrmTaskName,
    int? smartStrmDelaySeconds,
    List<String>? refreshMediaSourceIds,
    int? refreshDelaySeconds,
  }) {
    return NetworkStorageConfig(
      quarkCookie: quarkCookie ?? this.quarkCookie,
      quarkSaveFolderId: quarkSaveFolderId ?? this.quarkSaveFolderId,
      quarkSaveFolderPath: quarkSaveFolderPath ?? this.quarkSaveFolderPath,
      syncDeleteQuarkEnabled:
          syncDeleteQuarkEnabled ?? this.syncDeleteQuarkEnabled,
      syncDeleteQuarkWebDavDirectories: syncDeleteQuarkWebDavDirectories ??
          this.syncDeleteQuarkWebDavDirectories,
      smartStrmWebhookUrl: smartStrmWebhookUrl ?? this.smartStrmWebhookUrl,
      smartStrmTaskName: smartStrmTaskName ?? this.smartStrmTaskName,
      smartStrmDelaySeconds:
          smartStrmDelaySeconds ?? this.smartStrmDelaySeconds,
      refreshMediaSourceIds:
          refreshMediaSourceIds ?? this.refreshMediaSourceIds,
      refreshDelaySeconds: refreshDelaySeconds ?? this.refreshDelaySeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'quarkCookie': quarkCookie,
      'quarkSaveFolderId': quarkSaveFolderId,
      'quarkSaveFolderPath': quarkSaveFolderPath,
      'syncDeleteQuarkEnabled': syncDeleteQuarkEnabled,
      'syncDeleteQuarkWebDavDirectories': syncDeleteQuarkWebDavDirectories
          .map((item) => item.toJson())
          .toList(growable: false),
      'smartStrmWebhookUrl': smartStrmWebhookUrl,
      'smartStrmTaskName': smartStrmTaskName,
      'smartStrmDelaySeconds': smartStrmDelaySeconds,
      'refreshMediaSourceIds': refreshMediaSourceIds,
      'refreshDelaySeconds': refreshDelaySeconds,
    };
  }

  factory NetworkStorageConfig.fromJson(Map<String, dynamic> json) {
    final resolvedRefreshDelaySeconds =
        (json['refreshDelaySeconds'] as num?)?.toInt() ?? 1;
    final resolvedSmartStrmDelaySeconds =
        (json['smartStrmDelaySeconds'] as num?)?.toInt() ??
            resolvedRefreshDelaySeconds;
    return NetworkStorageConfig(
      quarkCookie: json['quarkCookie'] as String? ?? '',
      quarkSaveFolderId: json['quarkSaveFolderId'] as String? ?? '0',
      quarkSaveFolderPath: json['quarkSaveFolderPath'] as String? ?? '/',
      syncDeleteQuarkEnabled: json['syncDeleteQuarkEnabled'] as bool? ?? false,
      syncDeleteQuarkWebDavDirectories:
          (json['syncDeleteQuarkWebDavDirectories'] as List<dynamic>? ??
                  const [])
              .whereType<Map>()
              .map(
                (item) => NetworkStorageWebDavDirectory.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((item) => item.sourceId.isNotEmpty)
              .where((item) => item.directoryId.isNotEmpty)
              .toList(growable: false),
      smartStrmWebhookUrl: json['smartStrmWebhookUrl'] as String? ?? '',
      smartStrmTaskName: json['smartStrmTaskName'] as String? ?? '',
      smartStrmDelaySeconds: resolvedSmartStrmDelaySeconds <= 0
          ? 1
          : resolvedSmartStrmDelaySeconds,
      refreshMediaSourceIds:
          (json['refreshMediaSourceIds'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false),
      refreshDelaySeconds:
          resolvedRefreshDelaySeconds <= 0 ? 1 : resolvedRefreshDelaySeconds,
    );
  }
}

class NetworkStorageWebDavDirectory {
  const NetworkStorageWebDavDirectory({
    required this.sourceId,
    this.sourceName = '',
    required this.directoryId,
    this.directoryLabel = '',
  });

  final String sourceId;
  final String sourceName;
  final String directoryId;
  final String directoryLabel;

  NetworkStorageWebDavDirectory copyWith({
    String? sourceId,
    String? sourceName,
    String? directoryId,
    String? directoryLabel,
  }) {
    return NetworkStorageWebDavDirectory(
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      directoryId: directoryId ?? this.directoryId,
      directoryLabel: directoryLabel ?? this.directoryLabel,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sourceId': sourceId,
      'sourceName': sourceName,
      'directoryId': directoryId,
      'directoryLabel': directoryLabel,
    };
  }

  factory NetworkStorageWebDavDirectory.fromJson(Map<String, dynamic> json) {
    return NetworkStorageWebDavDirectory(
      sourceId: (json['sourceId'] as String? ?? '').trim(),
      sourceName: (json['sourceName'] as String? ?? '').trim(),
      directoryId: (json['directoryId'] as String? ?? '').trim(),
      directoryLabel: (json['directoryLabel'] as String? ?? '').trim(),
    );
  }
}

const kNavigationDestinationHome = 'home';
const kNavigationDestinationSearch = 'search';
const kNavigationDestinationFavorites = 'favorites';
const kNavigationDestinationLibrary = 'library';
const kNavigationDestinationSettings = 'settings';

const kAllNavigationDestinationIds = <String>[
  kNavigationDestinationHome,
  kNavigationDestinationSearch,
  kNavigationDestinationFavorites,
  kNavigationDestinationLibrary,
  kNavigationDestinationSettings,
];

const kDefaultNavigationDestinationIds = <String>[
  kNavigationDestinationHome,
  kNavigationDestinationSearch,
  kNavigationDestinationLibrary,
  kNavigationDestinationSettings,
];

const kAppSettingsSchemaVersion = 2;

List<String> normalizeNavigationDestinationIds(Iterable<String> values) {
  final selected = values
      .map((value) => value.trim())
      .where(kAllNavigationDestinationIds.contains)
      .toSet();
  if (selected.isEmpty) {
    selected.add(kNavigationDestinationHome);
  }
  selected.add(kNavigationDestinationSettings);
  return [
    for (final id in kAllNavigationDestinationIds)
      if (selected.contains(id)) id,
  ];
}

class AppSettings {
  const AppSettings({
    required this.mediaSources,
    required this.searchProviders,
    required this.doubanAccount,
    required this.homeModules,
    this.networkStorage = const NetworkStorageConfig(),
    this.homeHeroSourceModuleId = '',
    this.homeHeroDisplayMode = HomeHeroDisplayMode.normal,
    this.homeHeroStyle = HomeHeroStyle.composite,
    this.homeHeroLogoTitleEnabled = false,
    this.homeHeroBackgroundEnabled = true,
    this.homeStartupAutoRefreshEnabled = true,
    this.homeStartupAutoRefreshEmbyEnabled,
    this.homeNavigationSingleTapCleanupEnabled = true,
    this.translucentEffectsEnabled = true,
    this.autoHideNavigationBarEnabled = true,
    this.navigationDestinationIds = kDefaultNavigationDestinationIds,
    this.performanceReduceDecorationsEnabled = false,
    this.performanceReduceMotionEnabled = false,
    this.performanceStaticNavigationEnabled = false,
    this.performanceStaticHomeHeroEnabled = false,
    this.performanceLightweightHomeHeroEnabled = false,
    this.performanceLiveItemHeroOverlayEnabled = true,
    this.performanceAggressivePlaybackTuningEnabled = false,
    this.taskMaxConcurrency = kTaskMaxConcurrencyDefault,
    this.metadataPrefetchInitialBatchSize =
        kMetadataPrefetchInitialBatchSizeDefault,
    this.metadataPrefetchBatchDelayMs = kMetadataPrefetchBatchDelayMsDefault,
    this.metadataPrefetchForegroundResumeDelayMs =
        kMetadataPrefetchForegroundResumeDelayMsDefault,
    this.homeFeedInitialBatchSize = kHomeFeedInitialBatchSizeDefault,
    this.homeFeedBatchDelayMs = kHomeFeedBatchDelayMsDefault,
    this.tmdbMetadataMatchEnabled = false,
    this.wmdbMetadataMatchEnabled = false,
    this.metadataMatchPriority = MetadataMatchProvider.tmdb,
    this.imdbRatingMatchEnabled = false,
    this.detailAutoLibraryMatchEnabled = false,
    this.libraryMatchSourceIds = const [],
    this.searchSourceIds = const [],
    this.tmdbReadAccessToken = '',
    this.playbackOpenTimeoutSeconds = 20,
    this.playbackDefaultSpeed = 1.0,
    this.playbackSubtitlePreference = PlaybackSubtitlePreference.auto,
    this.playbackDefaultSubtitle = PlaybackDefaultSubtitle.systemLanguage,
    this.playbackDualSubtitlePrimaryLanguage =
        PlaybackSubtitleLanguage.simplifiedChinese,
    this.playbackDualSubtitleSecondaryLanguage =
        PlaybackSubtitleLanguage.english,
    this.playbackSubtitleScale = kPlaybackSubtitleScaleDefault,
    this.playbackPrimarySubtitlePosition =
        kPlaybackPrimarySubtitlePositionDefault,
    this.playbackSecondarySubtitlePosition =
        kPlaybackSecondarySubtitlePositionDefault,
    this.playbackSecondarySubtitleScale =
        kPlaybackSecondarySubtitleScaleDefault,
    this.onlineSubtitleSources = const [OnlineSubtitleSource.assrt],
    this.assrtToken = '',
    this.opensubtitlesEnabled = false,
    this.opensubtitlesUsername = '',
    this.opensubtitlesPassword = '',
    this.subdlEnabled = false,
    this.subdlApiKey = '',
    this.subtitlePreferredLanguages = const [],
    this.subtitleSearchMaxValidatedCandidates =
        kSubtitleSearchMaxValidatedCandidatesDefault,
    this.playbackBackgroundPlaybackEnabled = true,
    this.playbackEngine = PlaybackEngine.embeddedMpv,
    this.playbackDecodeMode = PlaybackDecodeMode.auto,
    this.nativeAudioOutputMode = NativeAudioOutputMode.auto,
    this.playbackMpvQualityPreset = PlaybackMpvQualityPreset.performanceFirst,
    this.playbackMpvDoubleTapToSeekEnabled = true,
    this.playbackMpvSwipeToSeekEnabled = true,
    this.playbackMpvLongPressSpeedBoostEnabled = true,
    this.playbackMpvStallAutoRecoveryEnabled = true,
    this.localLoggingEnabled = true,
    this.localLogMaxSizeMb = kLocalLogMaxSizeMbDefault,
    this.localLogRecordedLevels = kDefaultLocalLogRecordedLevels,
    this.localLogVisibleLevels = kDefaultLocalLogVisibleLevels,
  });

  final List<MediaSourceConfig> mediaSources;
  final List<SearchProviderConfig> searchProviders;
  final DoubanAccountConfig doubanAccount;
  final List<HomeModuleConfig> homeModules;
  final NetworkStorageConfig networkStorage;
  final String homeHeroSourceModuleId;
  final HomeHeroDisplayMode homeHeroDisplayMode;
  final HomeHeroStyle homeHeroStyle;
  final bool homeHeroLogoTitleEnabled;
  final bool homeHeroBackgroundEnabled;
  final bool homeStartupAutoRefreshEnabled;
  // null = follow platform default (TV defaults to off, others default to on).
  final bool? homeStartupAutoRefreshEmbyEnabled;
  final bool homeNavigationSingleTapCleanupEnabled;
  final bool translucentEffectsEnabled;
  final bool autoHideNavigationBarEnabled;
  final List<String> navigationDestinationIds;
  final bool performanceReduceDecorationsEnabled;
  final bool performanceReduceMotionEnabled;
  final bool performanceStaticNavigationEnabled;
  final bool performanceStaticHomeHeroEnabled;
  final bool performanceLightweightHomeHeroEnabled;
  final bool performanceLiveItemHeroOverlayEnabled;
  final bool performanceAggressivePlaybackTuningEnabled;
  final int taskMaxConcurrency;
  final int metadataPrefetchInitialBatchSize;
  final int metadataPrefetchBatchDelayMs;
  final int metadataPrefetchForegroundResumeDelayMs;
  final int homeFeedInitialBatchSize;
  final int homeFeedBatchDelayMs;
  final bool tmdbMetadataMatchEnabled;
  final bool wmdbMetadataMatchEnabled;
  final MetadataMatchProvider metadataMatchPriority;
  final bool imdbRatingMatchEnabled;
  final bool detailAutoLibraryMatchEnabled;
  final List<String> libraryMatchSourceIds;
  final List<String> searchSourceIds;
  final String tmdbReadAccessToken;
  final int playbackOpenTimeoutSeconds;
  final double playbackDefaultSpeed;
  final PlaybackSubtitlePreference playbackSubtitlePreference;
  final PlaybackDefaultSubtitle playbackDefaultSubtitle;
  final PlaybackSubtitleLanguage playbackDualSubtitlePrimaryLanguage;
  final PlaybackSubtitleLanguage playbackDualSubtitleSecondaryLanguage;
  final double playbackSubtitleScale;
  final double playbackPrimarySubtitlePosition;
  final double playbackSecondarySubtitlePosition;
  final double playbackSecondarySubtitleScale;
  final List<OnlineSubtitleSource> onlineSubtitleSources;
  final String assrtToken;
  final bool opensubtitlesEnabled;
  final String opensubtitlesUsername;
  final String opensubtitlesPassword;
  final bool subdlEnabled;
  final String subdlApiKey;
  final List<String> subtitlePreferredLanguages;
  final int subtitleSearchMaxValidatedCandidates;
  final bool playbackBackgroundPlaybackEnabled;
  final PlaybackEngine playbackEngine;
  final PlaybackDecodeMode playbackDecodeMode;
  final NativeAudioOutputMode nativeAudioOutputMode;
  final PlaybackMpvQualityPreset playbackMpvQualityPreset;
  final bool playbackMpvDoubleTapToSeekEnabled;
  final bool playbackMpvSwipeToSeekEnabled;
  final bool playbackMpvLongPressSpeedBoostEnabled;
  final bool playbackMpvStallAutoRecoveryEnabled;
  final bool localLoggingEnabled;
  final int localLogMaxSizeMb;
  final Set<AppLogLevel> localLogRecordedLevels;
  final Set<AppLogLevel> localLogVisibleLevels;

  AppSettings copyWith({
    List<MediaSourceConfig>? mediaSources,
    List<SearchProviderConfig>? searchProviders,
    DoubanAccountConfig? doubanAccount,
    List<HomeModuleConfig>? homeModules,
    NetworkStorageConfig? networkStorage,
    String? homeHeroSourceModuleId,
    HomeHeroDisplayMode? homeHeroDisplayMode,
    HomeHeroStyle? homeHeroStyle,
    bool? homeHeroLogoTitleEnabled,
    bool? homeHeroBackgroundEnabled,
    bool? homeStartupAutoRefreshEnabled,
    bool? homeStartupAutoRefreshEmbyEnabled,
    bool? homeNavigationSingleTapCleanupEnabled,
    bool? translucentEffectsEnabled,
    bool? autoHideNavigationBarEnabled,
    List<String>? navigationDestinationIds,
    bool? performanceReduceDecorationsEnabled,
    bool? performanceReduceMotionEnabled,
    bool? performanceStaticNavigationEnabled,
    bool? performanceStaticHomeHeroEnabled,
    bool? performanceLightweightHomeHeroEnabled,
    bool? performanceLiveItemHeroOverlayEnabled,
    bool? performanceAggressivePlaybackTuningEnabled,
    int? taskMaxConcurrency,
    int? metadataPrefetchInitialBatchSize,
    int? metadataPrefetchBatchDelayMs,
    int? metadataPrefetchForegroundResumeDelayMs,
    int? homeFeedInitialBatchSize,
    int? homeFeedBatchDelayMs,
    bool? tmdbMetadataMatchEnabled,
    bool? wmdbMetadataMatchEnabled,
    MetadataMatchProvider? metadataMatchPriority,
    bool? imdbRatingMatchEnabled,
    bool? detailAutoLibraryMatchEnabled,
    List<String>? libraryMatchSourceIds,
    List<String>? searchSourceIds,
    String? tmdbReadAccessToken,
    int? playbackOpenTimeoutSeconds,
    double? playbackDefaultSpeed,
    PlaybackSubtitlePreference? playbackSubtitlePreference,
    PlaybackDefaultSubtitle? playbackDefaultSubtitle,
    PlaybackSubtitleLanguage? playbackDualSubtitlePrimaryLanguage,
    PlaybackSubtitleLanguage? playbackDualSubtitleSecondaryLanguage,
    double? playbackSubtitleScale,
    double? playbackPrimarySubtitlePosition,
    double? playbackSecondarySubtitlePosition,
    double? playbackSecondarySubtitleScale,
    List<OnlineSubtitleSource>? onlineSubtitleSources,
    String? assrtToken,
    bool? opensubtitlesEnabled,
    String? opensubtitlesUsername,
    String? opensubtitlesPassword,
    bool? subdlEnabled,
    String? subdlApiKey,
    List<String>? subtitlePreferredLanguages,
    int? subtitleSearchMaxValidatedCandidates,
    bool? playbackBackgroundPlaybackEnabled,
    PlaybackEngine? playbackEngine,
    PlaybackDecodeMode? playbackDecodeMode,
    NativeAudioOutputMode? nativeAudioOutputMode,
    PlaybackMpvQualityPreset? playbackMpvQualityPreset,
    bool? playbackMpvDoubleTapToSeekEnabled,
    bool? playbackMpvSwipeToSeekEnabled,
    bool? playbackMpvLongPressSpeedBoostEnabled,
    bool? playbackMpvStallAutoRecoveryEnabled,
    bool? localLoggingEnabled,
    int? localLogMaxSizeMb,
    Set<AppLogLevel>? localLogRecordedLevels,
    Set<AppLogLevel>? localLogVisibleLevels,
  }) {
    return AppSettings(
      mediaSources: mediaSources ?? this.mediaSources,
      searchProviders: searchProviders ?? this.searchProviders,
      doubanAccount: doubanAccount ?? this.doubanAccount,
      homeModules: homeModules ?? this.homeModules,
      networkStorage: networkStorage ?? this.networkStorage,
      homeHeroSourceModuleId:
          homeHeroSourceModuleId ?? this.homeHeroSourceModuleId,
      homeHeroDisplayMode: homeHeroDisplayMode ?? this.homeHeroDisplayMode,
      homeHeroStyle: homeHeroStyle ?? this.homeHeroStyle,
      homeHeroLogoTitleEnabled:
          homeHeroLogoTitleEnabled ?? this.homeHeroLogoTitleEnabled,
      homeHeroBackgroundEnabled:
          homeHeroBackgroundEnabled ?? this.homeHeroBackgroundEnabled,
      homeStartupAutoRefreshEnabled:
          homeStartupAutoRefreshEnabled ?? this.homeStartupAutoRefreshEnabled,
      // Nullable: copyWith never resets back to platform default; toggle setter
      // always supplies an explicit bool.
      homeStartupAutoRefreshEmbyEnabled: homeStartupAutoRefreshEmbyEnabled ??
          this.homeStartupAutoRefreshEmbyEnabled,
      homeNavigationSingleTapCleanupEnabled:
          homeNavigationSingleTapCleanupEnabled ??
              this.homeNavigationSingleTapCleanupEnabled,
      translucentEffectsEnabled:
          translucentEffectsEnabled ?? this.translucentEffectsEnabled,
      autoHideNavigationBarEnabled:
          autoHideNavigationBarEnabled ?? this.autoHideNavigationBarEnabled,
      navigationDestinationIds:
          navigationDestinationIds ?? this.navigationDestinationIds,
      performanceReduceDecorationsEnabled:
          performanceReduceDecorationsEnabled ??
              this.performanceReduceDecorationsEnabled,
      performanceReduceMotionEnabled:
          performanceReduceMotionEnabled ?? this.performanceReduceMotionEnabled,
      performanceStaticNavigationEnabled: performanceStaticNavigationEnabled ??
          this.performanceStaticNavigationEnabled,
      performanceStaticHomeHeroEnabled: performanceStaticHomeHeroEnabled ??
          this.performanceStaticHomeHeroEnabled,
      performanceLightweightHomeHeroEnabled:
          performanceLightweightHomeHeroEnabled ??
              this.performanceLightweightHomeHeroEnabled,
      performanceLiveItemHeroOverlayEnabled:
          performanceLiveItemHeroOverlayEnabled ??
              this.performanceLiveItemHeroOverlayEnabled,
      performanceAggressivePlaybackTuningEnabled:
          performanceAggressivePlaybackTuningEnabled ??
              this.performanceAggressivePlaybackTuningEnabled,
      taskMaxConcurrency: taskMaxConcurrency == null
          ? this.taskMaxConcurrency
          : clampTaskMaxConcurrency(taskMaxConcurrency),
      metadataPrefetchInitialBatchSize: metadataPrefetchInitialBatchSize == null
          ? this.metadataPrefetchInitialBatchSize
          : clampMetadataPrefetchInitialBatchSize(
              metadataPrefetchInitialBatchSize,
            ),
      metadataPrefetchBatchDelayMs: metadataPrefetchBatchDelayMs == null
          ? this.metadataPrefetchBatchDelayMs
          : clampMetadataPrefetchBatchDelayMs(metadataPrefetchBatchDelayMs),
      metadataPrefetchForegroundResumeDelayMs:
          metadataPrefetchForegroundResumeDelayMs == null
              ? this.metadataPrefetchForegroundResumeDelayMs
              : clampMetadataPrefetchForegroundResumeDelayMs(
                  metadataPrefetchForegroundResumeDelayMs,
                ),
      homeFeedInitialBatchSize: homeFeedInitialBatchSize == null
          ? this.homeFeedInitialBatchSize
          : clampHomeFeedInitialBatchSize(homeFeedInitialBatchSize),
      homeFeedBatchDelayMs: homeFeedBatchDelayMs == null
          ? this.homeFeedBatchDelayMs
          : clampHomeFeedBatchDelayMs(homeFeedBatchDelayMs),
      tmdbMetadataMatchEnabled:
          tmdbMetadataMatchEnabled ?? this.tmdbMetadataMatchEnabled,
      wmdbMetadataMatchEnabled:
          wmdbMetadataMatchEnabled ?? this.wmdbMetadataMatchEnabled,
      metadataMatchPriority:
          metadataMatchPriority ?? this.metadataMatchPriority,
      imdbRatingMatchEnabled:
          imdbRatingMatchEnabled ?? this.imdbRatingMatchEnabled,
      detailAutoLibraryMatchEnabled:
          detailAutoLibraryMatchEnabled ?? this.detailAutoLibraryMatchEnabled,
      libraryMatchSourceIds:
          libraryMatchSourceIds ?? this.libraryMatchSourceIds,
      searchSourceIds: searchSourceIds ?? this.searchSourceIds,
      tmdbReadAccessToken: tmdbReadAccessToken ?? this.tmdbReadAccessToken,
      playbackOpenTimeoutSeconds:
          playbackOpenTimeoutSeconds ?? this.playbackOpenTimeoutSeconds,
      playbackDefaultSpeed: playbackDefaultSpeed == null
          ? this.playbackDefaultSpeed
          : playbackDefaultSpeed.clamp(0.75, 2.0),
      playbackSubtitlePreference:
          playbackSubtitlePreference ?? this.playbackSubtitlePreference,
      playbackDefaultSubtitle:
          playbackDefaultSubtitle ?? this.playbackDefaultSubtitle,
      playbackDualSubtitlePrimaryLanguage:
          playbackDualSubtitlePrimaryLanguage ??
              this.playbackDualSubtitlePrimaryLanguage,
      playbackDualSubtitleSecondaryLanguage:
          playbackDualSubtitleSecondaryLanguage ??
              this.playbackDualSubtitleSecondaryLanguage,
      playbackSubtitleScale: playbackSubtitleScale == null
          ? this.playbackSubtitleScale
          : clampPlaybackSubtitleScale(playbackSubtitleScale),
      playbackPrimarySubtitlePosition: playbackPrimarySubtitlePosition == null
          ? this.playbackPrimarySubtitlePosition
          : clampPlaybackSubtitlePosition(playbackPrimarySubtitlePosition),
      playbackSecondarySubtitlePosition:
          playbackSecondarySubtitlePosition == null
              ? this.playbackSecondarySubtitlePosition
              : clampPlaybackSubtitlePosition(
                  playbackSecondarySubtitlePosition,
                ),
      playbackSecondarySubtitleScale: playbackSecondarySubtitleScale == null
          ? this.playbackSecondarySubtitleScale
          : clampPlaybackSecondarySubtitleScale(
              playbackSecondarySubtitleScale,
            ),
      onlineSubtitleSources:
          onlineSubtitleSources ?? this.onlineSubtitleSources,
      assrtToken: assrtToken ?? this.assrtToken,
      opensubtitlesEnabled: opensubtitlesEnabled ?? this.opensubtitlesEnabled,
      opensubtitlesUsername:
          opensubtitlesUsername ?? this.opensubtitlesUsername,
      opensubtitlesPassword:
          opensubtitlesPassword ?? this.opensubtitlesPassword,
      subdlEnabled: subdlEnabled ?? this.subdlEnabled,
      subdlApiKey: subdlApiKey ?? this.subdlApiKey,
      subtitlePreferredLanguages:
          subtitlePreferredLanguages ?? this.subtitlePreferredLanguages,
      subtitleSearchMaxValidatedCandidates:
          subtitleSearchMaxValidatedCandidates == null
              ? this.subtitleSearchMaxValidatedCandidates
              : clampSubtitleSearchMaxValidatedCandidates(
                  subtitleSearchMaxValidatedCandidates,
                ),
      playbackBackgroundPlaybackEnabled: playbackBackgroundPlaybackEnabled ??
          this.playbackBackgroundPlaybackEnabled,
      playbackEngine: playbackEngine ?? this.playbackEngine,
      playbackDecodeMode: playbackDecodeMode ?? this.playbackDecodeMode,
      nativeAudioOutputMode:
          nativeAudioOutputMode ?? this.nativeAudioOutputMode,
      playbackMpvQualityPreset:
          playbackMpvQualityPreset ?? this.playbackMpvQualityPreset,
      playbackMpvDoubleTapToSeekEnabled: playbackMpvDoubleTapToSeekEnabled ??
          this.playbackMpvDoubleTapToSeekEnabled,
      playbackMpvSwipeToSeekEnabled:
          playbackMpvSwipeToSeekEnabled ?? this.playbackMpvSwipeToSeekEnabled,
      playbackMpvLongPressSpeedBoostEnabled:
          playbackMpvLongPressSpeedBoostEnabled ??
              this.playbackMpvLongPressSpeedBoostEnabled,
      playbackMpvStallAutoRecoveryEnabled:
          playbackMpvStallAutoRecoveryEnabled ??
              this.playbackMpvStallAutoRecoveryEnabled,
      localLoggingEnabled: localLoggingEnabled ?? this.localLoggingEnabled,
      localLogMaxSizeMb: localLogMaxSizeMb == null
          ? this.localLogMaxSizeMb
          : normalizeLocalLogMaxSizeMb(localLogMaxSizeMb),
      localLogRecordedLevels:
          localLogRecordedLevels ?? this.localLogRecordedLevels,
      localLogVisibleLevels:
          localLogVisibleLevels ?? this.localLogVisibleLevels,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': kAppSettingsSchemaVersion,
      'mediaSources': mediaSources.map((item) => item.toJson()).toList(),
      'searchProviders': searchProviders.map((item) => item.toJson()).toList(),
      'doubanAccount': doubanAccount.toJson(),
      'homeModules': homeModules.map((item) => item.toJson()).toList(),
      'networkStorage': networkStorage.toJson(),
      'homeHeroSourceModuleId': homeHeroSourceModuleId,
      'homeHeroDisplayMode': homeHeroDisplayMode.name,
      'homeHeroStyle': homeHeroStyle.name,
      'homeHeroLogoTitleEnabled': homeHeroLogoTitleEnabled,
      'homeHeroBackgroundEnabled': homeHeroBackgroundEnabled,
      'homeStartupAutoRefreshEnabled': homeStartupAutoRefreshEnabled,
      'homeStartupAutoRefreshEmbyEnabled': homeStartupAutoRefreshEmbyEnabled,
      'homeNavigationSingleTapCleanupEnabled':
          homeNavigationSingleTapCleanupEnabled,
      'translucentEffectsEnabled': translucentEffectsEnabled,
      'autoHideNavigationBarEnabled': autoHideNavigationBarEnabled,
      'navigationDestinationIds': navigationDestinationIds,
      'performanceReduceDecorationsEnabled':
          performanceReduceDecorationsEnabled,
      'performanceReduceMotionEnabled': performanceReduceMotionEnabled,
      'performanceStaticNavigationEnabled': performanceStaticNavigationEnabled,
      'performanceStaticHomeHeroEnabled': performanceStaticHomeHeroEnabled,
      'performanceLightweightHomeHeroEnabled':
          performanceLightweightHomeHeroEnabled,
      'performanceLiveItemHeroOverlayEnabled':
          performanceLiveItemHeroOverlayEnabled,
      'performanceAggressivePlaybackTuningEnabled':
          performanceAggressivePlaybackTuningEnabled,
      'taskMaxConcurrency': taskMaxConcurrency,
      'metadataPrefetchInitialBatchSize': metadataPrefetchInitialBatchSize,
      'metadataPrefetchBatchDelayMs': metadataPrefetchBatchDelayMs,
      'metadataPrefetchForegroundResumeDelayMs':
          metadataPrefetchForegroundResumeDelayMs,
      'homeFeedInitialBatchSize': homeFeedInitialBatchSize,
      'homeFeedBatchDelayMs': homeFeedBatchDelayMs,
      'tmdbMetadataMatchEnabled': tmdbMetadataMatchEnabled,
      'wmdbMetadataMatchEnabled': wmdbMetadataMatchEnabled,
      'metadataMatchPriority': metadataMatchPriority.name,
      'imdbRatingMatchEnabled': imdbRatingMatchEnabled,
      'detailAutoLibraryMatchEnabled': detailAutoLibraryMatchEnabled,
      'libraryMatchSourceIds': libraryMatchSourceIds,
      'searchSourceIds': searchSourceIds,
      'tmdbReadAccessToken': tmdbReadAccessToken,
      'playbackOpenTimeoutSeconds': playbackOpenTimeoutSeconds,
      'playbackDefaultSpeed': playbackDefaultSpeed,
      'playbackSubtitlePreference': playbackSubtitlePreference.name,
      'playbackDefaultSubtitle': playbackDefaultSubtitle.name,
      'playbackDualSubtitlePrimaryLanguage':
          playbackDualSubtitlePrimaryLanguage.name,
      'playbackDualSubtitleSecondaryLanguage':
          playbackDualSubtitleSecondaryLanguage.name,
      'playbackSubtitleScale': playbackSubtitleScale,
      'playbackPrimarySubtitlePosition': playbackPrimarySubtitlePosition,
      'playbackSecondarySubtitlePosition': playbackSecondarySubtitlePosition,
      'playbackSecondarySubtitleScale': playbackSecondarySubtitleScale,
      'playbackSubtitleStyleDefaultsVersion':
          kPlaybackSubtitleStyleDefaultsVersion,
      'onlineSubtitleSources':
          onlineSubtitleSources.map((item) => item.name).toList(),
      'assrtToken': assrtToken,
      'opensubtitlesEnabled': opensubtitlesEnabled,
      'opensubtitlesUsername': opensubtitlesUsername,
      'opensubtitlesPassword': opensubtitlesPassword,
      'subdlEnabled': subdlEnabled,
      'subdlApiKey': subdlApiKey,
      'subtitlePreferredLanguages': subtitlePreferredLanguages,
      'subtitleSearchMaxValidatedCandidates':
          subtitleSearchMaxValidatedCandidates,
      'playbackBackgroundPlaybackEnabled': playbackBackgroundPlaybackEnabled,
      'playbackEngine': playbackEngine.name,
      'playbackDecodeMode': playbackDecodeMode.name,
      'nativeAudioOutputMode': nativeAudioOutputMode.name,
      'playbackMpvQualityPreset': playbackMpvQualityPreset.name,
      'playbackMpvDoubleTapToSeekEnabled': playbackMpvDoubleTapToSeekEnabled,
      'playbackMpvSwipeToSeekEnabled': playbackMpvSwipeToSeekEnabled,
      'playbackMpvLongPressSpeedBoostEnabled':
          playbackMpvLongPressSpeedBoostEnabled,
      'playbackMpvStallAutoRecoveryEnabled':
          playbackMpvStallAutoRecoveryEnabled,
      'localLoggingEnabled': localLoggingEnabled,
      'localLogMaxSizeMb': localLogMaxSizeMb,
      'localLogRecordedLevels': AppLogLevel.values
          .where(localLogRecordedLevels.contains)
          .map((level) => level.name)
          .toList(growable: false),
      'localLogVisibleLevels': AppLogLevel.values
          .where(localLogVisibleLevels.contains)
          .map((level) => level.name)
          .toList(growable: false),
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final rawHomeHeroStyle = (json['homeHeroStyle'] as String? ?? '').trim();
    final rawHomeModules = (json['homeModules'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              HomeModuleConfig.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    return AppSettings(
      mediaSources: (json['mediaSources'] as List<dynamic>? ?? [])
          .map(
            (item) => MediaSourceConfig.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      searchProviders: (json['searchProviders'] as List<dynamic>? ?? [])
          .map(
            (item) => SearchProviderConfig.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      doubanAccount: DoubanAccountConfig.fromJson(
        Map<String, dynamic>.from((json['doubanAccount'] as Map?) ?? const {}),
      ),
      homeModules: _normalizeHomeModules(rawHomeModules),
      networkStorage: NetworkStorageConfig.fromJson(
        Map<String, dynamic>.from((json['networkStorage'] as Map?) ?? const {}),
      ),
      homeHeroSourceModuleId: json['homeHeroSourceModuleId'] as String? ?? '',
      homeHeroDisplayMode: HomeHeroDisplayModeX.fromName(
        json['homeHeroDisplayMode'] as String? ?? '',
      ),
      homeHeroStyle: _parseHomeHeroStyle(rawHomeHeroStyle),
      homeHeroLogoTitleEnabled:
          json['homeHeroLogoTitleEnabled'] as bool? ?? false,
      homeHeroBackgroundEnabled:
          json['homeHeroBackgroundEnabled'] as bool? ?? true,
      homeStartupAutoRefreshEnabled:
          json['homeStartupAutoRefreshEnabled'] as bool? ?? true,
      homeStartupAutoRefreshEmbyEnabled:
          json['homeStartupAutoRefreshEmbyEnabled'] as bool?,
      homeNavigationSingleTapCleanupEnabled:
          json['homeNavigationSingleTapCleanupEnabled'] as bool? ?? true,
      translucentEffectsEnabled:
          json['translucentEffectsEnabled'] as bool? ?? true,
      autoHideNavigationBarEnabled:
          json['autoHideNavigationBarEnabled'] as bool? ?? true,
      navigationDestinationIds: json.containsKey('navigationDestinationIds')
          ? normalizeNavigationDestinationIds(
              _parseNormalizedStringList(json['navigationDestinationIds']),
            )
          : kDefaultNavigationDestinationIds,
      performanceReduceDecorationsEnabled:
          json['performanceReduceDecorationsEnabled'] as bool? ?? false,
      performanceReduceMotionEnabled:
          json['performanceReduceMotionEnabled'] as bool? ?? false,
      performanceStaticNavigationEnabled:
          json['performanceStaticNavigationEnabled'] as bool? ?? false,
      performanceStaticHomeHeroEnabled:
          json['performanceStaticHomeHeroEnabled'] as bool? ?? false,
      performanceLightweightHomeHeroEnabled:
          json['performanceLightweightHomeHeroEnabled'] as bool? ?? false,
      performanceLiveItemHeroOverlayEnabled:
          json['performanceLiveItemHeroOverlayEnabled'] as bool? ?? true,
      performanceAggressivePlaybackTuningEnabled:
          json['performanceAggressivePlaybackTuningEnabled'] as bool? ?? false,
      taskMaxConcurrency: clampTaskMaxConcurrency(
        (json['taskMaxConcurrency'] as num?)?.toInt() ??
            kTaskMaxConcurrencyDefault,
      ),
      metadataPrefetchInitialBatchSize: clampMetadataPrefetchInitialBatchSize(
        (json['metadataPrefetchInitialBatchSize'] as num?)?.toInt() ??
            kMetadataPrefetchInitialBatchSizeDefault,
      ),
      metadataPrefetchBatchDelayMs: clampMetadataPrefetchBatchDelayMs(
        (json['metadataPrefetchBatchDelayMs'] as num?)?.toInt() ??
            kMetadataPrefetchBatchDelayMsDefault,
      ),
      metadataPrefetchForegroundResumeDelayMs:
          clampMetadataPrefetchForegroundResumeDelayMs(
        (json['metadataPrefetchForegroundResumeDelayMs'] as num?)?.toInt() ??
            kMetadataPrefetchForegroundResumeDelayMsDefault,
      ),
      homeFeedInitialBatchSize: clampHomeFeedInitialBatchSize(
        (json['homeFeedInitialBatchSize'] as num?)?.toInt() ??
            kHomeFeedInitialBatchSizeDefault,
      ),
      homeFeedBatchDelayMs: clampHomeFeedBatchDelayMs(
        (json['homeFeedBatchDelayMs'] as num?)?.toInt() ??
            kHomeFeedBatchDelayMsDefault,
      ),
      tmdbMetadataMatchEnabled:
          json['tmdbMetadataMatchEnabled'] as bool? ?? false,
      wmdbMetadataMatchEnabled:
          json['wmdbMetadataMatchEnabled'] as bool? ?? false,
      metadataMatchPriority: MetadataMatchProviderX.fromName(
        json['metadataMatchPriority'] as String? ?? '',
      ),
      imdbRatingMatchEnabled: json['imdbRatingMatchEnabled'] as bool? ?? false,
      detailAutoLibraryMatchEnabled:
          json['detailAutoLibraryMatchEnabled'] as bool? ?? false,
      libraryMatchSourceIds: _parseNormalizedStringList(
        json['libraryMatchSourceIds'],
      ),
      searchSourceIds: _parseNormalizedStringList(json['searchSourceIds']),
      tmdbReadAccessToken: json['tmdbReadAccessToken'] as String? ?? '',
      playbackOpenTimeoutSeconds:
          ((json['playbackOpenTimeoutSeconds'] as num?)?.toInt() ?? 20).clamp(
        1,
        600,
      ),
      playbackDefaultSpeed:
          ((json['playbackDefaultSpeed'] as num?)?.toDouble() ?? 1.0).clamp(
        0.75,
        2.0,
      ),
      playbackSubtitlePreference: PlaybackSubtitlePreferenceX.fromName(
        json['playbackSubtitlePreference'] as String? ?? '',
      ),
      playbackDefaultSubtitle: PlaybackDefaultSubtitleX.fromName(
        json['playbackDefaultSubtitle'] as String? ?? '',
      ),
      playbackDualSubtitlePrimaryLanguage: PlaybackSubtitleLanguageX.fromName(
        json['playbackDualSubtitlePrimaryLanguage'] as String? ?? '',
        fallback: PlaybackSubtitleLanguage.simplifiedChinese,
      ),
      playbackDualSubtitleSecondaryLanguage: PlaybackSubtitleLanguageX.fromName(
        json['playbackDualSubtitleSecondaryLanguage'] as String? ?? '',
        fallback: PlaybackSubtitleLanguage.english,
      ),
      playbackSubtitleScale: parsePlaybackSubtitleScale(
        json['playbackSubtitleScale'],
      ),
      playbackPrimarySubtitlePosition: parsePlaybackSubtitlePosition(
        json['playbackPrimarySubtitlePosition'],
        kPlaybackPrimarySubtitlePositionDefault,
      ),
      playbackSecondarySubtitlePosition: parsePlaybackSubtitlePosition(
        json['playbackSecondarySubtitlePosition'],
        kPlaybackSecondarySubtitlePositionDefault,
      ),
      playbackSecondarySubtitleScale: _parseSecondarySubtitleScale(json),
      onlineSubtitleSources: _parseOnlineSubtitleSources(
        json['onlineSubtitleSources'],
      ),
      assrtToken: json['assrtToken'] as String? ?? '',
      opensubtitlesEnabled: json['opensubtitlesEnabled'] as bool? ?? false,
      opensubtitlesUsername: json['opensubtitlesUsername'] as String? ?? '',
      opensubtitlesPassword: json['opensubtitlesPassword'] as String? ?? '',
      subdlEnabled: json['subdlEnabled'] as bool? ?? false,
      subdlApiKey: json['subdlApiKey'] as String? ?? '',
      subtitlePreferredLanguages: parseSubtitlePreferredLanguages(
        json['subtitlePreferredLanguages'],
      ),
      subtitleSearchMaxValidatedCandidates:
          clampSubtitleSearchMaxValidatedCandidates(
        (json['subtitleSearchMaxValidatedCandidates'] as num?)?.toInt() ??
            kSubtitleSearchMaxValidatedCandidatesDefault,
      ),
      playbackBackgroundPlaybackEnabled:
          json['playbackBackgroundPlaybackEnabled'] as bool? ?? true,
      playbackEngine: PlaybackEngineX.fromName(
        json['playbackEngine'] as String? ?? '',
      ),
      playbackDecodeMode: PlaybackDecodeModeX.fromName(
        json['playbackDecodeMode'] as String? ?? '',
      ),
      nativeAudioOutputMode: NativeAudioOutputModeX.fromName(
        json['nativeAudioOutputMode'] as String? ?? '',
      ),
      playbackMpvQualityPreset: PlaybackMpvQualityPresetX.fromName(
        json['playbackMpvQualityPreset'] as String? ?? 'performanceFirst',
      ),
      playbackMpvDoubleTapToSeekEnabled:
          json['playbackMpvDoubleTapToSeekEnabled'] as bool? ?? true,
      playbackMpvSwipeToSeekEnabled:
          json['playbackMpvSwipeToSeekEnabled'] as bool? ?? true,
      playbackMpvLongPressSpeedBoostEnabled:
          json['playbackMpvLongPressSpeedBoostEnabled'] as bool? ?? true,
      playbackMpvStallAutoRecoveryEnabled:
          json['playbackMpvStallAutoRecoveryEnabled'] as bool? ?? true,
      localLoggingEnabled: json['localLoggingEnabled'] as bool? ?? true,
      localLogMaxSizeMb: normalizeLocalLogMaxSizeMb(
        (json['localLogMaxSizeMb'] as num?)?.toInt() ??
            kLocalLogMaxSizeMbDefault,
      ),
      localLogRecordedLevels: parseLocalLogLevels(
        json['localLogRecordedLevels'],
        fallback: kDefaultLocalLogRecordedLevels,
      ),
      localLogVisibleLevels: parseLocalLogLevels(
        json['localLogVisibleLevels'],
        fallback: kDefaultLocalLogVisibleLevels,
      ),
    );
  }

  factory AppSettings.fromCurrentJson(Map<String, dynamic> json) {
    final schemaVersion = (json['schemaVersion'] as num?)?.toInt();
    if (schemaVersion != kAppSettingsSchemaVersion) {
      throw FormatException(
        '不支持的设置格式：需要 schemaVersion '
        '$kAppSettingsSchemaVersion，实际为 ${schemaVersion ?? '未提供'}。',
      );
    }
    return AppSettings.fromJson(json);
  }
}

double _parseSecondarySubtitleScale(Map<String, dynamic> json) {
  final version =
      (json['playbackSubtitleStyleDefaultsVersion'] as num?)?.toInt() ?? 0;
  final raw = (json['playbackSecondarySubtitleScale'] as num?)?.toDouble() ??
      kPlaybackSecondarySubtitleScaleDefault;
  if (version < kPlaybackSubtitleStyleDefaultsVersion && raw == 75.0) {
    return kPlaybackSecondarySubtitleScaleDefault;
  }
  return clampPlaybackSecondarySubtitleScale(raw);
}

extension AppSettingsPerformanceX on AppSettings {
  AppSettings applyStartupCrashRecoveryPreset() {
    return copyWith(
      translucentEffectsEnabled: false,
      autoHideNavigationBarEnabled: false,
      homeHeroBackgroundEnabled: false,
      performanceReduceDecorationsEnabled: true,
      performanceReduceMotionEnabled: true,
      performanceStaticNavigationEnabled: true,
      performanceStaticHomeHeroEnabled: true,
      performanceLightweightHomeHeroEnabled: true,
      performanceLiveItemHeroOverlayEnabled: false,
      performanceAggressivePlaybackTuningEnabled: true,
      homeStartupAutoRefreshEnabled: false,
      homeStartupAutoRefreshEmbyEnabled: false,
      playbackBackgroundPlaybackEnabled: false,
      playbackMpvQualityPreset: PlaybackMpvQualityPreset.performanceFirst,
      playbackMpvDoubleTapToSeekEnabled: false,
      playbackMpvSwipeToSeekEnabled: false,
      playbackMpvLongPressSpeedBoostEnabled: false,
      playbackMpvStallAutoRecoveryEnabled: false,
    );
  }

  bool get effectiveReduceMotionEnabled {
    return performanceReduceMotionEnabled;
  }

  bool get effectiveStaticNavigationEnabled {
    return performanceStaticNavigationEnabled;
  }

  bool get effectiveNavigationAnimationEnabled {
    return !effectiveStaticNavigationEnabled && !effectiveReduceMotionEnabled;
  }

  bool get effectiveTranslucentEffectsEnabled {
    return translucentEffectsEnabled;
  }

  bool get effectiveNavigationAutoHideEnabled {
    return autoHideNavigationBarEnabled;
  }

  bool effectivePerformanceLiveItemHeroOverlayEnabled({
    required bool? isTelevision,
  }) {
    if (isTelevision != false) {
      return false;
    }
    return performanceLiveItemHeroOverlayEnabled;
  }

  bool effectiveBackgroundPlaybackEnabled({required bool? isTelevision}) {
    if (isTelevision != false) {
      return false;
    }
    return playbackBackgroundPlaybackEnabled;
  }

  bool effectiveHomeStartupAutoRefreshEmbyEnabled({
    required bool isTelevision,
  }) {
    if (!homeStartupAutoRefreshEnabled) {
      return false;
    }
    final stored = homeStartupAutoRefreshEmbyEnabled;
    if (stored != null) {
      return stored;
    }
    // Platform default: TV off, others on.
    return !isTelevision;
  }

  bool effectiveLeanPlaybackUiEnabled({required bool isTelevision}) {
    return isTelevision;
  }

  bool effectiveLightweightHomeHeroEnabled({required bool isTelevision}) {
    return performanceLightweightHomeHeroEnabled;
  }

  bool effectiveSlimDetailHeroEnabled({required bool isTelevision}) {
    return isTelevision;
  }

  bool effectiveLightweightTvFocusEnabled({required bool isTelevision}) {
    return isTelevision;
  }

  bool get effectiveFullscreenRouteAnimationEnabled {
    return !effectiveReduceMotionEnabled;
  }
}

extension AppSettingsSubtitleSearchX on AppSettings {
  bool get assrtApiSearchEnabled =>
      onlineSubtitleSources.contains(OnlineSubtitleSource.assrt) &&
      assrtToken.trim().isNotEmpty;

  bool get opensubtitlesSearchEnabled =>
      opensubtitlesEnabled &&
      opensubtitlesUsername.trim().isNotEmpty &&
      opensubtitlesPassword.trim().isNotEmpty;

  bool get subdlSearchEnabled => subdlEnabled && subdlApiKey.trim().isNotEmpty;

  List<OnlineSubtitleSource> get configuredStructuredSubtitleSources {
    final sources = <OnlineSubtitleSource>[
      if (assrtApiSearchEnabled) OnlineSubtitleSource.assrt,
      if (opensubtitlesSearchEnabled) OnlineSubtitleSource.opensubtitles,
      if (subdlSearchEnabled) OnlineSubtitleSource.subdl,
    ];
    return sources.toSet().toList(growable: false);
  }

  List<OnlineSubtitleSource> get effectiveOnlineSubtitleSources {
    return configuredStructuredSubtitleSources;
  }
}

HomeHeroStyle _parseHomeHeroStyle(String raw) {
  return switch (raw) {
    'poster' => HomeHeroStyle.poster,
    'composite' => HomeHeroStyle.composite,
    _ => HomeHeroStyle.composite,
  };
}

List<String> _parseNormalizedStringList(Object? raw) {
  return (raw as List<dynamic>? ?? const <dynamic>[])
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

List<OnlineSubtitleSource> _parseOnlineSubtitleSources(Object? raw) {
  final sources = (raw as List<dynamic>? ?? const <dynamic>[])
      .whereType<String>()
      .map(OnlineSubtitleSourceX.fromName)
      .toSet()
      .toList(growable: false);
  return sources.isEmpty ? const [OnlineSubtitleSource.assrt] : sources;
}

String searchSourceSettingIdForMediaSource(String sourceId) {
  return 'source:${sourceId.trim()}';
}

String searchSourceSettingIdForProvider(String providerId) {
  return 'provider:${providerId.trim()}';
}

List<HomeModuleConfig> _normalizeHomeModules(List<HomeModuleConfig> modules) {
  final normalized = <HomeModuleConfig>[];
  HomeModuleConfig? heroModule;

  for (final module in modules) {
    if (module.type == HomeModuleType.hero ||
        module.id == HomeModuleConfig.heroModuleId) {
      heroModule = module.copyWith(
        id: HomeModuleConfig.heroModuleId,
        type: HomeModuleType.hero,
      );
      continue;
    }
    normalized.add(module);
  }

  normalized.insert(
    0,
    heroModule ?? HomeModuleConfig.hero(enabled: true),
  );
  return normalized;
}
