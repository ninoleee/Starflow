# 主机性能与回归验证

核对日期：2026-09-20。本文负责主机侧 smoke 计时、可重复运行方法及自动化回归证据。电视、手机和桌面实际界面的测量方法见 [真机性能验证](performance-device.md)，组件关系见 [架构说明](architecture.md)。下文历史代码优化只说明工作量与策略变化，不代表已经测得设备收益。

## 计时含义

`tool/perf/run_perf_baselines.dart` 串行启动 `flutter test` 子进程，用 wall-clock 记录整个子进程耗时，包含工具启动、可能的依赖检查、编译与测试执行。名称中的 `first_screen` 或 `player_open` 是场景标识，不是设备首屏 / 视频首帧时间，也不是远程服务吞吐量。

| 场景 | 实际测试入口（相对仓库根目录） | 主要覆盖 |
| --- | --- | --- |
| `startup` | `test/perf/bootstrap_smoke_test.dart` | Flutter 启动编排与截止时间 |
| `home_first_screen` | `test/home_controller_test.dart` | 首页来源及装配逻辑 |
| `detail_first_screen` | `test/media_detail_enrichment_test.dart` | 详情缓存和元数据补全 |
| `player_open` | `test/features/playback/application/playback_startup_preparation_test.dart`、`playback_startup_routing_test.dart`，以及 `test/perf/player_open_smoke_test.dart` | 本地准备、解析、路由、执行器协作，不运行真实 decoder |
| `index_refresh` | `test/media_repository_quark_source_test.dart` | 夸克来源索引读取 / 刷新契约，不等于真实 WebDAV 全库扫描耗时 |

默认每场景运行 5 次；`--scenario` 接受逗号分隔的场景 ID。每次保存原始 `runsMs`，p50 / p95 使用排序后的 nearest-rank（`ceil(n * p) - 1`）。只有 1 个样本时两者相等，5 个样本的 p95 实际就是最大值，不宜据此宣称稳定尾延迟。

## 当前验证记录

### 2026-09-20 组件重构回归

详情、搜索与转存、缓存、MPV 与 iOS 宿主的四组重构验证单独记在 [组件重构记录](refactoring-2026-09-20.md)。主任务的跨模块集成集合 105 项通过，`dart analyze lib test` 无问题；各子任务的定向集合与它有重叠，不能直接累加。本轮是组件职责和行为回归，不是新一次全仓/发布构建或设备性能采样。其他并行任务的性能改动保持原记录边界。

补充主任务新增组件集合 67 项、缓存/焦点/UI 集合 64 项通过；iOS 模型/存储 runner 和既有记忆/字幕契约通过，无签名 arm64、iOS 13.0 目标的 Xcode Debug 构建成功。RunnerTests 仅类型检查，未执行 XCTest 或真机后台/字幕/遥控器验收；既有主线程隔离与图标资源警告保留。

### 2026-09-20 性能审计后实施

逐项状态见 [审计处理表](performance-audit-2026-09-20.md)，具体请求/缓存/日志契约见 architecture 与 development-network。本轮不覆盖历史 smoke 数据，不修改画质/缓冲策略、不裁剪历史，不将代码复杂度下降解释为设备测速结果。

- 性能、图片、日志、搜索和 NAS 定向回归 112 项通过；补充夸克取消、动态并发池、搜索迁移和缓存拆分后的回归 59 项通过。这两组有重叠，不能相加作为独立用例总数。
- 最终 `flutter test --no-pub --concurrency 2 --reporter expanded`：**1681 项全部通过**，包含同工作区完成的搜索/存储/播放组件拆分；实际运行约 7 分钟，受到同机并行构建影响，仅作功能回归，不作速度基线。前一轮 1639 通过/1 失败的空索引取消问题已在本轮通过。
- 机制断言覆盖：图片慢正文超时/累计字节中止、共享消费者取消、隐藏超过 UI 租期后释放传输；16ms 跨事件写合并/clear/dispose 顺序；评分人数只写两个变化 shard；12 个冷历史读取只读一次；160 个 NAS 剧集的并发冷读只加载一次；预览跳过超大残行；日志批量/关键 flush/清理及队列背压。
- 完整回归中发现空 NAS 缓存于容器销毁后读取设置的取消异常，已改为空索引直接返回并通过相关回归。期间搜索/存储/iOS 同工作区拆分曾造成暂态编译错误，不回退其他任务的改动；验证以最后结果为准。
- `flutter analyze --no-pub` 无问题；Kotlin `:app:compileDebugKotlin` 通过（最终增量跳过 Flutter assemble 单独核对原生代码）；拆分后的 AppDelegate/NativePlaybackMemoryStore/NativePlaybackModels/NativePlaybackViewController/SettingsDocumentExporter 通过 `swiftc -frontend -parse`，这不是 iOS 链接构建或设备运行验证。
- `NativeAppLoggerTest` JVM 专项 1 项通过，验证调用返回时尚未触碰磁盘、后台单线程按序写入、满容量轮转保持完整 JSON 尾行及最新记录；未等同验证 Android 厂商闪存耗时或崩溃现场。
- 未连接 TV，未运行发布预设或交付 APK。blur、buffer、解码、首帧及 ARM32/ARM64 峰值内存仍按 performance-device 执行，不声称这些测量项已完成。

### 2026-09-20 逻辑统一回归

本轮在持续有其他任务修改的同一工作区执行，不能把某次通过当成所有后续修改的证明。未运行发布预设、未递增版本、未生成交付 APK，也未做设备性能采样。

- 14 个受影响测试文件的定向回归：150 项通过，覆盖首页 / 详情缓存、WebDAV / Quark NFO、播放记忆、版本工具、设置引用与两种网盘转存交互。
- 最后一次播放记忆、资源身份兼容、版本工具复测：24 项通过；版本 CLI 只修改临时 pubspec，覆盖固定批次版本、CRLF 和非法月份拒绝。
- Android 全量 JVM：337 项，336 通过、0 失败、1 跳过；包含共享播放记忆 fixture、时间戳排序裁剪和原生选集共享调色板。使用 `-x :app:compileFlutterBuildDebug` 复用已有 Flutter 输出，原生 Kotlin 和 JVM 测试正常编译，不代表完整发布构建。
- Swift 播放记忆契约：10 个阈值用例及 UTC / 时区 / 微秒旧时间戳归一化通过；`AppDelegate.swift` 与新策略文件通过语法解析，Xcode 工程通过 `plutil -lint`，未做 AVPlayer 真机续播验收。
- 策略生成 `--check`、两个 Bash 发布入口 `bash -n`、`git diff --check` 通过。本机无 PowerShell，未执行 PowerShell 发布入口。
- 最后一次 `flutter analyze --no-pub`：`No issues found`。整仓 Flutter 复跑未完成：机器负载超过 400 并发生大量内存交换，已停止本任务的重复重型验证。中断前记录到两项 `app_network_image_test.dart` 的 TV 图片加载失败，以及 `nas_media_indexer_test.dart` 新增冷加载并发合并用例失败（期望一次读取、实际六次）；这几处属于运行期间并行修改的工作区，不能把本次定向通过结果扩展成整仓全绿。SIGTERM 造成的收尾错误不计为业务断言失败。
- 最新增加的微秒 fixture 在 Dart / Swift 已通过；Android 全量通过后追加的 fixture 复跑因同机 Gradle 争用中断，不冒充再次通过。此前 JVM 已覆盖毫秒、时区、排序、裁剪及单调时间戳。

下方记录是本轮统一之前的历史快照，选集调色板失败已经在上面的 JVM 复跑修复；不要把两个时点合并计数。

2026-09-20，在包含既有未提交修改的 macOS 工作区执行。以下是**执行当时的快照**，不是后续继续编辑的工作区全绿声明：

| 检查 | 结果 | 边界 |
| --- | --- | --- |
| `flutter analyze --no-pub` | 无问题 | 静态分析，不是所有平台构建 |
| `flutter test --no-pub --reporter expanded` | 1580 项通过 | 主机单元 / 组件回归，不是设备播放 |
| `dart tool/generate_playback_policy.dart --check` | 通过 | Dart / Kotlin 生成策略与 JSON 一致 |
| Android `:app:testDebugUnitTest` | 318 项：316 通过、1 失败、1 跳过 | 失败为选集外观源码断言；跳过为需要外部 LPCM 样本的可选测试 |
| Android `:app:compileReleaseKotlin` | 单独执行通过 | 有弃用警告；没有生成或交付 APK |
| Swift 字幕语言契约 | 16 项通过 | 只编译语言策略与 fixture runner |

Android 失败位于 `android/app/src/test/kotlin/com/example/starflow/NativePlaybackSettingsAppearanceTest.kt:101`，检查选集面板源码是否包含指定调色板引用；本次未修改 UI 或测试绕过此失败。Gradle 的测试失败会使同一命令后续任务不再执行，因此本次另行运行了 release Kotlin 编译并通过。JVM 报告通常生成在 `build/app/reports/tests/testDebugUnitTest/index.html`，后续构建或清理会覆盖 / 删除，不能作为永久证据链接。

Flutter 全量运行于本地时间约 00:22 完成；文档收尾期间又出现公共组件、位图字幕解析、设置引用协调和发布版本工具等代码改动。本文已补充这些文件的职责，但没有把它们冒充为前面测试覆盖的内容，也没有启动发布预设来验证。需要针对最终稳定工作区重新运行回归。

本次未重新运行五场景性能采样、未运行发布预设，也没有新增真机性能数据。仓库现有 [perf_baselines.json](../tool/perf/perf_baselines.json) 生成于 **2026-04-11**，每场景只有 1 次采样：startup 2931ms、home 2568ms、detail 2988ms、player 2773ms、index 2635ms。它只是一份历史 smoke 记录，不是当前版本基线，本次保留原文件未覆盖。

### 位图字幕专项（2026-09-20）

本次 PGS/VobSub/DVB 加固及 MPV 绑定改动的专项检查，与前面的全量快照分开记录：

| 检查 | 结果 | 边界 |
| --- | --- | --- |
| Flutter 字幕五文件回归 | 34 项通过 | 新增绑定测试，以及 pipeline、server track resolver、FNTV、session preference |
| Android 字幕及相邻提取器/会话专项 | 86 项通过，无失败或跳过 | 含 11 项有界位图测试、真实 TextRenderer 时钟测试、作用域隔离；Bitmap 是 JVM mock |
| 本次涉及的 10 个 Dart 源码/测试文件定向分析 | 无问题 | 不代表并行修改文件的状态 |
| 最新全项目 `flutter analyze --no-pub` | 2 条 info | `persistent_image_cache_impl_io.dart:46`、`online_subtitle_repository_io.dart:149` 的大括号样式，属于并行修改文件 |

Flutter 命令：`flutter test --no-pub test/mpv_subtitle_render_binding_test.dart test/subtitle_pipeline_regression_test.dart test/playback_server_track_resolver_test.dart test/native_fntv_service_test.dart test/playback_subtitle_session_preference_test.dart`。

Android 在 `android/` 运行 `./gradlew :app:testDebugUnitTest -x :app:compileFlutterBuildDebug -Pandroid-skip-build-dependency-validation=true --console=plain`，使用 `--tests` 选择 `*BoundedBitmapSubtitleTest`、`*PgsReaderTest`、`*NativeSubtitle*Test`、`*NativeDualSubtitleTrackPolicyTest`、`*NativePlaybackSubtitleStyleControllerTest`、`*NativePlaybackExtractorsFactoryTest`、`*NativeTsH264SeekTest`、`*NativePlaybackSessionTest`。跳过 Flutter 打包任务是为了隔离运行期间其他任务的 Dart 改动，Kotlin/Java 和 JVM 测试实际编译；不是 APK 构建证据。报告目录可能被并行测试覆盖，以上只统计选择范围。

过程中曾遇到并行生成策略字段及日志模块编译暂态错误；未改动这些无关文件，恢复后字幕 Flutter 集重新通过。本轮未运行发布预设、未修改版本或交付 APK，也没有真机显示/峰值内存测量。资源上限和回归样本只证明边界行为，不证明低内存 TV 的实际播放效果。

### TV 焦点回归（2026-09-20）

同日约 00:55–01:01 的独立焦点检查，不能与上方较早的全量结果合并成当前工作区全绿结论。覆盖清单与页面职责见 [TV 焦点清单](tv-focus.md)。

| 检查 | 结果 | 边界 |
| --- | --- | --- |
| Flutter 焦点及相邻页面回归 | 352 项通过 | 公共控件、侧栏、首页、详情、设置、媒体库、搜索、字幕与播放器弹窗 |
| `tv_press_only_shortcuts_test.dart` 单项补跑 | 1 项通过 | 验证重复事件拦截器保留快捷键触发键及调试描述；与上行合计 353 项 |
| Android 六个焦点／遥控器测试类 | 50 项通过，无失败或跳过 | JVM 策略与 mock 验证，不运行 ARM 播放器或系统输入法 |
| 本轮涉及的 Dart 源码与测试静态检查 | 无问题 | 定向检查，不代表全仓库无告警 |
| `dart analyze lib test` | 2 个 warning、2 个 info | 位于并行改动文件，未在焦点任务中修改 |

原生运行使用 `:app:testDebugUnitTest`、`-Pandroid-skip-build-dependency-validation=true`，以 `--tests` 限定 `NativePlayerTvFocusPolicyTest`（4）、`NativePlayerTvSeekPolicyTest`（4）、`NativePlaybackRemoteControllerTest`（23）、`NativePlaybackControllerViewTest`（9）、`NativeEpisodePickerNavigationTest`（4）和 `NativePlaybackNumberPickerTest`（6）。本轮没有改原生焦点实现，也没有重复运行前述全部原生测试。

全仓库静态检查的 warning 是 `home_controller.dart`、`library_cached_items.dart` 中未使用的评分工具导入；info 是 `nfo_metadata.dart`、`playback_memory_policy.dart` 的条件分支括号风格。另一次包含转存流程的运行发现 `search_page_save_progress_test.dart` 的 `CloudSaveDrive.quark strm failure closes progress` 失败：STRM 失败后刷新次数期望为 0，实际为 1；该测试显式使用非 TV 模式，与并行的转存后处理整合有关，未调整其业务行为或测试断言。

快捷键单项补跑最初在编译阶段遇到磁盘 `errno = 28`，空间恢复后重试通过。未清理其他任务文件；没有生成 APK、修改发布版本或进行设备性能测量，`adb devices` 无连接设备。

## 比较条件与策略背景

以下保留自 2026-08-27 起的架构 / 性能检查事项，并按当前实现核对。代码边界变化不能单独证明性能改善：
The latest architecture pass moved several hot paths out of single large files:

* Home presentation is now split between `home_page.dart`, `home_page_hero.dart`, and `home_page_sections.dart`.
* Home application wiring is now split between `home_controller.dart`, `home_controller_models.dart`, and `home_feed_repository.dart`.
* Playback presentation is now split between `player_page.dart` and `presentation/widgets/player_page_*.part.dart` plus shared overlay/dialog widgets.
* Playback network-speed labels reuse existing player telemetry: Exo is event-driven through its `DefaultBandwidthMeter`, while non-Web MPV reads the local `cache-speed` property once per second. Neither path launches an additional network probe; include the visible control chrome when comparing playback UI frame cost.
* NAS indexing is now split across `nas_media_indexer.dart` and the `nas_media_indexer_*` part files (`grouping`, `refresh_flow`, `storage_access`, `indexing`, `refresh_support`).
* Recent playback ordering now depends on the monotonic `updatedAt` behavior in `playback_memory_repository.dart`, which matters most on Windows where multiple saves can happen in the same millisecond.
* Home source loading and metadata prefetching retain separate schedulers but share one persisted maximum-concurrency value with Emby and NAS/WebDAV work. Record that value, initial batch sizes, continuation delays, and foreground resume delay with every comparable baseline.
* A single Home navigation tap is the explicit soft-recovery boundary: it removes scheduler-owned batch/quiet waits and cancels background library refreshes without zeroing active counters or duplicating in-flight requests. The TV exit dialog only holds new metadata prefetch starts while visible and resumes them immediately when cancelled.
* Lifecycle and memory-pressure admission are lease-based and stack safely. Backgrounding pauses new Home and metadata work; foreground resume waits for the first frame plus 400 ms. Memory pressure adds a separate two-second quiet window and cancels background library refreshes without clearing persistent caches or active counters.
* Queue diagnostics warn once per continuous queue period after 5 seconds for Home/metadata and 4 seconds for TV raster images. Compare `oldestWaitMs`, active/pending counts, pause holds, and the configured maximum before treating a long wall-clock wait as a performance regression.
* Explicit user refreshes may consume one half-open probe per currently open Douban/metadata host circuit. Automated baseline startup does not arm probes, so keep manual refreshes outside a comparable run.
* The default shared maximum is `2`; Home starts `2` modules in the first batch with a `350ms` continuation delay, while metadata starts `12` items with a `300ms` continuation delay. Scrolling, focus movement, and page transitions defer new metadata starts for `400ms` by default.
* NAS/WebDAV source, collection, and enrichment-item budgets all read the shared maximum, with internal caps of `2` sources and `4` collections/items. Every online enrichment item additionally passes through the global metadata limiter.
* Structure-inferred episodes resolve online series metadata with the parent series title. Provider in-flight/result caches are therefore shared across a season instead of issuing one title search per episode filename; optional episode still requests remain separate.
* NAS/WebDAV series and season hierarchies are materialized into the source cache once and indexed per section. Detail child reads therefore avoid regrouping the full source for every series open or season switch.
* Large episode rows remain lazily built. TV artwork uses a shared four-request raster-load gate whose permits carry an eight-second self-healing lease, so an offstage widget cannot permanently stall Hero and poster loading. Image HTTP work times out after 15 seconds and retries after 1, 4, and 12 seconds. Already displayed detail sections remain mounted when covered by the player; page visibility and TickerMode gate the series-provider subscription.
* Detail series browsing starts after local source restoration without waiting for online metadata refresh. History and season reads run concurrently; series completion rebuilds only its Consumer region, and progress badges select their displayed text. Single-season content uses 292 logical pixels; only multi-season content adds the 68-pixel season selector. Errors use their natural height and empty series remain hidden. Validate cold/warm history, slow metadata, season switching and error states on TV; host smoke timings are not device frame measurements.
* Emby section refreshes enter the same global limiter as NAS metadata items. Maintenance sections have priority, so a large Emby library no longer launches every section request alongside NAS enrichment.
* Emby library persistence uses the current small manifest plus a source summary and source/section shards. Root-library and collection-only reads share a newest-400-item summary, section-scoped Home loads decode only the requested shard, and full-library matching decodes at most two shards concurrently. Identical snapshot and shard reads share in-flight work. Fallback payloads exclude items already represented by section shards, and large JSON work runs on a background isolate. Loads slower than `500ms` emit an info-level `storage.emby-cache` record. Legacy single-payload caches are not read or migrated.
* Detail-cache saves use a 16 ms timer window across event-loop turns, followed by serialized mutation. Clear queues behind accepted writes and disposal flushes accepted batches. Byte-identical payloads skip writes; rating updates persist only changed shards. These are write-count reductions, not physical fsync or device latency measurements.
* NAS/WebDAV section reads now apply `sourceId + sectionId` in the Sembast finder instead of loading a whole source into Dart before filtering.
* Bootstrap and the navigation shell share cold-start refresh completion state, so a baseline should contain at most one automatic Home refresh cycle.
* Structured logging and the frame monitor are active by default. Keep the same recorded log levels across comparison runs because trace-heavy diagnostics add some I/O.
* Successful metadata cache hits, joins of already in-flight requests, and empty sidecar contexts no longer emit one `TRACE` record per item. Keep comparing warning/error counts, but do not treat the lower trace volume as missing work.
* Movie version-folder recognition and the migration fingerprint run locally during NAS/WebDAV indexing. The library emits one representative movie while retaining the real files for detail playback choices, so compare both `media_index` duration and final record/card counts after this change.
* Detail source selection and playback-version selection are now separate derived views over the same retained candidate state. The source selector deduplicates providers, while the Hero-adjacent version selector only builds the selected source's playable files; include a multi-source, multi-version detail sample when investigating `detail_first_screen` or interaction regressions.

### When to run
* After modifying performance-sensitive controllers such as `HomePageController`, `HomeFeedRepository`, playback startup coordinators/resolvers, or retained async controllers that were part of the P0/P1 efforts.
* After touching `home_page.dart`, `home_page_hero.dart`, or `home_page_sections.dart`, because they directly affect the `home_first_screen` baseline.
* After touching detail presentation hot paths such as `detail_page_providers.dart`, `detail_resource_info_section.dart`, or `media_detail_page.dart`, because they directly affect `detail_first_screen` and detail interaction regressions.
* After touching `player_page.dart`, `presentation/widgets/player_page_*.part.dart`, `player_network_speed_label.dart`, `player_playback_options_dialog.dart`, or playback startup routing/execution, because they directly affect `player_open`.
* After touching `nas_media_indexer.dart` or any `nas_media_indexer_*` part file, because those changes can shift both `index_refresh` and any home/detail path that depends on index freshness.
* After changing `playback_memory_repository.dart`, because recent playback ordering changes can indirectly affect home feed stability and smoke expectations.
* After changing `home_feed_load_scheduler.dart`, `metadata_prefetch_concurrency_limiter.dart`, network guards, startup refresh settings, or structured logging.
* Before merging large refactors that could affect the timeline between user interaction and the first frame.

### Post-save directory refresh

Post-save WebDAV discovery uses the existing incremental refresh path and its normal scan, cache and concurrency policies. OpenList/AList STRM directories are supported when exposed through a WebDAV `/dav/...` path; no management `/api/...` request or server refresh call is made. Compare the existing `index_refresh` smoke separately; no server refresh API or periodic worker is part of this change.

### Exo TV directional-hold verification

The September 10 change coalesces directional repeats into one absolute seek per 250 ms window, with immediate first-press and key-up commits. Acceleration remains 10/30/60/120 seconds per input. Pending work is cancelled when focus, playback session, or the active interaction changes. The native memory store reuses unchanged decoded history, and Android media-session updates reuse the sampled display icon and skip unchanged metadata/notifications. These are code-level work reductions, not measured device frame-rate improvements.

* Run `./gradlew :app:testDebugUnitTest :app:compileReleaseKotlin -Pandroid-skip-build-dependency-validation=true` from `android` for hold timing, release, reversal, cancellation, seek bounds, snapshot invalidation and media-publication regressions.
* On a connected TV, compare short taps and 2/5/10-second holds in both directions, with the controller initially hidden and visible, and while paused or buffering. Include a low-memory/API 23 device and both a local sample and the same remote high-bitrate sample.
* Record controller frame timing separately from decoded-video dropped frames, audio underruns and key-up-to-playback recovery. Use existing `playback.performance` session summaries and Android device traces; seek buffering is not evidence of a rendering regression by itself.
* Check direction changes, start/end bounds, Back/Menu/confirm during a hold, focus loss and an episode switch with pending input. Confirm the controller does not flash closed or steal focus, no old callback seeks the next episode, and playback metadata/buttons update after a title, duration, pause or queue-boundary change.
* Host smoke timings and JVM mock-call counts cannot certify these device results. No TV device measurement is recorded for this change yet.

### Audio conversion verification (2026-09-19)

LPCM now reuses a 24-byte sample-frame buffer, a 30,720-byte output buffer and
one ParsableByteArray. The JVM batching test feeds 1,200 four-byte fragments
(25 ms, stereo/48 kHz) and expects three metadata submissions, not 1,200.
This is a deterministic work-count assertion, not a measured CPU/GC improvement.

For a local, legally available Blu-ray LPCM TS sample, compare the reader with
an independent FFmpeg decode without committing media into the repository:

```bash
ffmpeg -i sample.ts -map 0:a:0 -c:a copy -f data /tmp/lpcm-packets.bin
ffmpeg -i sample.ts -map 0:a:0 -c:a pcm_s16le -f s16le /tmp/lpcm-reference.bin
cd android
STARFLOW_LPCM_PACKETS=/tmp/lpcm-packets.bin STARFLOW_LPCM_REFERENCE=/tmp/lpcm-reference.bin ./gradlew :app:testDebugUnitTest --tests '*PcmBluRayReaderTest'
```

The optional fixture test is skipped when the two environment variables are
absent. The local stereo 48 kHz/16-bit TS sample matched byte-for-byte; synthetic
tests cover mono padding, 5.1/7.1 order, all fragment splits, 20/24-bit reduction,
seek, missing PTS and sample-rate changes. Real multichannel/high-bit-depth
samples and ARM32/ARM64 decoder execution still require device validation.

On API 23 TV and modern HDMI devices, test AC-3/E-AC-3/JOC, TrueHD, DTS/DTS-HD,
MP1/MP2/MP3 and supported LPCM layouts with missing metadata, mixed audio tracks,
output-mode changes, seek, speed, pause and episode changes. Capture actual
`playback.audio` decoder/output logs, underruns, CPU/GC and A/V sync. Confirm an
audio fallback happens at most once and never changes the video decode policy.
No connected-device audio performance result is recorded by this change.

## 运行命令

在仓库根目录执行，确保 `flutter` 在 PATH。先完成依赖安装和功能回归；对比期间不要同时运行 Flutter 构建、Gradle 或 iOS 发布脚本，避免共享输出目录争用。

```bash
dart tool/perf/run_perf_baselines.dart --runs 5 --output tool/perf/perf_baselines.local.json
```

Common variants:

```bash
dart tool/perf/run_perf_baselines.dart --runs 3 --output /tmp/starflow-perf.json
dart tool/perf/run_perf_baselines.dart --scenario player_open --runs 1 --output /tmp/starflow-player-perf.json
dart tool/perf/run_perf_baselines.dart --scenario startup,home_first_screen --runs 5 --output /tmp/starflow-startup-perf.json
```

`/tmp` 示例用于 macOS / Linux；Windows 可使用仓库内输出路径。脚本当前默认路径用 Windows 反斜杠拼接，所以跨平台调用必须显式提供 `--output`，避免在 POSIX 上生成错误位置的文件。这里记录现有限制，没有修改脚本。默认不覆盖历史基线；明确需要建立新基线时再指定 `tool/perf/perf_baselines.json`，同时记录机器、SDK、缓存和样本数。

### Output and validation
Review the generated report for regressions in the five baseline IDs: `startup`, `home_first_screen`, `detail_first_screen`, `player_open`, and `index_refresh`. The JSON contains `generatedAt`, `runsPerScenario`, and a `results` array with `runsMs`, `p50Ms`, and `p95Ms` for each scenario. If runtime shifts significantly, capture the new numbers together with the relevant diff and scenario id.

场景失败时脚本提前退出，不会写本轮完整报告；旧路径上的 JSON 可能仍在，必须同时检查退出码与 `generatedAt`。报告不自动收集设备、系统负载、SDK 版本或缓存状态，这些应随测量记录保存。

## 全量功能回归

仓库根目录：

```sh
flutter analyze --no-pub
flutter test --no-pub
dart tool/generate_playback_policy.dart --check
```

Android 目录分别执行，避免单元测试失败遮蔽编译检查：

```sh
./gradlew :app:testDebugUnitTest -Pandroid-skip-build-dependency-validation=true
./gradlew :app:compileReleaseKotlin -Pandroid-skip-build-dependency-validation=true
```

JVM mocks、源码断言与 Swift 纯策略测试不执行 ARM decoder，不验证系统字幕、HDMI、锁屏或 PiP。字幕的 Swift 命令见 [字幕链路](subtitles.md)，AAR 来源和重建见 [音频依赖](../android/app/libs/README.md)。

### Suggested focused verification
For this repo, the perf baseline run is usually paired with a few focused checks so we can tell whether a regression is functional, orchestration-related, or purely performance-related:

```bash
dart analyze lib/features/home/application/home_controller.dart lib/features/home/application/home_controller_models.dart lib/features/home/application/home_feed_repository.dart
flutter test test/home_controller_test.dart test/home_settings_slices_test.dart

dart analyze lib/features/playback/presentation/player_page.dart lib/features/playback/presentation/widgets lib/features/playback/data/playback_memory_repository.dart
flutter test test/playback_memory_repository_test.dart test/features/playback/application/playback_startup_routing_test.dart test/playback_target_resolver_test.dart test/playback_mpv_policy_test.dart

dart analyze lib/features/library/data/nas_media_indexer.dart lib/features/library/data/nas_media_indexer_grouping.dart lib/features/library/data/nas_media_indexer_refresh_flow.dart lib/features/library/data/nas_media_indexer_refresh_support.dart
flutter test test/nas_media_indexer_test.dart

dart analyze lib/core/network lib/core/logging lib/features/home/application/home_feed_load_scheduler.dart lib/features/metadata/application/metadata_prefetch_concurrency_limiter.dart
flutter test test/network_failure_test.dart test/network_request_guard_test.dart test/starflow_http_client_test.dart test/metadata_prefetch_concurrency_limiter_test.dart
```

### Tips
* Run under the same system load you plan to ship under so the numbers stay comparable.
* Re-run the script after applying the fix if the regression was real; this rewrites the baseline JSON, which you can commit alongside the change when the new numbers are expected.
* If a baseline regresses right after a file split, verify the focused tests first. In this codebase, regressions after refactors are often caused by wiring/state-order changes rather than the split itself.
* Keep the independent visual/playback switches, both startup refresh switches, the shared concurrency value, scheduler batch/delay values, and log levels identical when comparing two runs. TV-fixed protections are platform rules rather than comparison-time switches.
