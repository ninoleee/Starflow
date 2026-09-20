# 播放器流畅度审查

审查及修复日期：2026-09-20。范围是当前工作区的全部播放路径及其共享启动、控制、字幕、存储和媒体会话链路，包含已有未提交修改。最初只读审查，随后按用户要求在当前任务实施修复；下方“优先发现”保留为修复前快照，不代表问题仍原样存在。未递增版本或运行发布预设。

## 本次处理状态

- **P01/P03 已实施**：iOS 与 Android 共用延迟解析队列，保留前后集与未解析元数据；切集通过既有 Flutter resolver 通道请求单集，30 秒超时、代次校验、迟到转码结果释放。解析失败保留旧播放器；更换 request 前保存并释放旧播放器，清空 player 和保存阈值，再异步读取新集记忆。解析成功但新媒体解码失败仍走原有重试/退出，不承诺回滚旧解码实例。
- **P02 已实施**：iOS/Android 进度更新由串行后台写入，同媒体待写进度合并，强制保存不可被后续 tick 越过。缓存历史最大时间戳，iOS 日期解析器加锁复用；外部原文变化重新读取。iOS 启动记忆异步准备，强制保存申请有限系统后台时间；Android runtime 跳过规则使用发布的只读快照。写入完成通知 Flutter 失效历史缓存。同步查询接口仍保留于启动/选集等需要最新结果的路径，进程被强杀前未完成的写入不能保证落盘；共享 JSON 的跨运行时并发读改写不具备数据库事务保证。
- **P04/P05 已实施**：MPV 稳定播放后即进入可操作状态，轨道偏好/外挂下载随后异步准备；默认倍速和全局关闭字幕先应用。自动轨道通过 `PlaybackTrackGuard` 检查播放器代次及手动操作 revision，迟到任务不再选轨。TV 长按使用 `PlaybackSeekCoalescer` 累计目标、250ms 合并、首下立即、松手提交；切集、离页、失焦和后台取消输入。Scaffold 使用稳定 key。
- **P06/P07 已实施**：AVPlayer preroll 在途防重入，处理失败、取消和迟到结果，KVO/seek 回调转 MainActor。URL 扩展名、主机名和查询不再作为直播证据；未知先用点播偏好，ready 后由 indefinite 时间轴调整直播缓冲，直播不 preroll。保留系统自主缓冲行为。
- **附带处理**：原生启动日志区分 exo/avplayer，iOS 容器呈现与 `playing` 指标不再命名为真实首帧。桌面外部播放器用专属临时播放列表目录、唯一分配和十分钟清理节流，不遍历系统临时根目录；不会扫描或删除旧版根目录遗留播放列表。
- **仍需测量/未扩展范围**：全屏 MPV 属性差异写入、AVPlayer 连续精确 seek 容差、实际首帧像素指标、设备硬解/刷新率/温控和缓存调参未在无设备证据下改动。新建直播功能由其他工作处理，不在本次点播播放器修复范围。

验证记录以 [performance.md](performance.md) 本次实施条目为准；下面最初 148 Flutter / 80 JVM 的审查结果仅是修复前快照，不可当成本次回归。

最初审查收尾期间其他任务继续调整播放器日志/诊断与飞牛选轨。当时重新核对后问题仍存在，随后实施状态见上；最初专项测试不覆盖后续修复。易变化的 Dart 路径按函数名定位，行号不作为长期接口。

组件边界以 [architecture.md](architecture.md) 为准，导航见 [code-map.md](code-map.md)，字幕边界见 [subtitles.md](subtitles.md)，本轮主机证据见 [performance.md](performance.md)，设备验收方法见 [performance-device.md](performance-device.md)。本次没有连接 TV 或运行 iPhone、桌面 GUI、浏览器实际播放，不能给出帧率提升百分比。

## 十方向复审补充（2026-09-20）

以下 P01–P04 指外部 `starflow-ten-angle-review-2026-09-20.md` 的编号，不是本文下方早期审查的同名编号。本文“优先发现（修复前快照）”及最初 148 Flutter / 80 JVM 记录原样保留，不作为此轮通过证据。

- **P01**：播放器实例回收与页面 FNTV owner 终止分开。错误/卡顿硬恢复只释放旧实例会话，页面退出才关闭 owner；release/close/迟到 retain 对同一会话去重。解析过程中取消的返回值仍先接管再释放，不转交新播放器。
- **P02**：恢复绑定同步用户意图 revision、播放意图、前后台状态和 player 身份。暂停、seek（含 TV 合并输入）、手动切集、退出或失活作废旧恢复；延迟确认、play 返回后的 seek、硬回收和新目标解析均验证当前性。已提交给原生引擎的单条命令不等于可撤销，本轮阻止其后续陈旧命令和重建提交。硬重建取消后保留显式重试入口，不自动继续或永远显示加载。
- **P03**：iOS 自动与手动相邻集请求独立判优先级，新手动请求可替代 pending 自动请求。AVPlayer 的 play/pause/rate/seek 命令经同步 intent 边界，包括系统播放控件和 remote command；后续明确操作取消旧自动切集，迟到转码结果仅释放。播放器/异步记忆准备 generation 与 episode resolver generation 分离，取消切集不误伤当前媒体的记忆准备。
- **P04**：preroll 返回 false 时，仅 item failed 或存在 item.error 才报告失败；无错误的时间/速率中断按取消收尾，不强行 play。显式操作取消 gate 和启动超时，迟到成功回调不得恢复播放；启动自身 seek/play 绕过用户命令 bookkeeping。
- **T01–T04**：媒体 intent、pointer、菜单回退和大字 chip 高度修复见 [TV 焦点清单](tv-focus.md)。没有修改 README、版本、发布脚本、AppDelegate、原生记忆存储或 Android 原生文件；其他任务修改不纳入本轮文件归属。

主机验证：首批新增恢复/输入测试 19 项通过；最终扩展回归、Swift runner 和布局截图结果待本轮收尾记录。没有实机弱网播放、iPhone AVKit 手势或物理 TV 遥控/空鼠验收，不声明帧率或真实首帧改善。

## 早期审查结论

可以提高，优先空间在启动关键路径、连续 seek 和主线程存储，不是普遍缺少缓存或播放器文件太大。需要分别观察四种体验：点击到画面、画面出现到可操作、连续播放掉帧/缓冲、seek/切集恢复。减少启动等待不等于视频解码 FPS 提高。

优先级表示建议处理顺序：P1 是明显放大等待/主线程工作或影响播放正确性的问题；P2 是确定存在的冗余工作、条件性卡顿风险或策略缺陷；P3 是需要设备证据后再决定的调参项。

## 播放路径

| 路径 | 实际实现与入口 | 流畅度边界 |
| --- | --- | --- |
| Android、iOS、桌面 MPV | `PlayerPage` -> `player_page_startup_mpv*.part.dart` -> media_kit 1.2.6 / media_kit_video 2.0.1 -> libmpv | Flutter 控件/文本字幕与原生解码分开；Android/iOS full 二进制覆盖不等于桌面能力相同 |
| Android ExoPlayer | `NativePlaybackActivity` -> Coordinator / Session / RuntimeController；Media3 1.10.1 | 手机/TV 都使用 SurfaceView；视频、音频、字幕和应用主线程各有成本 |
| iOS AVPlayer | `NativePlaybackViewController`、StartupGate、BufferingTuning、StallRecovery、MemoryStore | 使用系统解码和 AVPlayerViewController；队列解析、启动策略、历史保存仍由应用负责 |
| Web | 相同 PlayerPage，media_kit 的 HTMLVideoElement 后端 | 不是 libmpv；MPV 调参方法在 Web 直接返回；受浏览器编码、自动播放与 CORS 限制 |
| 外部系统播放器 | `system_playback_launcher_io.dart`，移动端平台通道、桌面临时 M3U | 应用能优化启动/文件清理，不能控制第三方播放器解码、掉帧与进度回传 |
| 服务端转码 | `fntv_api_client.dart`、`native_fntv_service.dart`、`fntv_session_owner.dart`，以及 Exo Emby 回退 | 不是另一套客户端 decoder；NAS 编码能力、媒体传输与客户端输出分别测量 |

共同入口为 `PlaybackStartupCoordinator -> PlaybackTargetResolver -> PlaybackEngineRouter -> PlaybackStartupExecutor`。`playback_stream_relay_service_io.dart` 保留了实现，但本轮搜索未发现生产播放链调用其 `prepareTarget`；不能把这个未接入路径的预热当作当前所有 MPV 首播成本。

## 优先发现（修复前快照）

### P01 / P1：iOS 首播前串行解析剩余剧集

位置：`player_page_startup_mpv_launch.part.dart` 的 `_launchNativePlaybackTarget / _resolveNativePlayableEpisodeQueue`。

Android 走延迟解析队列，iOS 则在 `launcher.launch` 之前从当前集循环到本季最后一集，并逐项 `await targetResolver.resolve`。当前集地址已经可播也需要等待后续地址准备。需要请求的集数越多，启动越慢；循环没有自身的整体截止时间。全部已解析的普通直链可能很快，不能把每集都等同于一次网络请求；飞牛会重新解析，STRM/云盘等未解析目标也会走网络。

提前取得的临时地址还可能在数集之后过期。结果队列从当前集开始重新构造，当前集之前的条目也不再传给 iOS。

建议让 iOS 复用 Android 的按需 resolver 契约：先打开当前集，保留完整元数据队列，最多预解析相邻一集。保留失败时旧视频和队列、会话代际、地址有效期及迟到转码会话释放。测试要明确断言首播前后续集解析次数为零，不能只测试队列序列化。

### P02 / P1：原生历史保存仍阻塞主线程

位置：`NativePlaybackViewController.swift:795 / 936`、`NativePlaybackMemoryStore.swift:28 / 147`、`PlaybackMemoryPolicy.swift:17 / 34`；Android 对应 `NativePlaybackRuntimeController.kt:265`、`NativePlaybackMemoryStore.kt:22 / 64 / 196`。

- iOS 的 2 秒周期观察在 main queue，约每 10 秒进度变化触发保存。保存遍历 items/series 的时间戳，每条解析新建日期 formatter，再校验和编码整个 JSON。暂停、退出、切集还有强制保存。
- iOS 已有原文/解析快照缓存，不能继续称为“每次重新解析整个历史”。当前残余热点是时间戳扫描、目标解码、全量编码和持久化；series 不按最近 20 条裁剪。
- Android runtime 也在 main looper，普通保存的 JSON 构建仍在调用线程；`force=true` 进一步调用 SharedPreferences `commit()` 同步落盘。改成 `apply()` 只能覆盖部分磁盘工作，不能解决编码成本或生命周期写入顺序。
- Dart 已合并冷读，较大历史已通过 compute 编解码，不将此前全量主 isolate 编码结论继续套用到现状。

本轮优化编译的 macOS 合成暖保存探针中，20/200/1000 条 series 记录的中位耗时约为 10.56/89.11/435.04ms。具体环境、原始值和边界记录在 performance.md。这是主机同步工作量证据，不是 iPhone/Android 帧时测量，也不能把全部耗时归因于闪存。

建议在串行存储所有者中缓存最大时间戳、复用 formatter，将重编码和写入移出 UI 线程并合并同一媒体待写进度。切集/退出保留可靠的最终快照，Flutter/原生交替写入时重新读取或失效缓存；不删除历史/字幕偏好来制造提速。

### P03 / P1：iOS 切集会把旧进度保存到新集

位置：`NativePlaybackViewController.swift:528` 的 `advanceToAdjacentEpisode`、`:84` 的 `configurePlayer`、`:892` 的 `teardownPlayback`。

当前顺序为：保存旧进度 -> `request = nextEntry.request` -> `configurePlayer()` -> `teardownPlayback()` 再次强制保存。此时 player 仍是旧实例，但 itemKey/seriesKey/target 已来自新 request，旧时间会写入新集。随后 configurePlayer 又从新集 key 读取 resume，可能让新集从旧集的位置开始，甚至因完成阈值覆盖原有续播记录。

这是代码调用顺序可确认的正确性问题，不是设备测速推断。应在更换 request 前完成旧实例字幕/进度快照及 teardown，或让会话持有不可变的目标身份。增加旧集/新集不同时长、手动切集、自然结束、旧字幕偏好、原有新集历史的场景测试；存储单元测试通过不能证明调用者传对了身份。

### P04 / P2：MPV 可操作状态被字幕等待阻塞

位置：`player_page_startup_mpv_open.part.dart` 的 `_openEmbeddedPlayback`、`player_page_runtime_actions.part.dart` 的 `_applyStartupPlaybackPreferences / _awaitAvailableSubtitleTracks`，以及 `_initialize / _togglePlayback / _seekRelative` 的 `_isReady` 门控。

首帧、play 和稳定播放确认完成后，仍串行等待默认偏好、服务端轨道和外挂字幕，最后才设 `_isReady=true`。默认字幕为 auto/systemLanguage；无真实字幕轨时 `_awaitAvailableSubtitleTracks` 等满 3 秒，双字幕失败回退还可能重复等待。服务端外挂下载也在这条路径中。

此时画面可能已经显示，不能说必然黑屏 3 秒；但 Starflow 的 TV 播放/暂停、seek 和系统会话仍受 `_isReady` 限制。media_kit 自己的非 TV 控件不一定受同一个门控。

建议分离“媒体可操作”和“轨道偏好准备完成”，让无字幕和非关键外挂下载不阻挡控制。自动选择保持代际保护，不能覆盖用户在等待期间的手动选择；倍速、初始静音/字幕可见性等首帧前必要设置单独保留。测试覆盖无字幕、字幕迟到、下载失败/取消和用户提前切轨。

### P05 / P2：MPV TV 长按没有 seek 合并

位置：`player_page.dart` 的 `_handleTvSeekKeyEvent`、`player_page_controls.part.dart` 的 `_seekRelative`。对照 `NativePlaybackRemoteController.kt:265`。

MPV 每个 KeyRepeatEvent 都 `unawaited(_seekRelative(delta))`，基准直接读取 player.state.position，没有待提交目标累加器、250ms 合并窗口或松手提交。底层 media_kit 的 native seek 虽然串行发命令，但不会替应用丢弃中间目标，也不会在命令调用处立即更新 position。因此快速输入可能按迟到进度重复算目标，并反复触发实际定位/缓存失效。

Android Exo 已有 250ms 合并、最后目标累加、松手提交和旧播放器/设备/按压身份校验，不应重复修它。MPV 建议实现同等边界，保持首下立即响应、10/30/60/120 秒加速档及取消后的会话隔离。收益重点是远程长按快进，不是正常播放 FPS。

### P06 / P2：AVPlayer 预热会被状态通知重复启动

位置：`NativePlaybackStartupGate.swift:143 / 195`。

`beginPlayback` 只检查 didComplete，该字段直到 preroll 回调后的 play 才设定。preroll 在途时 keep-up/buffer 等观察器继续调用 evaluate -> beginPlayback，可以再次 preroll。

本轮以 ReadyItem 和覆盖 preroll 的 CountingPlayer 跑真实 KVO 路径：初次 start 调用 1 次，在首次回调仍未完成时发送两个缓冲通知，累计调用变为 3 次。这证明缺少在途防重入，不证明特定设备一定黑屏。

建议使用明确的 waiting/seeking/prerolling/started/cancelled 状态；预热只能有一个在途操作，处理 completion 的成功值、取消以及晚到通知。编译本文件还报告已有的 MainActor/Sendable 回调隔离警告，状态回调应统一到 MainActor，而非依赖 @MainActor 标注自动跳线程。

### P07 / P2：AVPlayer 把点播 HLS 当直播调参

位置：`NativePlaybackBufferingTuning.swift:25 / 83`、`NativePlaybackViewController.swift:112 / 340`。

只要 URL 以 `.m3u8` 结尾就 isLiveStream=true，播放页没有传显式覆盖。点播 HLS 因而得到 8 秒 preferredForwardBufferDuration、暂停可用网络和无 preroll 分支，而普通远程点播是 24 秒加 balanced gate。本轮策略探针确认相同 VOD URL 的推断配置为 8 秒，显式 isLiveStream=false 为 24 秒。

HLS 是传输格式而非直播标记。建议传递可靠媒体类型/已知点播信息，必要时用 AVPlayerItem 的时间轴信息修正策略；未知类型不因扩展名强行判直播。不额外下载完整媒体或无依据探测所有地址。8/24 秒是系统偏好而非强制缓存量，是否增加缓冲仍需同一 VOD HLS 真机验证。

## 次级改进与测量项

- **MPV 视频子树身份**：`PlayerPage.build` 根据 `_isReady` 将 Scaffold key 从 null 改成 `player:ready`，Flutter 会销毁/重建其整棵子树，包含 Video、控件、字幕订阅和 wakelock。它不等于 Player/decoder 被 dispose，但就绪边界没有必要如此重建。建议稳定容器身份，用非破坏性的方式表达测试/状态标记，并检查焦点及全屏状态保持。
- **首帧统计口径**：`_launchWithNativeContainer` 将所有 native launch 都标为 exo；iOS 平台返回 true 是呈现容器完成（`AppDelegate.swift:365`），不是首帧。AVPlayer metrics 又把 timeControlStatus.playing 当首帧。应单列 avplayer/presented/first-video-frame/interactive，未修正前不跨内核比较该字段。
- **AVPlayer seek**：遥控快进和定位统一 zero tolerance，远程长 GOP 可能增加解码到精确时间的等待。先合并连续用户目标，再评估有限容差；不能更改精确续播和字幕时轴语义后仍称行为不变。
- **MPV 属性写入**：全屏切换调用整套 `_applyMpvPerformanceTuning`，重写网络、缓存、字幕和画质属性；可以按实际配置差异写入。低频成本，优先级低于启动/seek/存储。
- **网速/控件**：MPV 标签约 1 秒读取本地 cache-speed，性能采样约 5 秒；TV 标签随控制层销毁，非 TV 有 visible 门控。可共享采样、补超时和旧 player 校验，但不要把这些本地读取描述成网络测速洪峰。根 build 对整份 settings 的订阅可缩小，不能据此声称每个 position tick 都在整页 setState。
- **解码与画面连续性**：Exo 已用 SurfaceView 和默认 Media3 调度；MPV 目前默认 performanceFirst，不能再声称默认启用高成本质量档。自动/硬解设置需要核对实际 decoder/hwdec-current、输出拷贝路径、HDR、音频 underrun、掉帧和温控。24/23.976fps 内容在 60Hz 上的均匀性与 UI 帧率是两个问题，刷新率匹配需验证具体系统/屏幕支持。
- **缓冲内存**：Exo 低内存 TV 首播 32/48 MiB、切集至少 48 MiB，MPV 低内存 TV 按来源/负载限制前向 64/96 MiB 和回看 16 MiB。这不是应用总内存。保持现有保守档位，比较同片源缓冲次数、首帧、峰值 PSS/内存与恢复耗时，不直接统一扩大缓存。
- **字幕/音频**：PGS/VobSub/DVB 已有字节/像素边界、latest-only cue 交付与有界追赶，LPCM 已复用缓冲并批量提交。复杂字幕、双字幕和软解音频仍值得设备采样，但不重复列为尚未修复的无界队列/逐小包分配。
- **外部播放器/Web**：外部启动会扫描系统临时目录清理旧 M3U，宜改专用目录/节流；收益限于启动。Web first-frame Future 在依赖中由 canplaythrough 近似触发，也不是实际像素显示证据；不以调整 libmpv 参数优化浏览器后端。

## 原建议顺序与设备验收

1. 先修 P03 的旧/新身份隔离，以及 P01 的 iOS 延迟解析，补会话级场景测试。
2. 收口 P02 的原生存储所有权和时间戳计算，保留持久化顺序与跨端失效；用固定 20/200/1000 条记录分别测同步工作时间。
3. 实施 P04/P05，稳定 MPV 子树身份；测无字幕首播到可操作、长按 2/5/10 秒的输入次数/实际 seek 次数和稳定画面恢复。
4. 修 P06/P07，补 iOS 预热、VOD HLS、取消、暂停和回前台测试；先校正跨内核首帧统计。
5. 最后做 TV/API 23、ARM32/ARM64、iPhone 和桌面同样本测量，再决定缓冲、硬解、输出和刷新率策略。

设备矩阵至少包含本地/局域网/远程、首次/续播/切集、1080p H.264/4K HEVC、文本/位图/双字幕、稳定/限速/短时中断网络。记录实际视频掉帧与 UI/raster 分布，不能用主机 test 子进程耗时或“测试全通过”替代。

本轮专项：Flutter 123+25=148 项通过，Android 8 类 JVM 共 80 项通过，Dart 定向分析及策略生成检查通过，Swift 模型/存储 runner 通过；Swift 预热/HLS/存储探针记录在 performance.md。没有全仓回归、iOS App 链接构建、ARM 解码或设备性能验收。本轮只修改本文、README 索引和 performance.md，其他工作区变化不属于本轮。
