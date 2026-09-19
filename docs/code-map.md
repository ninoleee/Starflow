# Starflow 代码地图

核对日期：2026-09-20。本地图按当前工作区（含既有未提交代码）整理入口、职责、调用链及测试位置，不是逐行缺陷审计或所有平台验收报告。组件设计以 [architecture.md](architecture.md) 为准，用户能力与发布流程见 [README](../README.md)。

## 推荐阅读顺序

本轮规则统一入口：`details/domain/cached_metadata.dart`（展示缓存）、`cached_artwork.dart`（图片及鉴权配对）、`library/data/nfo_metadata.dart`（NFO）、`search/application/cloud_save_postprocessing.dart`（转存后处理）、`library/presentation/library_resource_deletion.dart`（删除交互）。播放记忆使用 `playback_memory_repository.dart` 的写入队列，以及 Dart / Kotlin / Swift 的 memory policy；共享 fixture 为 `test/fixtures/playback_memory_contract.json`，Swift runner 为 `scripts/test_playback_memory_contract.swift`。发布版本由 `tool/release_version.dart` 和 `config/release_version.json` 管理，不能为只读检查运行递增工具。

1. `lib/main.dart`、`lib/app/app.dart`、启动控制器：理解初始化顺序和 provider 容器。
2. `lib/app/router/`、`shell_layout.dart`：理解壳路由、导航和页面活动状态。
3. `lib/features/settings/domain/app_settings.dart`、settings slices：确定默认值与依赖粒度。
4. 沿具体业务的 presentation → application → data / domain 阅读，不按文件行数判断组件边界。
5. 涉及播放时同时检查 Dart resolver、平台通道及 Android / iOS 实现；最后对照对应测试和生成策略。

## 仓库分区

| 路径 | 用途与维护边界 |
| --- | --- |
| `lib/` | Flutter 业务、公共基础层及平台桥接；`*_io / *_web / *_stub` 不代表能力完全一致 |
| `android/` | Android / TV 宿主、Media3 原生播放器、资源、Gradle 配置和 JVM 测试 |
| `ios/` | iOS 宿主、AVPlayer、音频 / 系统媒体会话、CocoaPods 和资源 |
| `macos/`、`windows/`、`linux/` | 桌面宿主与构建配置；Windows 另含 Inno Setup 安装器 |
| `web/` | 浏览器入口、manifest 和图标；媒体后端受浏览器能力限制 |
| `packages/` | Android / iOS full libmpv 依赖覆盖，公共插件身份不变，不是业务仓库副本 |
| `config/` | 播放可靠性策略与跨发布脚本 / Gradle 的数字版本码策略 |
| `assets/` | 品牌资源、bootstrap 目录和本地性能样本；嵌入设置只由显式发布参数临时写入 |
| `scripts/` | 发布、环境准备、依赖重建及平台检查；部分脚本修改版本和构建目录 |
| `tool/` | 代码生成、主机计时、Web 开发代理与手动诊断 |
| `test/` | Dart 单元 / 组件 / smoke 测试及跨语言 fixture |
| `docs/` | 当前架构、网络、主机 / 真机性能、字幕与带日期的审查记录；HTML 是品牌设计素材 |
| `backups/branding/`、`icons/` | 品牌历史说明与设计原图，不是应用运行数据 |
| `pubspec.yaml / pubspec.lock` | 版本、依赖、插件覆盖和资源；自动发布会改版本 |
| `analysis_options.yaml`、`devtools_options.yaml` | 静态检查和开发工具设置 |

`build/`、`.dart_tool/`、Pods、插件二进制缓存和本机日志是生成物或诊断产物，不作为手工维护源码。不要为了更新说明而运行会清理缓存或递增版本的发布脚本。

## 启动、路由与公共层

| 入口 | 职责 |
| --- | --- |
| `lib/main.dart` | 初始设置、代理、结构化日志、错误钩子、帧监测、启动标记、MediaKit 初始化及 ProviderScope；关闭 Riverpod 自动重试 |
| `features/bootstrap/application/bootstrap_controller.dart` | 配置 / 缓存 / 首页启动编排与 10s 总截止时间；不覆盖此前初始化或同步阻塞 |
| `features/bootstrap/application/startup_crash_recovery.dart` | 启动标记及异常启动恢复，不代替原生崩溃日志 |
| `app/router/app_routes.dart`、`app_router.dart`、`app_navigator.dart` | 壳页和详情、人物、播放器、设置、搜索等附加路由 |
| `app/router/app_navigation_shell.dart`、`app/shell_layout.dart` | home / search / favorites / library / settings 五个壳路由，默认隐藏收藏，菜单可配置 |
| `app/lifecycle/app_runtime_recovery_boundary.dart` | 后台、前台、低内存和退出弹窗的调度准入租约 |
| `core/navigation/` | `PageActivityMixin` 和 RetainedAsync 控制器，暂停工作但保留稳定页面结果 |
| `core/network/` | 共享 HTTP、IO 代理、Web 转发、失败分类、超时与按主机熔断；详见网络文档 |
| `core/logging/` | IO 本地日志、轮转、脱敏、帧告警；Web 是文件日志 stub |
| `core/storage/` | 偏好存储、URL + headers 图片缓存、资源路径身份及本地存储模型 |
| `core/platform/` | TV 检测、系统退出、后台播放、媒体会话及 Android PiP 通道 |
| `core/scheduling/queue_wait_diagnostics.dart` | 队列等待诊断，不自行执行网络请求 |
| `core/state/riverpod_retry.dart` | provider 重试策略 |
| `core/widgets/` | TV 焦点、图片并发门、海报、对话框、横向翻页、Logo 等共享 UI |
| `core/utils/` | 文本、评分、图片 headers、默认 seed；旧 trace helper 静音但结构化日志活跃 |

本节路径除 `lib/main.dart` 外相对于 `lib/`。`SeedData` 提供默认配置，不应将已经接入真实数据的仓库称为 mock 仓库。

## 十个业务模块

以下路径相对于 `lib/features/`。

| 模块 | 主要入口 | 职责与下游 |
| --- | --- | --- |
| `bootstrap` | `application/bootstrap_controller.dart`、`presentation/bootstrap_page.dart` | 启动阶段与超时兜底，调用设置、缓存和首页 |
| `home` | `application/home_controller.dart`、`home_feed_repository.dart`、`home_controller_models.dart` | 来源 seed 与本地详情装饰分离；独立首页调度、Hero 预取、元数据刷新及 settings slices；页面拆成 home / hero / sections |
| `discovery` | `data/discovery_repository.dart`、`douban_api_client.dart`、`douban_network_guard.dart` | 豆瓣列表与详情数据，提供给首页 / 详情；不单独占一个默认主导航 tab |
| `library` | `data/media_repository.dart`、`application/app_media_query_service.dart` | AppMediaRepository 管刷新 / 删除，query service 管读；media_server_client 协调 Emby / 飞牛，NAS 索引覆盖 WebDAV / 夸克 |
| `details` | `application/detail_page_controller.dart`、`detail_target_resolver.dart`、`detail_metadata_service.dart` | 详情恢复、统一元数据执行、本地匹配、评分预取、版本选择与从头播放；季集 UI 按目标懒加载 |
| `metadata` | `data/metadata_match_resolver.dart`、`wmdb_metadata_client.dart`、`tmdb_metadata_client.dart` | WMDB / TMDB 匹配、结果复用、网络 guard 与共享限流；IMDb 客户端文件存在不等于已进入默认自动评分链 |
| `playback` | `application/playback_startup_coordinator.dart`、`presentation/player_page.dart` | 启动、路由、播放会话、可靠性、字幕、播放记忆及平台适配 |
| `search` | `data/search_repository.dart`、`presentation/search_page.dart` | PanSou / CloudSaver / 本地来源搜索、分享验证、收藏及网盘保存工作流 |
| `settings` | `application/settings_controller.dart`、`settings_slice_providers.dart`、`domain/app_settings.dart` | 配置模型、窄字段保存、来源生命周期、自动保存、导入导出、日志、代理与 WebDAV 同步 |
| `storage` | `data/local_storage_cache_repository.dart`、`application/local_storage_cache_revision.dart` | 本地详情及媒体服务器分片缓存、统计与清理，revision 驱动本地派生刷新 |

`library/data/mock_media_repository.dart`、`discovery/data/mock_discovery_repository.dart`、`search/data/mock_search_repository.dart` 已由正式命名文件取代，排障和新测试不要继续引用旧路径。

## 关键调用链

### 首页与详情

```text
HomePage -> HomePageController -> HomeFeedRepository -> 来源 / 豆瓣 seed
                                                   -> 批量详情缓存装饰
MediaDetailPage -> DetailPageController -> DetailTargetResolver
                                       -> resolveDetailMetadata
                                       -> 本地匹配 / 评分 / 季集 / 版本
```

详情缓存 revision 只驱动装饰层本地重算，不应重新抓取整轮首页来源。详情被播放器覆盖时保留剧集组件、季选择和滚动，活动状态控制订阅及新增任务。

### 媒体库与存储

```text
AppMediaRepository -> AppMediaQueryService -> MediaServerClient / 本地索引
                   -> MediaRefreshCoordinator -> 来源刷新 / NAS enrichment
                   -> WebDAV 删除确认 -> 可选网盘同步删除 -> 本地失效
```

- Emby / 飞牛使用媒体服务器缓存分片；根列表读取最多 400 条 summary，分区只读目标 shard，完整匹配最多两路解码。
- NAS 索引由 `nas_media_indexer.dart` 及 `refresh_flow / storage_access / indexing / grouping / refresh_support` 的 `part` 文件共同实现；这些不是彼此独立的服务。
- `nas_media_index_store_impl_io.dart` 使用 Sembast；Web 有单独实现。当前 schema 是 `webdav-v14`，支持分区过滤与 upsert / patch，不再只做整库覆盖。
- `webdav_nas_client.dart` 的 structure / sidecar / background 文件也是同一 Dart library。普通页面优先读索引，不实时扫全目录。
- `resource_path_identity.dart` 与 `media_source_identity.dart` 分别处理资源路径和来源身份；不要因元数据身份相同复用不同资源的直链或鉴权头。
- `library/data/nfo_metadata.dart` 共享 WebDAV / 夸克 XML 字段解析，`details/domain/cached_artwork.dart` 共享图片 URL 与 headers 配对合并；`library/presentation/library_resource_deletion.dart` 复用两级媒体库页面的删除确认。
- 详情缓存按下一次 microtask flush 前的队列批量写入，不是固定 16ms 窗口；相同编码内容跳过重复持久化。这是本地优化，不改变服务器请求协议。

### 搜索、转存与收藏

```text
SearchRepository -> 多来源搜索 -> 分享去重 / 验证 -> SearchPage
用户确认保存 -> QuarkSaveWorkflowService / Cloud115SaveWorkflowService
             -> CloudSavePlanner -> 可选名称清理 -> SmartStrmWebhookClient
             -> MediaRefreshCoordinator
```

公共规划器负责目录复用、单层展开、递归去重和新增范围；协议客户端只负责各自 API。`CloudSavedNameSanitizer` 仅处理本次新增内容，不能为改名扫描并改写旧内容。115 Cookie 不进入配置 JSON，也不是已接入的直连媒体源。

`cloud_save_postprocessing.dart` 共享 STRM 触发、延迟规范化和保存后刷新失败反馈。来源修改 / 导入时，settings 层通过公共来源路径规则协调夸克与 115 监听目录，删除来源时清理两者引用；不因此放宽实际同步删除的匹配范围。

收藏由 `search_preferences_repository.dart` 持久化，`favorite_auto_sync.dart` 控制可选同步触发，`favorite_sync_document / favorite_sync_payload` 定义版本与精简传输，`settings/data/webdav_sync_service.dart` 负责 WebDAV IO。手动配置快照与每设备收藏文件是不同协议，收藏没有启动定时同步或轮询。

### 播放与字幕

```text
PlaybackStartupCoordinator -> 本地续播 / 跳过准备
                           -> PlaybackTargetResolver
                           -> PlaybackEngineRouter -> PlaybackStartupExecutor
                             -> Flutter PlayerPage / 原生容器 / 外部播放器
```

- `player_page.dart` 是页面壳；`presentation/widgets/player_page_*.part.dart` 共享该 library 的状态，分别承载 MPV 启动、调参、恢复、控制、系统会话、运行动作和性能采集。
- 非 TV 控件基于 media_kit Adaptive Material / MaterialDesktop，TV 使用专用遥控层；Web 的 `embeddedMpv` 枚举值实际路由浏览器后端，不是浏览器里运行 libmpv。
- `playback_engine_support.dart` 是平台选项边界；`native_playback_launcher_io.dart` 桥接 Android Exo / iOS AVPlayer，`system_playback_launcher_io.dart` 负责外部应用 / 系统打开。
- `FntvSessionOwner` 与 `native_fntv_service.dart` 负责转码会话所有权和原生回调，失败 / 迟到的新会话也需释放；Exo 不另写一套 Authx 客户端。
- `playback_episode_browser.dart` 管季集浏览缓存，queue / next-episode 策略只预解析一个目标，不预建第二个播放器。
- `playback_remote_preflight.dart` 保留给原生 SmartStrm 格式探测，不应据文件名推断 MPV 仍执行 Range 启动预检。
- 在线字幕的 provider protocol、IO repository、validation pipeline 与共享 content processing 分工见 [subtitles.md](subtitles.md)；搜索结果不等于已经下载验证。
- `mpv_subtitle_render_binding.dart` 串行合并每个 Player 的字幕可见性属性写入；`player_menu_style.dart` 为播放菜单提供共享半透明主题，不改变解码逻辑。
- `playback_memory_repository.dart` 保存续播、最近播放、跳过规则和剧集字幕偏好；外挂文件仍限定当前集。

## 原生平台

### Android

主要目录：`android/app/src/main/kotlin/com/example/starflow/`。

| 文件组 | 职责 |
| --- | --- |
| `MainActivity`、`StarflowApplication`、`NativeAppLogger` | Flutter 通道、启动及本地日志；系统历史退出信息要求 API 30+ |
| `NativePlaybackActivity / LaunchController / Coordinator / Session` | 原生页面装配、启动及 Exo 生命周期，不把策略都放回 Activity |
| `NativePlaybackSource / Target / Options` | Dart JSON 契约、媒体源与会话设置 |
| `NativePlaybackRuntimeController / RecoveryController` 及各 `*Policy` | tick、启动进展、缓冲、恢复、错误、HLS、TV seek 和焦点规则 |
| `NativePlaybackRenderersFactory / AudioPolicy / AudioTracks` | renderer / sink、实际 MIME 输出策略、音轨身份恢复 |
| `NativePlaybackExtractorsFactory / PcmBluRayReader / PgsReader` | 有证据的 TS 扩展解析、LPCM 转 PCM16、PGS 显示集 |
| `NativeDualSubtitleController / NativeSubtitleOutput / NativeSubtitleContent` | 主副字幕 renderer、过期 UI 更新合并、文本与 cue 处理 |
| `NativeSubtitleParserFactory / BitmapSubtitleLimits / BoundedPgsParser` | PGS / DVB 输入、缓存及像素分配边界；VobSub 的 `BoundedVobsubParser.java` 位于相邻 `src/main/java` 目录 |
| `NativePlaybackExternalSubtitleController / SubtitleFiles / SubtitleStyleController` | 文本外挂、受锁播放副本、偏移、样式与清理 |
| `NativePlaybackTrackController / TrackChoices / SubtitleTrackSelectionPolicy` | 选轨、语言和剧集手动偏好 |
| `NativePlaybackEpisodeController / EpisodePicker / NativeEpisodePickerNavigation` | 换集、跨季浏览、面板与导航 |
| `NativeFntvController / NativeFntvProgressQueue` | Flutter 解析回调、飞牛进度合并与会话切换 |
| `PlaybackSystemSessionManager / NativePlaybackSystemController` | 媒体通知、系统会话、后台和 PiP |
| `NativePlaybackDiagnostics / PerformanceTracker / TransferProgress` | 脱敏诊断、现有传输事件与性能汇总 |

主要通道为 `starflow/platform`、`starflow/native_playback_resolver` 和 `starflow/playback_session`。修改请求 / 回调参数必须同步 Dart、Kotlin、序列化测试和迟到结果处理。

本地 Media3 FFmpeg AAR 与 full MPV 是两套独立原生依赖，见各自 README；Exo 软解能力不能用 MPV codec 列表证明。

### iOS 与桌面

- `ios/Runner/AppDelegate.swift` 承载通道和 AVPlayer 容器；`PlaybackSystemSessionBridge.swift` 管共享音频会话、Now Playing、封面及远程控制。
- `NativePlaybackStartupGate / BufferingTuning / StallRecovery / Metrics` 分别管 AVPlayer 启动、缓冲、卡顿和指标；`NativeSubtitleLanguagePolicy.swift` 与 Dart / Kotlin 共用语言 fixture。
- `ios/Runner/SceneDelegate.swift`、storyboard、Info.plist 和 Xcode 工程属于宿主配置。原生启动页只有深色底，Flutter Logo 是另一层。
- macOS 的 AppDelegate / MainFlutterWindow、Windows runner、Linux runner 主要负责 Flutter 宿主，不能据目录存在推断有 Android 同等原生播放器或后台会话能力。

## 工具与发布

| 入口 | 作用与注意事项 |
| --- | --- |
| `config/playback_policy.json` → `tool/generate_playback_policy.dart` | 生成 Dart `playback_policy_values.dart` 与 Kotlin `PlaybackPolicyValues.kt`；用 `--check` 校验，不手工单改生成值 |
| `config/release_version.json`、`tool/release_version.dart` | 四个发布脚本共用版本递增 / 显式批次值，Gradle 共用 Android 数字版本码策略；工具执行会写 pubspec，不作为只读检查 |
| `scripts/build_tv_apk.ps1` | TV 发布权威预设：release、API 23、ARM 双 ABI、按月版本、规范命名、桌面输出、显式配置嵌入 |
| `scripts/build_tv_apk_to_icloud.sh` | Bash 等价 TV 构建；普通交付用 `ICLOUD_INSTALLER_DIR="$HOME/Desktop"` |
| `scripts/build_ipa_to_icloud.sh` | 清理后构建未签名 IPA，不能直接当已签名安装包；会改版本 |
| `scripts/prepare_ios_device_build.sh / verify_ios_device_frameworks.sh` | 清理误缓存的模拟器 Native Assets、检查设备 framework |
| `scripts/build_windows_installer.ps1`、`windows/installer/starflow_windows_installer.iss` | Flutter Windows 构建及 Inno Setup 安装器，会递增版本 |
| `scripts/flutter_with_mirror.ps1`、`connect_mumu.ps1`、`complete_android_setup.sh` | 镜像、模拟器连接和旧 SDK 辅助；环境与限制见网络文档 |
| `scripts/run_web_with_proxy.ps1`、`tool/web_dev_proxy.dart` | 本机 Web 开发转发；无身份验证，CORS 白名单尚未覆盖全部功能 |
| `scripts/rebuild_media3_audio.sh` | 固定源码重建 ARM 音频 JNI，需已有 AAR 提供 Java 类；非日常启动步骤 |
| `scripts/test_subtitle_language_contract.swift` | macOS 上独立编译的 Swift 语言契约 runner |
| `tool/perf/run_perf_baselines.dart` | 五场景主机子进程计时，跨平台显式提供 `--output` |
| `tool/generate_brand_assets.py`、`generate_app_icons.swift` | Python 是统一资源导出入口，Swift 是转发兼容入口；使用 PNG 母版及 Edge 横幅渲染 |
| `tool/debug/manual_nas_grouping_test.dart` | 手动分组诊断，不属于默认 `flutter test` 回归集合 |

## 测试导航与维护原则

- Dart：`test/` 根目录及 `test/features/` 按领域覆盖模型、仓库、网络、缓存、页面和控制器；`test/core/` 覆盖公共身份等规则；`test/perf/` 是主机 smoke。
- 整理期间新增 `test/perf/performance_audit_probe_test.dart` 是行为 / 工作量审计探针，不在五场景计时脚本列表内，也不是设备性能报告；前面的全量结果不自动覆盖后续新增测试。
- Android：`android/app/src/test/kotlin/` 使用 JVM 单测及必要的 Android / Media3 stub，不执行 ARM decoder；测试报告不能替代电视显示、音频或网络验收。
- 跨语言字幕：`test/fixtures/subtitle_language_contract.json` 由 Dart / Kotlin / Swift 读取，修改语义时一起检查。
- iOS 的纯 Swift runner 不等于 Xcode 全量构建；macOS 模板 RunnerTests 也不等于所有业务回归。
- 当前执行结果、已知 Android 失败及运行命令见 [performance.md](performance.md)；不要在其他文档无日期地写“所有测试已通过”。

修改代码时优先保持现有 feature 边界、`part` 关系与平台条件导入；涉及用户行为同步 README 和专项文档。文档更新不得回退工作区已有变更，也不要提交凭据、原始日志、生成缓存或临时媒体样本。
