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

### 2026-09-20 选集到选季焦点回归

- TV 选集首集／网格首行上移优先进入可用选季入口；选季上移到模式按钮，两个模式按钮下移经过选季，选季下移返回原剧集。单季跳过禁用入口，原有跨段和底部定位导航不变。
- 主机指定 3 文件 **52 项通过**，包含新增列表／网格四列的选季往返、取消选季弹窗后的恢复，以及单季跳过测试；同时覆盖原有首帧定位、跨段导航、加载结果失效、手机布局和播放器小弹窗。不与此前 50 项重复累计。
- 选集组件及测试的定向 `flutter analyze --no-pub` 无问题。本轮首次运行曾被工作区缓存代码的类型错误阻断，另一处更新后重跑通过；中断的重复运行不作为通过证据。
- Android 已同步修改选集 View 的方向处理并补充首行边界 JVM 用例；停止前已完成 debug Kotlin 编译和 `NativeEpisodePickerNavigationTest` 5 项测试（0 失败／错误／跳过），仅验证索引策略，不运行原生 View。随后按用户要求终止 Gradle，release Kotlin 编译未完成，不记为通过。
- 以上为模拟按键与组件焦点验证，不是物理遥控器、Android 原生 View 或设备性能验收。没有发布 APK、递增版本或修改播放解析链路。

```sh
flutter test --no-pub --concurrency=1 test/player_episode_picker_dialog_test.dart test/player_small_dialog_focus_test.dart test/player_tv_playback_widgets_test.dart
flutter analyze --no-pub lib/features/playback/presentation/widgets/player_episode_picker_dialog.dart test/player_episode_picker_dialog_test.dart
```

### 2026-09-20 TV 直播扫码导入

- TV 文件入口改为手机扫码，复用配置/日志传输的二维码组件。文件接收后只进入编辑草稿，仍需电视确认保存；非 TV 保留本地文件选择。
- 主机指定 9 文件 **87 项通过**，其中新增接收服务 8 项、界面 7 项；其余包含原有直播解析/仓库/生命周期/页面/Exo 通道及共享二维码、日志导出回归。与下方历史 132 项有重叠，不累加，不代表全仓测试。
- 接收服务使用本机真实 HTTP 测试，覆盖令牌/Host/Origin、原始 GBK 字节、无效文件重试、声明/分块超限、30s 期限策略、单次/并发接收、取消和会话过期。界面使用 fake session/repository，覆盖 320/1280 宽度、草稿确认、返回/后台清理、迟到启动与失败；真实仓库由原有数据测试覆盖。
- 定向 `dart analyze` 无问题，`git diff --check` 通过。早期界面夹具因 FakeAsync 与实际存储/isolate 等待中止，已分离为界面和数据测试；以最终 87 项为本轮结果。
- 按用户要求停止浏览器测试。此前仅打开页面、选择文件并检查了 390 宽度布局，上传提交前测试服务过期，未完成成功上传验收；临时浏览器验证入口已移除。手机到电视的跨设备扫码、真实遥控器与 API23 设备仍未测，没有发布 APK 或递增版本。

```sh
flutter test --no-pub --concurrency=1 --reporter expanded test/live_playlist_transfer_service_test.dart test/live_playlist_transfer_page_test.dart test/live_tv_test.dart test/live_tv_data_test.dart test/live_playback_lifecycle_test.dart test/live_tv_page_test.dart test/live_exo_bridge_test.dart test/features/settings/presentation/lan_transfer_qr_address_card_test.dart test/features/settings/presentation/log_export_page_test.dart
dart analyze lib/features/live_tv test/live_playlist_transfer_service_test.dart test/live_playlist_transfer_page_test.dart
```

### 2026-09-20 直播前置验证快照

以下保留前置快照，并补充五任务合并后的主任务验证。所有结果只覆盖列出的主机测试，不代表全仓全绿或设备解码验收。

| 批次／检查 | 已确认结果 | 证据边界 |
| --- | --- | --- |
| 五任务开始前直播及集成集合 | 指定 7 文件、79 项通过 | 执行早于五任务后续修改，不代表当前 live 全套或全仓全绿 |
| Android `:app:compileDebugKotlin` | 2026-09-20 成功 | 仅该次 Kotlin 编译；不是 APK 发布、ARM 解码、原生视图运行或后续修改复编译通过 |
| 后续导航集成补充 | 3 文件、48 项通过 | 新增旧菜单不强制插入直播及旧分支索引不移动用例；与前置集合重叠，不与 79 相加，也不是最终全量 |
| 后续播放任务专项 | 新增生命周期 19 项、当前 Exo 通道 6 项通过 | 主任务转述的该次专项结果，不并入 79/48，不代表最终 live 全套或真实原生视图运行 |
| 后续数据任务专项 | `test/live_tv_test.dart`、`test/live_tv_data_test.dart` 共 38 项通过 | 主任务确认的数据收尾结果，与前置/其他专项可能重叠，不相加为最终总数 |
| `adb devices` | 无已连接设备 | 真实源和真机均未测，没有双内核首帧、换台或长播结果 |
| 合并后直播及导航/设置集成集合 | 9 文件、132 项通过，0 失败 | 包含生命周期 19、页面 7、Exo 通道 6、数据/控制器 38 和导航/设置 62；合成数据与 fake engine/mock 通道，不播放真实媒体 |
| 核心独立复测 | 生命周期、页面、Exo 通道 3 文件、32 项通过 | 与 132 项重叠，不累加；上轮组合执行曾 131 通过/1 失败，后续完整及核心复测未复现，未将其推断为已定位修复 |
| 合并后 Android 检查 | Gradle 编译及直播 JVM 目标成功；17 项、0 失败/错误/跳过 | LiveTvPolicyTest 11、LiveTvHttpTransportTest 6；收尾 Gradle 检查命中 UP-TO-DATE，报告为该源码的专项结果，不称为重新执行全部 Android 测试 |
| 定向静态分析及布局 | `dart analyze` 无问题；320/390/1280 宽度组件布局和截图已检查 | 14 张截图位于 `build/live-tv-review/`，播放背景来自 fake engine；不作为 TextureView、解码或真实台标网络证据 |

前置 7 文件范围，均相对仓库根目录：

- `test/live_tv_test.dart`
- `test/live_tv_page_test.dart`
- `test/live_exo_bridge_test.dart`
- `test/app_navigation_shell_tv_focus_test.dart`
- `test/app/router/app_routes_test.dart`
- `test/app_settings_test.dart`
- `test/features/settings/presentation/settings_hierarchy_navigation_test.dart`

后续 48 项仅为 `test/app_settings_test.dart`、`test/app/router/app_routes_test.dart`、`test/app_navigation_shell_tv_focus_test.dart`。这些是两次执行快照，不相加、不冒称互不重叠；本页其他点播 Flutter/JVM/Swift 批次也不自动覆盖直播模块。

主任务合并后已执行的完整集合及复测命令：

```sh
flutter test --no-pub --concurrency=1 --reporter expanded test/live_tv_test.dart test/live_tv_data_test.dart test/live_playback_lifecycle_test.dart test/live_tv_page_test.dart test/live_exo_bridge_test.dart test/app_navigation_shell_tv_focus_test.dart test/app/router/app_routes_test.dart test/app_settings_test.dart test/features/settings/presentation/settings_hierarchy_navigation_test.dart
flutter test --no-pub --concurrency=1 --reporter expanded test/live_playback_lifecycle_test.dart test/live_tv_page_test.dart test/live_exo_bridge_test.dart
dart analyze lib/features/live_tv lib/app/router/app_routes.dart lib/app/router/app_router.dart lib/app/router/app_navigation_shell.dart lib/features/settings/domain/app_settings.dart lib/features/settings/presentation/settings_page.dart test/live_tv_test.dart test/live_tv_data_test.dart test/live_tv_page_test.dart test/live_playback_lifecycle_test.dart test/live_exo_bridge_test.dart
# 在 android/ 目录执行；成功，Kotlin/JVM 目标为 UP-TO-DATE。
./gradlew :app:compileDebugKotlin :app:testDebugUnitTest --tests 'com.example.starflow.LiveTv*' --console=plain
```

解析/时区/事务缓存/迟到刷新与播放恢复可用合成数据、内存库和 fake engine 测试；布局/遥控器组件测试不执行解码，Exo MethodChannel mock 仅验证参数及事件契约，不创建真实 `LiveTvView`。本机原生编译也不能证明 Media3 标准 renderer 的真实格式支持、音轨切换、TextureView 像素或 TV 焦点。

直播的 `live.playback` started 记录首次 `progress` 或 `frame`，耗时从合并窗口后进入开流队列任务开始，不含最初用户按键到该任务执行的全部等待。MPV position 前进不是像素首帧；Exo 也可能先由 progress 记忆频道，不能把所有 started 记录当 `onRenderedFirstFrame`。直播目前没有接入点播完整的 `playback.performance` 会话摘要、掉帧/带宽/decoder 汇总，跨内核首帧、换台 p50/p95 需外部一致测量，见 [设备对比清单](performance-device.md#直播双内核对比验收2026-09-20)。

本轮未运行发布预设、未递增发布版本或交付 APK；保留既有文档及其他任务改动。真实订阅鉴权/重定向、台标、长播、断流、低内存设备及物理遥控器尚无本轮验收数据。Gradle 仍提示已有弃用特性，不据此宣称 Gradle 9 兼容。

播放任务收尾边界：15s 开流等待只计时并触发失败，不使用 `Future.timeout` 提前释放所有权；旧 open 未 settle 仍阻塞串行清理。`LiveEngine` 没有取消接口，永久挂起仍需等待底层，19 项生命周期及 6 项通道测试不能证明 15s 强制中止媒体网络。专项已纳入上述最终集合，不相加。

数据任务收尾边界：10000 频道/每频道 64 线路/全表 50000 线路上限；generation 刷新合并和删除/禁用/同 ID 重建后的旧结果失效；EPG 失败保留节目与台标；手动排序后新频道追加；来源日志 ID 哈希、偏好来源归属。38 项是该次合成数据/仓库回归，不是大规模真实订阅、设备内存或网络吞吐测量。

### 2026-09-20 MPV 跳过与切集边界修复

- 本轮五项修复已集成：自动切集请求取消 / 手动优先、全部 Player seek 入口的手动保护、启动期片头越界纠正、真实位置与显式完成标记分离，以及预解析缓存 / 在途请求复用。Android 原生实现未在本轮修改。
- 最终主机 Flutter 选择范围 **217 项通过，0 失败**，命令为 `flutter test --no-pub --concurrency 2 --reporter expanded test/features/playback/application test/player_auto_skip_interactions_test.dart test/playback_memory_repository_test.dart test/player_adaptive_controls_layout_test.dart test/player_startup_cancellation_test.dart test/player_episode_picker_dialog_test.dart test/playback_seek_coalescer_test.dart test/playback_system_session_test.dart test/perf/player_open_smoke_test.dart`。
- 新增策略回归覆盖取消后迟到结果、手动请求取代自动请求、旧 finally、一次前台期限、定时器执行前的截止时间检查、手动失败重试、短集 / 未知时长 / 迟到 seek / 取消、完成状态与实际进度。`player_auto_skip_interactions_test.dart` 使用真实 Android / iOS / Windows Adaptive 控件和假后端，验证进度条命令在后端事件前撤销自动意图并清除完成标记；该测试不是设备解码或触屏实测。
- 定向 `dart analyze` 检查新增五个模块、仓库、播放页与修改的 part 文件及相关测试，无问题；`git diff --check` 通过。早期新测试夹具的控件显隐 / 鼠标悬停问题和缓存空值编译问题已修正，最终结果以上述 217 项为准。
- 没有运行发布预设、递增版本或交付 APK，没有新增真机性能数据。需按 `performance-device.md` 的跳过边界与短集场景验证实际出帧、网络解析请求量和远程播放时序；不要把本轮主机耗时解释为播放性能收益。

### 2026-09-20 播放器流畅度修复

对应 [播放器审查处理状态](player-smoothness-review-2026-09-20.md)。以下均为主机执行结果，不是 TV/iPhone 掉帧或首帧测量；没有运行发布预设、改变版本或交付 APK。

- Flutter 播放应用层、取消、字幕绑定、历史、外部播放列表及新增 seek 集合 **91 项通过**。补充轨道守卫、seek、飞牛服务、服务端选轨、字幕管线、启动 scope、生命周期集合 **50 项通过**；其中 seek 的 5 项重叠，不能直接相加。新增测试覆盖 2/5/10 秒长按、定位在途合并、取消及自动字幕迟到/手动选择/失败隔离。守卫测试不等同于真实 decoder 下的完整 UI 选轨验收。
- Android 4 类 JVM **56 项通过，0 失败/错误/跳过**：MemoryStore 15、RuntimeController 9、BufferPolicy 9、RemoteController 23。新并发用例阻塞首个写入，确认调用线程不执行持久化、周期更新合并且强制保存先于后续 tick；现有历史/字幕/跳过偏好及外部原文失效用例保留。验证过程中另有任务执行 Android 构建，计时不作为性能基线。
- `scripts/test_native_playback_storage.swift` 优化编译后通过：延迟队列保留空 URL 元数据、前后集索引、进度队列最终顺序、字幕偏好、裁剪与外部失效。`scripts/test_native_playback_startup.swift` 优化编译后通过：重复 KVO 只有一个 preroll、成功/失败/取消/迟到回调及 VOD/显式直播 HLS 策略；不播放网络媒体。
- iOS 无签名 arm64、部署目标 iOS 13.0 的 Xcode Debug 构建成功；全部 Runner Swift 使用 iPhoneOS SDK 的独立类型检查通过。已有 Pod OpenGLES 弃用、图标未分配资源等构建警告保留；未执行 RunnerTests/XCTest、模拟器 UI 或真机切集/后台联调。
- `dart tool/generate_playback_policy.dart --check` 通过；播放目录及新增测试定向分析无问题，编辑文件空白检查通过。收尾 seek/轨道守卫/启动取消/外部文件四文件复测 **14 项通过**，与前两组重叠，不累加。之前审查的 148 Flutter/80 JVM 是更早快照，不作为本次修复用例计数。

主要命令：

```sh
flutter test --no-pub --concurrency 2 test/playback_seek_coalescer_test.dart test/features/playback/application test/player_startup_cancellation_test.dart test/player_startup_overlay_test.dart test/mpv_subtitle_render_binding_test.dart test/features/playback/data test/playback_memory_repository_test.dart
flutter test --no-pub --concurrency 2 test/playback_seek_coalescer_test.dart test/playback_track_guard_test.dart test/native_fntv_service_test.dart test/playback_server_track_resolver_test.dart test/subtitle_pipeline_regression_test.dart test/mpv_startup_scope_test.dart test/app_runtime_recovery_boundary_test.dart
swiftc -O ios/Runner/NativePlaybackStartupGate.swift ios/Runner/NativePlaybackBufferingTuning.swift scripts/test_native_playback_startup.swift -o /tmp/starflow-startup-check
/tmp/starflow-startup-check
swiftc -O ios/Runner/NativePlaybackModels.swift ios/Runner/NativePlaybackMemoryStore.swift ios/Runner/PlaybackMemoryPolicy.swift ios/Runner/PlaybackPolicyValues.swift scripts/test_native_playback_storage.swift -o /tmp/starflow-storage-check
/tmp/starflow-storage-check
```

Android 在 `android/` 执行 `./gradlew :app:testDebugUnitTest -x :app:compileFlutterBuildDebug -Pandroid-skip-build-dependency-validation=true --console=plain`，用 `--tests` 限定上述四类。Xcode 使用 `-workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`，独立 derived data 位于 `/tmp/starflow-player-build`。这不是发布安装包。

尚无优化后同规模保存耗时或设备改善百分比。同步最新历史查询仍可能等待后台队列。2026-09-20 后续修复把移动端 Flutter 读改写接入原生共享串行队列，以 compare-and-set 拒绝旧快照并重试；历史上仅靠各自队列、存在跨运行时覆盖竞争的描述属于修复前快照。该协议不是跨进程数据库事务；iOS 有限后台时间、Android 后台 commit 均不能承诺强杀瞬间未完成写入持久化。真机验收仍按 performance-device 执行。

### 2026-09-20 音频五项再审修复

- 五个并行子任务的最终实现接入 Session 后，将全部 Android 主 Kotlin 与 JVM 测试源码复制到独立目录，用缓存的 Kotlin 2.2.20 编译器、JVM 17 目标和冻结的 Android/Media3 测试依赖重新编译；JUnit 全量 **418 项通过**。结束后比对当前全部 Kotlin 源码与已验证副本一致。共享 Gradle 构建输出受到其他并行任务影响，因此本次使用隔离编译，不称为完整 Gradle/APK 构建通过。
- 新增覆盖高精度 `getMinBufferSize` 明确拒绝的类型化异常、默认缓冲区策略一致性、原异常和声道能力透传、缺少 renderer Format 的源轨/DRM 防护、倍速临时精度历史、AudioTrack 复用与旧释放、FFmpeg AC-3 排除。集成用例运行真实 Media3 `DefaultAudioSink` 和 provider，注入平台拒绝结果后验证原始 Format 传到单次 PCM16 回退；Android 硬件 API 使用测试替身。
- LPCM 可选样本通过 `STARFLOW_LPCM_PACKETS=/tmp/starflow-lpcm24-packets.bin`、`STARFLOW_LPCM_REFERENCE=/tmp/starflow-lpcm24-reference.bin` 启用，包含 stereo/96 kHz/24-bit 合成样本与 FFmpeg PCM24 逐字节对比。隔离执行脚本为本机临时文件 `/tmp/starflow-audio-reaudit/verify.rb --all`，不是仓库构建入口；无并行构建冲突时可在 `android/` 以相同样本环境变量运行 `./gradlew :app:testDebugUnitTest --offline` 复验。
- `git diff --check` 通过，`adb devices` 仍无已连接设备。本批没有重建 AAR、运行发布预设、修改版本或生成 APK，也未重跑 Flutter 全集。没有新增 ARM decoder、HDMI、真实 AudioTrack、CPU/GC、A/V 同步或 bit-perfect 测量；418 是本次源码快照的 JVM 结果，不覆盖后续并行编辑。

### 2026-09-20 音频输出状态与倍速补强

- 前一批 Android JVM 全量 **368 项通过，0 失败、0 跳过**。在 `android` 目录运行 `STARFLOW_LPCM_PACKETS=/tmp/starflow-lpcm24-packets.bin STARFLOW_LPCM_REFERENCE=/tmp/starflow-lpcm24-reference.bin ./gradlew :app:testDebugUnitTest --offline`，未排除 Flutter 编译或 MPV 依赖任务；这是该批工作区快照，不覆盖上方五项再审修复或后续并行修改。
- 新增覆盖普通 PCM16 原地调速、直通改速及恢复、速度/音调与所有输出模式组合、可读编码标签、失败前捕获 sink Format、压缩输入但 float 输出故障、实际 AudioSink 异常格式优先于缓存、PCM16 不误回退、DRM/视频排除、独立恢复预算和释放后输出状态隔离。仍包含上一批 LPCM 低位保留、Media3 转换器及 stereo/96 kHz/24-bit 合成样本与 FFmpeg PCM24 逐字节对照。
- `git diff --check` 通过。`adb devices` 无已连接设备；没有新增 ARM decoder、HDMI、AudioTrack、CPU/GC、A/V 同步或 bit-perfect 实测。本批未运行 Flutter 测试全集、重建 AAR 或执行 APK 发布预设。

### 2026-09-20 LPCM 保位深与输出策略

- 前一批 Android JVM 全量 **357 项通过，0 失败、0 跳过**。命令为 `STARFLOW_LPCM_PACKETS=/tmp/starflow-lpcm24-packets.bin STARFLOW_LPCM_REFERENCE=/tmp/starflow-lpcm24-reference.bin ./gradlew :app:testDebugUnitTest --offline`（在 android 目录）；没有排除 Flutter 编译或 MPV 依赖任务。这是该批代码快照结果，不覆盖之后的并行修改或上方输出状态补强。
- 前置 71 项音频专项回归包含已有 stereo/48 kHz/16-bit 实样字节对比。全量中的可选 LPCM 对比改用 FFmpeg 生成的 stereo/96 kHz/24-bit 合成 Blu-ray TS，与 FFmpeg PCM24 参考输出逐字节一致；临时媒体未加入仓库。
- 新测试覆盖 20/24-bit 完整低位、同采样率位深变化、192 kHz/7.1 缓冲边界、上游 float 转换器的最低有效位、PCM16 兼容转换、速度/音调策略、倍速恢复状态和 raw PCM 输出单次回退。
- `git diff --check` 通过。未重建 AAR、运行发布预设或修改版本；没有运行本轮 Flutter 测试全集，也没有新真机 AudioTrack、HDMI、CPU/GC 或 bit-perfect 测量。兼容输出复用 Media3 默认整数转换，不将该降位深路径称为无损或带 dither。

### 2026-09-20 冗余代码与条件诊断清理

- 删除 189 处普通静默 trace 调用及四类旧 trace helper、`DebugTraceOnce`；错误路径改用结构化 `appLogError`，本地日志与原生退出捕获不关闭。清理日志专用空分支、参数、尺寸订阅及未使用的 IMDb 预览 API。
- 帧统计仅在记录 info 时收集、排序；warning 独立扫描长帧。MPV 收尾不记录 info 时只读取功能需要的 `cache-speed`，少读 11 项诊断属性，带宽缓存与会话收尾保留。
- IMDb 评分共享下载和后台索引构建，保留 TSV 与行偏移并二分查询；缓存有界，失败可重试，旧请求不得覆盖清空后的新缓存。下载、展开、行数和行长均设上限；这不是零内存开销或真机峰值测量。
- Flutter 运行资源排除两张设计源图与性能视频，保留实际 Logo 和 bootstrap。排除文件原始合计 2,037,702 字节（约 1.94 MiB），不代表 APK 压缩后体积差；移除未使用的 `cupertino_icons` 依赖。
- 主机扩展回归 **256 项通过**，覆盖元数据、详情、字幕、播放解析/启动/应用服务、首页、NAS、日志、IMDb 边界和运行资源清单。此前专项 22 项包含在本次集合内，不重复相加。
- `dart analyze lib test` 无问题，`git diff --check` 通过。验证针对当次工作区快照，不作为其他并行任务后续修改的验收结果。
- 本轮未执行完整测试全集、发布构建或 Android/iOS 真机性能测量；没有新增首帧、内存峰值、CPU 或 APK 体积的实测收益结论。

### 2026-09-20 播放器流畅度审查

范围与待处理问题见 [播放器流畅度审查](player-smoothness-review-2026-09-20.md)。本轮只读审查播放器实现，新增文档和索引，不修改画质、缓冲、字幕、持久化或版本。以下主机结果不是设备播放验收，也不是同日其他任务后续修改的全绿证明。

- Flutter 播放启动、策略、恢复、生命周期、系统会话、字幕绑定、播放记忆和 smoke 集合 **123 项通过**；补充飞牛、服务端选轨、字幕管线和外部 M3U 集合 **25 项通过**。两组测试文件不重叠，合计 148 项。
- Android `:app:testDebugUnitTest` 选择 8 类 **80 项通过，0 失败/错误/跳过**：BufferPolicy 9、MemoryStore 14、RuntimeController 9、RemoteController 23、Session 7、PerformanceTracker 1、SubtitleOutput 13、DualSubtitleTrackPolicy 4。使用 `-x :app:compileFlutterBuildDebug -Pandroid-skip-build-dependency-validation=true --console=plain`，原生代码和测试实际编译，不是完整 APK 构建。
- `dart analyze lib/features/playback lib/core/platform/playback_system_session.dart` 无问题；`dart tool/generate_playback_policy.dart --check` 通过。`scripts/test_native_playback_storage.swift` 与对应模型/存储/策略优化编译后运行通过；不等于运行 RunnerTests/XCTest 或 AVPlayer 设备播放。
- 临时 Swift 预热探针使用 ready 状态 AVPlayerItem 子类和只计数、不完成回调的 AVPlayer.preroll 覆盖，调用现有 StartupGate，再通过 KVO 发出两次缓冲属性通知：preroll 调用数从 1 变成 3，确认在途阶段缺少防重入。编译仍有 StartupGate 的 MainActor/Sendable 回调隔离警告，未修复或隐藏。
- 临时 Swift HLS 策略探针使用 `https://example.test/vod/movie.m3u8`，不访问网络；默认推断 isLiveStream=true、前向偏好 8 秒，显式 VOD 为 24 秒。仅证明格式推断分支，不证明设备缓冲量或收益。

Swift 历史保存探针环境：Intel Core i5-8257U 1.40GHz、macOS 15.7.9、Swift 6.2.4、`swiftc -O`。用独立临时 UserDefaults suite 写入合成 series JSON，以现有 MemoryStore 预热快照；同一当前集连续保存 8 次，剔除首个样本，统计后 7 次调用的墙钟时间。包含时间戳扫描、JSON 校验/编码和 UserDefaults.set 调用，不等待异步磁盘同步；结束后清理 suite，不读取用户播放记录。

| series 条目数 | 种子 JSON 字节数 | 7 次暖保存耗时 ms | 中位数 ms |
| --- | --- | --- | --- |
| 20 | 7,253 | 12.47, 11.56, 10.66, 10.54, 10.56, 10.42, 10.40 | 10.56 |
| 200 | 72,893 | 88.69, 87.46, 89.41, 89.11, 88.44, 89.42, 92.54 | 89.11 |
| 1000 | 365,693 | 433.52, 433.20, 438.77, 433.30, 471.77, 437.84, 435.04 | 435.04 |

这些是合成规模下的主机同步工作量快照，不是实际库规模、iPhone 帧时、TV 闪存耗时或优化后收益。原文/解析缓存已经存在；当前被测成本不能再描述成每次完整 JSON 冷解码。临时探针不纳入正式回归，实施前需将对应场景变成可持续的测试/基线。

Flutter 主要集合命令：

```sh
flutter test --no-pub --concurrency 2 --reporter expanded test/features/playback/application test/playback_mpv_policy_test.dart test/mpv_tuning_policy_aggressive_downgrade_test.dart test/mpv_stall_watchdog_test.dart test/mpv_network_recovery_policy_test.dart test/mpv_startup_scope_test.dart test/player_startup_cancellation_test.dart test/player_startup_overlay_test.dart test/mpv_subtitle_render_binding_test.dart test/playback_memory_repository_test.dart test/perf/player_open_smoke_test.dart
flutter test --no-pub --concurrency 2 --reporter expanded test/native_fntv_service_test.dart test/playback_server_track_resolver_test.dart test/subtitle_pipeline_regression_test.dart test/features/playback/data/external_playback_playlist_test.dart
```

`adb devices -l` 无设备；未运行发布预设、未生成交付安装包、未重跑全仓测试或 iOS App 链接构建。其他任务正在修改详情、选集及文档，收尾时还出现播放器日志/诊断与飞牛选轨修改；已重新核对相关热点，但上述测试完成于这些新增修改之前，不是最新工作区全绿证明。本轮审查没有改变这些实现。

### 2026-09-20 选集整行定位

- Flutter / MPV 选集自动定位改为按 72dp 行边界停靠；底部补不足一行的滚动余量，避免为展示最后一行而在顶部露出半行空白。手动拖动不强制吸附。
- `flutter test --no-pub --reporter expanded test/player_episode_picker_dialog_test.dart test/player_small_dialog_focus_test.dart`：42 项通过。新增用例先在旧定位算法下复现未对齐，再验证手机横竖屏、TV、列表/网格、首帧位置稳定、分段/模式切换、定位当前集、末集完整显示与触屏自由滑动。
- 两个本轮修改的 Dart 文件定向 `dart analyze` 无问题；目视检查 320dp 手机列表/网格及 1280dp TV 列表组件截图。仅为主机组件回归，不是设备播放或性能验收；未修改 Android 原生定位、未运行发布预设或生成安装包。

### 2026-09-20 手机选集关闭入口

- 非 TV 的 Flutter / MPV 选集面板左下角新增关闭按钮，TV 焦点布局保持不变。
- `flutter test --no-pub --reporter expanded test/player_episode_picker_dialog_test.dart test/player_small_dialog_focus_test.dart`：35 项通过。覆盖手机横竖屏、列表/网格的左下角位置与取消返回值、加载中关闭及迟到成功/失败结果，以及原有 TV 焦点回归；另目视检查 320dp 列表/网格组件截图。
- 两个本轮修改的 Dart 文件定向 `dart analyze` 无问题。这些是主机组件验证，不是真机播放验收；未运行发布预设或生成安装包。

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

### Audio conversion verification (updated 2026-09-20)

LPCM now reuses a 24-byte sample-frame buffer, a 46,080-byte output buffer and
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
tests cover mono padding, 5.1/7.1 order, all fragment splits, preservation of 20/24-bit samples,
seek, missing PTS and sample-rate changes. Real multichannel/high-bit-depth
samples and ARM32/ARM64 decoder execution still require device validation.

The example reference command is for 16-bit input; for 24-bit use
`-c:a pcm_s24le -f s24le`. Precision tests execute the actual Media3 float and
integer audio processors on the JVM, including the lowest 24-bit sample bit.
Policy tests cover normal speed, pitch/speed changes, explicit PCM compatibility
and one-shot AudioTrack failure fallback. These are not AudioTrack device tests.

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
