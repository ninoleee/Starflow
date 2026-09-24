# 音频解码与转换审查

> 历史审查与分批修复记录，2026-09-24 归档。下文“当前”和测试结果均指各节标注的执行时快照，不代表最新工作区已复验。现行组件边界见 [架构说明](../architecture.md)，后续验证见 [主机记录](../performance.md)。

原始审查日期：2026-09-19；现状核对：2026-09-20。范围包含已有未提交修改，不是只审查某个 commit 的差异。本文将当前实现与 9 月 19 日实施前发现分开保留。组件边界见 [架构说明](../architecture.md)，当前主机回归见 [主机验证](../performance.md)，设备验收见 [真机性能](../performance-device.md)。

## 实施状态

### 2026-09-20 十方向审查后续修复

本节对应十方向报告的 A01、A02、U01、S04；报告及下文既有验证计数均保留为当时快照，不自动作为本节修改的验证结果。

- A01：同一 `playbackItemKey` 下，未消费的音轨身份跨连续播放器重建保留，不再被 prepare 阶段的空 tracks 覆盖；换片时在保存、暂存倍速和恢复入口隔离旧状态。
- A02：服务端默认音轨与反向 GUID 匹配都排除已知编码冲突，包括 metadata 唯一候选和未压缩序号兜底。编码未知仍可保守匹配，E-AC-3/JOC、DTS/DTS-HD 的通用编码提示不误判为明确冲突。
- U01：本地关闭、内嵌、全局默认、双字幕、外挂文件及飞牛下载共享字幕选择 revision。下载、文件构建、延迟 UI 操作及服务端重新解析在提交前校验；旧构建只清理准备文件，不挂载、不回滚新偏好。飞牛下载不再占用画质切换 busy 标志，允许新字幕选择使旧请求失效；显式选择后不自动重新下载旧服务端字幕。原始下载缓存仍由 Dart 会话所有者最终清理，原生提前清理仅限受约束的飞牛临时文件。
- S04：episode `tick()` 和 `onUserSeek()` 使用现有 `peekSeriesSkipPreference`；不修改共享 memory store。正常初始化已预热发布视图；首次未预热时该 API 的同步回退仍需由存储所有者评估，不能据此宣称所有读取都零阻塞。

本批验证记录在收尾时补充；未执行发布预设、版本递增、APK/AAR 构建或设备性能测量。README 与字幕文档由主审集成，不在本分工中修改。

### 此前批次验证

2026-09-20 五项再审修复集成验证：当前主 Kotlin 与 JVM 测试源码在独立目录重新编译，JUnit 全量 **418 项通过**，包含真实 Media3 sink 的配置拒绝/单次回退集成用例；与收尾源码比对一致，`git diff --check` 通过。为避开共享构建目录竞争，本次不是 Gradle/APK 构建，未重建 AAR；`adb devices` 仍无设备。方法与范围见 [主机验证](../performance.md)。

2026-09-20 高位深实现前一批验证：完整 Android JVM **357 项通过，0 失败、0 跳过**，含 24-bit/96 kHz 合成 LPCM 与 FFmpeg PCM24 输出逐字节对比、实际 Media3 转换器测试及输出/倍速/回退策略测试。该计数不包含随后输出状态补强；分批命令和范围见 [主机验证](../performance.md)。下文此前批次的失败、PCM16 转换和未启用 float 描述如标为原始建议，均是历史快照，不是当前状态；未新增真机验证。

2026-09-20 前一批输出状态补强验证：Android JVM 全量 **368 项通过，0 失败、0 跳过**，包括实际 sink 异常优先级、倍速/直通边界和独立回退预算；`git diff --check` 通过。此为五项再审修复之前的快照，不作为后续修改的验证结果。`adb devices` 无已连接设备，仍不代表 ARM 解码、HDMI 或最终音频格式已验收。

- 已修复：FFmpeg 始终注册，输出策略按实际 MIME 决定；系统 codec 偏好改排序，保留兜底候选。
- 已修复：原生 ARM32/ARM64 AAR 补齐 `mp3` decoder，API 23、16 KiB 对齐；提供固定源码和哈希校验的重建脚本。
- 已实现：非 DRM 音频解码错误单次 FFmpeg 回退，排除视频、网络和 FFmpeg 自身解码失败；实际高精度/直通输出错误另限额一次 PCM16 回退，不强制软解。恢复进度、暂停、倍速、音量和音轨。
- 已实现：Exo 首次应用飞牛默认音轨，手动 override 优先；MPV 空元数据返回 null，音频与字幕恢复独立容错，语言别名归一化和歧义匹配保护。
- 已实现：LPCM 单/双声道及 5.1/7.1 映射；非法格式和截断音频头明确失败。固定 scratch/output 缓冲，10 ms/PES 批量提交，保留分片、seek、PTS 和采样率变化语义。
- 已实现：真实 decoder 和输出 encoding/采样率/声道掩码日志，音频列表去重；MPV 汇总音频后端、格式和 A/V sync。
- 2026-09-20 新增：reader 完整保留 20/24-bit 到 PCM24，自动/设备直通正常速度优先 float 输出；PCM 兼容、倍速/音调处理及有界设备输出回退走 PCM16。读取保位深不等于 Android/HDMI bit-perfect；主机检查与设备验收仍分开记录。
- 2026-09-20 输出补强：非正常倍速/音调禁用压缩直通但不强制 FFmpeg；普通 PCM16 原地调速，实际高精度/直通需要切路径时才重建。每播放器独立记录 sink Format、decoder 与输出 encoding，错误优先看 AudioSink 异常格式，不用压缩 renderer 输入猜输出；日志提供 PCM16/PCM24/Float32 标签与重建决定。
- 2026-09-20 五项再审修复：高精度最小缓冲区明确拒绝转为类型化配置异常；系统 decoder 倍速后的精度恢复按源轨历史判断；缺少 renderer Format 时按异常格式、当前源轨和 DRM 证据恢复；sink 复用保留活动输出、释放按代次清理；FFmpeg AC-3 不再触发无效 float 恢复。保持现有三种输出设置，不新增用户开关或恢复预算。
- 保守保留：其他 HDMV 布局未开放；MPV 未切换输出后端或开启 HDMI 直通，macOS 未替换为未经验证的 full 二进制；飞牛未添加未经协议确认的“仅音频转码”参数。

真机验收仍需 API 23 TV、ARM32/ARM64 和 HDMI 输出设备；本轮无设备连接，不能将单元测试和 ELF 检查写成真实解码通过。

2026-09-19 实施验证记录：78 项相关 Flutter 测试、64 项相关 Android JVM 测试通过；后者包含本地 stereo/48 kHz/16-bit TS 的 LPCM 数据与 FFmpeg PCM16 输出逐字节比较。相关 Dart 静态分析、`git diff --check` 和构建脚本语法检查通过。AAR 两种 ABI 的 `mp3` decoder/JNI 导出符号、Android API 23 note、16 KiB LOAD 对齐及系统库依赖已检查，SHA-256 已同步到 [libs README](../../android/app/libs/README.md)。这些是当日记录，不是本次重跑全部原生二进制检查。

2026-09-19 全量 Android 记录：304 项执行，303 项通过，唯一失败为 `NativePlaybackSettingsAppearanceTest` 的选集面板调色板源码断言。该次因共享构建目录的依赖复制冲突，使用已存在的 MPV 依赖并排除 `:media_kit_libs_android_video:downloadDependencies`。

2026-09-20 文档核对回归：Flutter 全量 1580 项通过，`flutter analyze --no-pub` 与播放策略生成检查通过；Android JVM 318 项中 316 项通过、1 项失败、1 项跳过，失败仍为上述选集外观源码断言（第 101 行），跳过为未提供外部 LPCM 样本的可选测试。本次没有排除 MPV 依赖下载任务，也没有为消除失败修改业务代码或测试。测试结果不能证明真机解码或 HDMI 输出可用。

上述 2026-09-20 结果对应执行时快照；整理期间工作区继续出现代码修改，新增位图字幕解析及发布工具等未包含在这些结果中，详见主机验证的时间说明。

## 结论

当前没有应用层通用音频文件转码服务。音频处理分为播放器内部解码、Blu-ray LPCM 字节转换和媒体服务器转码三类。主要风险集中在 Android Exo 的能力选择、异常回退及自定义 LPCM reader；不建议为这些问题全局开启服务端视频转码，也不建议继续扩大网络缓存来解决解码失败。

原始优先级与当前处理情况：

1. 已修复 LPCM 不支持格式阻塞准备及 FFmpeg 注册受启动元数据限制的问题。
2. 已补齐 MPEG MIME 对应的 `mp3` decoder、单次音频回退和输出切换状态恢复。
3. 已收口 LPCM 缓冲和提交粒度，增加音频诊断及样本回归；仍需设备 CPU / GC / 同步测量。
4. 已支持部分多声道 LPCM 布局和高位深读取/float 输出策略；其他布局、硬件高精度输出验收、MPV 输出后端及服务端仅音频转码仍需独立评估。

## 代码地图

下列路径相对于仓库根目录。

| 层次 | 主要文件 | 职责 |
| --- | --- | --- |
| 播放模型 | `lib/features/playback/domain/playback_models.dart` | `PlaybackAudioStream` 的标题、语言、编码、声道和索引；`PlaybackTarget` 的编码提示、音轨列表、首选音轨和转码会话 |
| Emby 元数据 | `lib/features/library/data/emby_api_client.dart` | 解析 PlaybackInfo，选择媒体源和播放 URL，从第一条 Audio stream 取 `audioCodec` |
| 飞牛元数据与转码 | `lib/features/library/data/fntv_api_client.dart` | `play/info -> stream`，读取默认音轨、可用画质，必要时调用 `play/play` 创建转码会话 |
| NAS / 夸克元数据 | `lib/features/library/data/webdav_nas_client_sidecar.dart`、`quark_external_storage_client.dart` | 从 NFO、文件名和已有索引获取编码提示；提示不等于实际选中的音轨 |
| 播放路径与桥接 | `lib/features/playback/application/playback_startup_routing.dart`、`lib/features/playback/data/native_playback_launcher_io.dart` | 按播放器设置路由，向 Android 传递目标 JSON、解码模式和音频输出模式 |
| Exo 音频策略 | `android/app/src/main/kotlin/com/example/starflow/NativePlaybackAudioPolicy.kt` | 始终注册 FFmpeg，按实际音轨 MIME、输出设置与回退状态决定解码输出 |
| Exo 会话装配 | `android/app/src/main/kotlin/com/example/starflow/NativePlaybackSession.kt` | 创建 renderer、track selector、extractor 和 ExoPlayer；切换输出模式时重建播放器 |
| Exo 渲染与输出 | `android/app/src/main/kotlin/com/example/starflow/NativePlaybackRenderersFactory.kt` | 系统及 FFmpeg renderer；`NativePlaybackAudioSink` 按 Format 限制压缩输出并记录实际输出配置 |
| Exo 输出观测与精度历史 | `android/app/src/main/kotlin/com/example/starflow/NativeAudioOutputState.kt`、`NativeAudioPrecisionHistory.kt`、`NativeAudioDecoderPrecisionPolicy.kt` | 区分配置尝试/活动输出，隔离释放回调，按源轨恢复临时精度损失并排除 AC-3 无效重建 |
| Exo TS 解封装 | `android/app/src/main/kotlin/com/example/starflow/NativePlaybackExtractorsFactory.kt` | progressive TS 的有证据 `0x80` 流交给 LPCM reader；其他音频继续使用 Media3 默认解析 |
| LPCM 转换 | `android/app/src/main/kotlin/com/example/starflow/PcmBluRayReader.kt` | PES 音频头、分片残留、保位深大小端转换、PCM16/PCM24 输出及时间戳 |
| Exo 选轨 | `android/app/src/main/kotlin/com/example/starflow/NativePlaybackTrackController.kt`、`NativePlaybackTrackChoices.kt`、`NativeFntvController.kt` | 本地轨道 override、飞牛服务端选轨与会话重开 |
| Exo 音轨身份 | `android/app/src/main/kotlin/com/example/starflow/NativePlaybackAudioTracks.kt` | 跨播放器重建匹配音轨，避免复用失效的 TrackGroup override |
| Exo 错误与指标 | `android/app/src/main/kotlin/com/example/starflow/NativePlaybackCoordinator.kt`、`NativePlaybackRecoveryController.kt`、`NativePlaybackDiagnostics.kt` | 错误分派、视频转码回退、音轨和解码器日志、音频欠载计数 |
| MPV 初始化 | `lib/features/playback/presentation/widgets/player_page_startup_mpv_open.part.dart`、`player_page_startup_mpv_tuning.part.dart` | 创建 media_kit Player，配置视频硬解、网络和缓冲；没有自建音频 decoder |
| MPV 选轨 | `lib/features/playback/application/playback_server_track_resolver.dart`、`lib/features/playback/presentation/widgets/player_page_runtime_actions.part.dart`、`player_page_controls.part.dart` | 服务端 GUID 与本地音轨匹配，调用 `setAudioTrack`，切换飞牛转码会话 |
| MPV 解码库 | `packages/media_kit_libs_android_video_full/`、`packages/media_kit_libs_ios_video_full/`、`pubspec.yaml` | Android / iOS 覆盖为 full libmpv 构建，补齐精简包缺少的 MLP / TrueHD |
| iOS 系统播放 | `ios/Runner/AppDelegate.swift` | `AVURLAsset -> AVPlayerItem -> AVPlayer`，解码能力交给系统 |
| iOS 音频会话 | `ios/Runner/PlaybackSystemSessionBridge.swift` | 共享 `AVAudioSession` 持有者、中断与路由变化；不负责压缩音频解码 |
| 飞牛会话释放 | `lib/features/playback/application/fntv_session_owner.dart`、`lib/features/playback/data/native_fntv_service.dart` | 管理活动和待处理转码会话，退出及迟到结果释放 |
| 用户设置 | `lib/features/settings/domain/app_settings.dart`、`lib/features/settings/presentation/playback_settings_page.dart`、`android/app/src/main/kotlin/com/example/starflow/NativePlaybackSettingsController.kt` | 全局 Exo 输出模式及当前播放会话的输出模式菜单 |

## 当前处理流程

### Android Exo

```text
TV 标识 + 音频输出设置 + 可选单次音频回退状态
  -> 始终注册系统 renderer 和 FFmpeg 扩展
  -> Media3 extractor 发现实际音轨 Format
  -> NativePlaybackAudioPolicy / NativePlaybackAudioSink 按 MIME 判断输出
  -> DefaultTrackSelector 选择 renderer 和音轨
  -> 系统 MediaCodec 解码、设备可用的压缩直通或 FFmpeg 软件解码
  -> AudioSink / Android 音频输出
```

当前策略矩阵：

| 情况 | 禁用该轨压缩输出 | FFmpeg 扩展 |
| --- | --- | --- |
| TV，自动，实际 E-AC-3 / JOC | 是 | 已注册 |
| 手机自动，或 TV 的其他实际 MIME | 否，按设备能力选择 | 已注册，通常系统优先 |
| 任意设备，PCM 兼容 | 所有音轨禁用压缩输出 | 已注册，不等于强制软解或双声道 |
| 设备直通 | 通常否，允许设备能力决策 | 已注册，不保证一定直通 |
| 非默认倍速或音调 | 是，所有模式使用解码输出 | 不因此强制 FFmpeg |
| 符合条件的单次音频解码失败回退 | 对失败 MIME 使用解码输出 | 优先 FFmpeg，仍需该格式受支持 |
| 实际高精度/直通输出失败回退 | 是，使用 PCM16 兼容输出 | 不改变原解码器选择策略 |
| 启动编码提示为空或 AAC，但实际有 DTS / TrueHD | 按实际 Format 与模式判断 | 已注册，不被启动提示屏蔽 |

“设备直通”实际是允许 Media3 按设备能力选择直通，并非无条件输出压缩码流。“PCM 兼容”是禁用压缩直通，并不等于强制 FFmpeg，也不等于明确执行双声道 downmix。

系统 codec 偏好只调整顺序，不丢弃其他候选。系统音频解码失败在库支持时触发一次 FFmpeg 重建，排除 DRM、网络、视频及 FFmpeg 自身解码失败。AudioTrack 初始化/写入失败按实际 sink 高精度或直通证据，独立回退一次 PCM16；FFmpeg renderer 的输出失败也可走这条路径，已为 PCM16 或无输出证据时不猜测重试。两类恢复保留进度、暂停、倍速、音量与音轨身份，不改变视频解码策略，也不扩大原启动期限。

FFmpeg AAR 当前包含 ARM32 / ARM64，Media3 版本为 `1.10.1`，FFmpeg 为文档固定的 `release/6.0` commit。编译进来的 decoder 是 `ac3 eac3 mlp truehd dca mp1 mp2 mp3`。这不是 full FFmpeg，不含 x86 原生扩展，不能把 MPV 的解码范围套用到 Exo 上。

### Blu-ray LPCM

只对 progressive TS 生效，不接管 HLS extractor。`0x80` 必须有精确的 `pcm_bluray` 提示或有效 ES 级 HDMV 注册描述符；冲突或截断描述符不接管。

```text
TsExtractor -> NativeTsPayloadReaderFactory -> PesReader
  -> PcmBluRayReader.packetStarted / consume
  -> 4 字节音频头
  -> 完整采样帧 + 跨 TS 分片残留 + 有效声道映射
  -> 16-bit 或 20/24-bit 完整大端转小端
  -> AUDIO_RAW / PCM16 或 PCM24 -> Media3 AudioSink
  -> 正常速度高精度 float，或 PCM16 兼容/倍速路径
```

当前支持布局 `1 / 3 / 9 / 11`，对应单声道、双声道、5.1、7.1，以及 48/96/192 kHz 的 16/20/24-bit 输入。其他布局、非法头和截断头明确失败，不吞掉输入无限等待。reader 不重采样或 downmix，20/24-bit 三字节样本完整保留到 PCM24；下游兼容分支的 PCM16 转换仍会损失精度。

使用固定 24 字节采样帧缓冲、46,080 字节输出缓冲及复用的 `ParsableByteArray`，按最多 10ms 或 PES 边界批量提交。按实际字节宽度与累计采样帧计算时间戳，每个 PES 重读头，seek 清除残片与时间基线；位深变化发布新格式，单声道填充及多声道顺序也由 reader 处理。

已有分片越界、sampleData 参数、PES 包头和时间戳修复应保留，不能在优化缓冲时回退。

### 内置 MPV

`media_kit -> libmpv -> FFmpeg` 负责解封装、压缩音频解码、必要的音频格式转换和输出。应用只调播放、倍速、音量、选轨等控制，没有把音频样本搬到 Dart 处理。

- Android / iOS 使用本地覆盖的 full 构建；Android 固定上游 `v1.1.8`，iOS 为 `v0.6.0` full xcframework。
- 当前 media_kit `1.2.6` 在 Android 真机默认设置 `ao=opensles`。项目未覆写为 AudioTrack，也未设置 `audio-spdif`，不能认为 Exo 的直通设置同样影响 MPV。
- MPV 的 `hwdec=auto-safe/auto/no` 是视频硬解设置，不是音频 FFmpeg 开关。
- macOS 仍使用默认依赖构建，未像 Android / iOS 一样覆盖为 full；应在平台能力表中单列，不能假定三端 TrueHD 能力相同。Windows / Linux 也应按其实际依赖验证。
- MPV 退出后串行等待旧播放器完成释放，这有助于避免重开时叠音，应保留。

### 服务端转码

- Emby 优先使用返回的直链，其次使用 `TranscodingUrl`。Android 的视频不支持回退另由恢复控制器处理；这不是仅音频兼容回退。
- 当前工作区的飞牛实现已包含服务端画质转码：调用 `play/play` 请求 H.264 视频、AAC 音频和 `channels=2`，返回 HLS 会话。
- 飞牛转码时切音轨需要创建新服务端会话，不能只切当前 HLS 的单条 AAC 轨。原始音轨列表用于服务端选择，不代表转码输出仍有同样的本地音轨。
- 当前飞牛转码不是视频 copy + 仅音频 AAC；只为音频兼容启用此流程会同时改变视频链路、画质和服务端负载。支持仅音频转码前必须确认服务端协议，不猜测字段。

## 实施前问题快照

以下各项描述的是 2026-09-19 修复前的代码和 AAR，均已按上文状态实施；保留其原因分析用于防止回归。段落中的“当前”、源码行号及旧 decoder 列表只指当时快照，不适用于现工作区。

### P1：LPCM 不支持的声道布局会阻塞整部媒体准备

位置：`PcmBluRayReader.kt` 的 `createTracks`、`readHeader`。

reader 提前注册音轨，但 `channelLayout != 3` 时只设置 `unsupported` 并吞掉输入，不调用 `format`，也不显式失败。Media3 `ProgressiveMediaPeriod.maybeFinishPrepare` 要求所有已注册 SampleQueue 都有 upstream format，因此只要存在这样的 LPCM 轨，整部 TS 就可能一直 preparing，即使另有可播视频或音轨。

使用当前构建的类进行了隔离 JVM 验证：layout 3 发布格式，layout 9 和 11 已注册音轨但不发布格式。这不是仅凭“不支持多声道”推断。

建议：在不支持首个 LPCM header 时尽快返回明确的“不支持音频格式”错误并提供切换播放器入口；若要保留其他轨道播放，需要设计正确的不支持轨道描述，不能发布虚假的双声道 PCM。后续多声道支持应包括布局映射、补齐声道规则和真实样本测试。

### P1：解码器是否存在被启动元数据锁定

位置：`NativePlaybackSession.kt` 的 `initializePlayer`，`NativePlaybackAudioPolicy.kt` 的 `shouldEnableFfmpegAudioDecoder`。

只读取一次 `PlaybackTarget.audioCodec` 决定是否注册 FFmpeg，而实际音轨随后才由 extractor 解析。以下场景会遗漏软件解码能力：

- NAS / STRM 缺少编码元数据，实际是 DTS / TrueHD。
- 第一条或默认音轨提示 AAC，但另有 DTS / TrueHD 音轨。
- 手机自动模式或设备直通模式的 AC-3 / E-AC-3，在设备既不能直通也没有可用系统 decoder 时，FFmpeg 仍未注册。

音轨菜单又会过滤 `isTrackSupported == false` 的轨道，用户可能连手动选择都无法操作。TV 自动 DDP 的 PCM 策略同样不会随真实选中音轨变化。

建议：将“可用 decoder 注册”与“选择哪个 decoder / 输出模式”分离。注册 FFmpeg 作为备选不代表所有音频都强制软解；按真实 `Format.sampleMimeType`、用户模式和设备能力决定优先级，启动元数据只作为提示。不要为了补元数据额外发网络探测。

### P2：MP1/MP2 的 FFmpeg 构建与 Java 映射不匹配

位置：`android/app/libs/README.md:7`、`:15`，`NativePlaybackAudioPolicy.kt` 的 MPEG audio 分支，以及打包 AAR。

Media3 `FfmpegLibrary.getCodecName` 将 `audio/mpeg`、`audio/mpeg-L1`、`audio/mpeg-L2` 全部映射到 `mp3`。本地 AAR 的 Java 字节码与此一致；JNI 调用按 decoder 名称查找，而 native 动态符号只有 `ff_mp1_decoder`、`ff_mp2_decoder`，没有 `ff_mp3_decoder`。

因此当前 MP1/MP2 的“开启 FFmpeg”策略不会让该扩展实际支持这些 MIME。系统 decoder 仍可能播放，但软件兜底不成立。

建议：按 Media3 的实际映射补齐 `mp3` decoder 后重建 AAR，保留 API 23 和 ARM32 / ARM64，再校验 SHA-256、许可证、两种 ABI 的 `supportsFormat` 和真实 MPEG Layer I/II 样本。仅增加 policy 布尔测试无法发现这个问题。

### P2：启用 FFmpeg 不等于系统解码失败后回退 FFmpeg

位置：`NativePlaybackRenderersFactory.kt:21`，`NativePlaybackSession.kt` 的 `setEnableDecoderFallback`，`NativePlaybackCoordinator.kt` 的 `onPlayerError`。

`EXTENSION_RENDERER_MODE_ON` 把 FFmpeg 排在系统 renderer 后。系统报告支持但初始化或运行时失败时，`setEnableDecoderFallback(true)` 只在该 MediaCodec renderer 的 codec 列表内尝试，不会自动跨到 FFmpeg renderer。现有应用错误分派没有音频专用 renderer 回退。

建议：保持普通自动模式的系统优先；对明确的兼容模式或经过验证的问题 codec/设备选择 FFmpeg 优先，或在可识别音频解码错误后进行一次有预算的重建。必须区分音频 decoder 失败、AudioSink 输出失败、网络失败和视频失败，不应将视频也强制软解。

另外，`buildMediaCodecSelector` 当前是过滤掉非首选类型，不是重新排序。只要某类 decoder 存在，就丢弃另一类，即使首选类全部初始化失败也不能尝试它们。应保留完整列表，首选项在前、其余作为 fallback。

### P2：切换音频输出模式丢失已选音轨和倍速

位置：`NativePlaybackSession.kt` 的 `restartPlayerWithAudioOutputMode`。

重建前仅保存进度和 `playWhenReady`，没有恢复音频选择及 playback parameters。新 ExoPlayer 会使用默认选择和默认速度。用户为某条无声音轨切到 PCM 时，可能同时被切回其他音轨，造成“修好”的误判。

建议：保存音轨指纹、倍速、暂停状态，并在新轨道出现后匹配恢复。不要跨播放器直接复用旧 TrackGroup override。可复用飞牛画质重开已有的状态恢复思路，收口成小范围会话快照逻辑。

### P2：飞牛默认音轨在 Exo 首次播放中没有应用入口

位置：`NativeFntvController.kt` 的 `onTracksReady`，`NativePlaybackCoordinator.kt` 的 `onTracksChanged`。

`onTracksReady` 只执行画质切换时注册的恢复闭包；首次直接播放没有消费 `preferredAudioStreamId` 来选音轨。飞牛返回的偏好用于 Dart 的编码提示，但 Exo 仍按自身规则选轨，两者可能不一致。MPV 有 `_applyStartupServerTracks`，两端行为不对齐。

建议：区分首次默认选轨、用户主动选轨、会话恢复。首次轨道就绪后应用一次服务端 GUID 到本地 Format 的匹配；用户选轨后不再被默认选择覆盖。

### P2：空音轨元数据被当异常，可能连带跳过字幕恢复

位置：`lib/features/playback/application/playback_server_track_resolver.dart:165`。

公开 helper 返回 nullable，但 `_preferredStream` 对空列表抛 `StateError`。普通 Emby / NAS 经常没有完整 `audioStreams`；MPV 启动时会因此记录不必要的 FNTV 选轨警告。若有字幕而无音轨元数据，同一 try 块后半部分的字幕恢复也被跳过。

建议：空列表返回 null，音轨和字幕各自独立恢复，增加缺失元数据及混合缺失的测试。语言别名与序号兜底也应覆盖，不能只测试标题、语言齐全的两条音轨。

## 实施前优化建议

下面保留原始建议，属于实施前快照。固定缓冲、批量提交、输出诊断、音轨日志去重、MPV 音频汇总及高位深路径已实施；更多布局及其他输出后端仍需单独评估。不能将理论小包次数当作测得的 CPU 改善。

### LPCM 小包分配与提交

`consume` 每个有完整帧的分片创建输入 `ByteArray`、输出 `ByteArray` 和 `ParsableByteArray`，并各调用一次 `sampleData` 和 `sampleMetadata`。

按 48 kHz / 双声道 / 24-bit 输入及约 184 字节 TS payload 理论估算，音频部分每秒约 1,600 个小片；192 kHz 时约 6,300 个。实际数值受 PES/TS 头、打包和缓冲影响，这不是设备性能测量。

建议分两步：

1. 复用容量受限的 scratch buffer 和 ParsableByteArray，避免逐片分配；按已验证契约处理输入偏移、残片和有效输出长度。
2. 合并成 PES 或有界 10-20 ms 音频块再提交 metadata，降低 SampleQueue 和 decoder 调度频率；严格处理 PTS 跳变、采样率变化、seek 和末包刷新。

先测分配次数、提交次数和连续 seek 正确性，再在低内存 API 23 TV 测 CPU、GC、音频 underrun 和 A/V 同步，不先扩大缓冲。

### 高位深与多声道

- LPCM 的 20/24-bit 到 PCM16 是确定的精度缩减，不是无损格式转换。若追求高保真，应独立设计自动/兼容输出策略，不直接把全局 float output 打开。
- 当前 Exo 未启用 float output；Media3 默认使用 PCM16 兼容路径。高精度、倍速处理和设备兼容性需要一起验证。
- `mha` 被归为 TrueHD 提示，但 MPEG-H 与 TrueHD 不是同一个解码能力；编译了 `mlp` 也不能单凭 policy 判定 Media3 支持所有 MLP 容器和 MIME。应按 MIME 映射和样本建立能力表。
- MPV 若需要 HDMI 直通，应作为独立功能验证 output backend、功放能力、声道、倍速和音量行为；不要直接替换稳定的 OpenSL ES 默认输出。

### 可观测性

现有结构化本地日志有效：Exo 记录输入音轨 MIME、声道、采样率、支持/选中状态，性能汇总记录真实音频 decoder 名称和 underrun。旧 trace helper 静音不代表应用日志关闭。

建议补充：

- 区分 `ffmpegConfigured`、`ffmpegAvailable`、`selectedAudioDecoder`，现有布尔字段只代表配置。
- 记录实际输出 PCM 位深、采样率、声道、直通状态和输出设备变化，而非只记录输入格式。
- 音频 decoder / AudioSink 错误按结构化错误类型记录，附恢复决定和次数。
- MPV 性能汇总目前主要读取视频 decoder / 掉帧，应补充 audio codec / audio params / 输出后端 / A/V sync；静态字段在轨道或设备变化时采集，不新增网络请求或高频轮询。
- 对重复音轨列表日志去重，保留真正的切轨和能力变化事件。

## 原始审查验证

2026-09-19 初始审查阶段未修改播放器实现和依赖；其后的实施和回归结果已列在本文开头。以下只记录初始审查证据。

- 运行 5 个相关 Flutter 测试文件，59 项通过：server track resolver、FNTV API、native FNTV service、Emby API、playback models。
- 运行 7 个相关 Android JVM 测试类，43 项通过：audio policy、LPCM reader、extractors factory、session、FNTV controller、track choices、performance tracker。
- 用当前编译的 LPCM reader 做隔离 JVM 检查，验证多声道布局未发布格式。
- 用 `javap` 检查打包 AAR 的 MPEG MIME 映射，用 NDK `llvm-nm -D` 检查 native decoder 符号；AAR SHA-256 与 libs README 一致。
- 对照 Media3 `1.10.1` 的 `DefaultRenderersFactory`、`MediaCodecRenderer`、`FfmpegLibrary`、`ffmpeg_jni.cc` 和 `ProgressiveMediaPeriod` 源码确认 renderer 排序、fallback 范围、名称查找及 prepare 条件。

现有测试不足以证明真实解码和 HDMI 输出可用。后续应添加 ARM32 / ARM64 真机能力检查，以及 AC-3、E-AC-3/JOC、TrueHD、DTS/DTS-HD、MP1/MP2、双声道/多声道 LPCM 的短样本回归。每组至少覆盖无编码元数据、多音轨跨编码切换、PCM/自动/直通切换、seek、倍速、暂停恢复和切集。

代码审查期间工作区有其他进行中的修改，尤其飞牛转码和文档。涉及这些文件的结论是本轮读取的快照，实施前应重新核对最新实现；本报告没有覆盖或回退其他人的改动。

## 上游依据

- [Media3 1.10.1 FfmpegLibrary](https://github.com/androidx/media/blob/1.10.1/libraries/decoder_ffmpeg/src/main/java/androidx/media3/decoder/ffmpeg/FfmpegLibrary.java)
- [Media3 1.10.1 DefaultRenderersFactory](https://github.com/androidx/media/blob/1.10.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/DefaultRenderersFactory.java)
- [Media3 1.10.1 MediaCodecRenderer](https://github.com/androidx/media/blob/1.10.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/mediacodec/MediaCodecRenderer.java)
- [Media3 1.10.1 ProgressiveMediaPeriod](https://github.com/androidx/media/blob/1.10.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/source/ProgressiveMediaPeriod.java)
- [Media3 1.10.1 FFmpeg JNI](https://github.com/androidx/media/blob/1.10.1/libraries/decoder_ffmpeg/src/main/jni/ffmpeg_jni.cc)
