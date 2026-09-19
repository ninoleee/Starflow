# 字幕链路

核对日期：2026-09-20。本文负责字幕搜索、验证、渲染与生命周期；播放器总边界见 [架构说明](architecture.md)，请求与代理见 [网络说明](development-network.md)，设备显示验收见 [真机性能](performance-device.md)。

## 搜索与凭据

独立字幕页只预填当前影片，不自动搜索；播放器入口也由用户手动触发。默认结构化身份可包含 IMDb / TMDB、季集、年份、文件大小和本地文件哈希。只有可读取的本地文件才计算哈希，不为字幕搜索下载完整远程视频。修改搜索词后不继续沿用原影片身份。

TV 独立字幕页默认聚焦关键词入口，复用设置文本编辑弹窗并等待确认键释放后打开键盘；搜索按钮独立可聚焦，忙碌期间保留焦点但不接受重复确认。结果以整条为唯一遥控器焦点目标，内部同义按钮不再参与遍历；下载失败后仍保留原焦点。非 TV 继续使用内联输入框与原有触摸按钮。

| 来源 | 凭据入口 | 搜索与下载边界 |
| --- | --- | --- |
| ASSRT | 字幕设置中的 Token | 只用官方 search / detail API；无 Token 不启用 |
| OpenSubtitles | 构建参数 `STARFLOW_OPENSUBTITLES_API_KEY`，设置中的账号密码 | 搜索保留 file ID，点选才调用 download；登录态缓存 15 分钟，授权遇 401 重新登录一次，额度 / 限频错误不盲目重试 |
| SubDL | 字幕设置中的 API Key | 使用支持的标题 / ID 查询，跳过不支持的哈希查询；相对下载地址基于 `https://dl.subdl.com/` |

IO 仓库并行请求启用的来源，每来源等待上限 30 秒。搜索结果虽然使用 `ValidatedSubtitleCandidate` 模型，初始验证状态实际为 `skipped`，只代表待点选的元数据，不能当作已下载可播放。真实账号、额度和服务可用性不由单元测试保证。Web 仓库为 unsupported stub，不继承 IO 实现。

## 组件边界

- 搜索页负责输入、来源选择和回调代际检查，不自动搜索。未编辑输入时保留当前影片结构化身份；修改后只按新关键词构造请求。
- `online_subtitle_provider_protocol.dart` 负责 ASSRT、OpenSubtitles、SubDL 协议。搜索只取元数据；OpenSubtitles 下载授权延迟到点选，文件 ID 可跨 Flutter/原生路由序列化。
- `online_subtitle_repository_io.dart` 负责来源编排、按需授权、缓存根目录维护；`SubtitleValidationPipeline` 是唯一在线下载验证管线。
- `subtitle_content_decoder.dart` 负责 UTF-8/UTF-16/GBK 解码、字幕格式识别及有界 ZIP 解压；管线按季集与语言选文件，验证 CRC 后输出 UTF-8。HTML 登录页、空内容和不可识别文本不视为可播放字幕。
- `subtitle_content_processing.dart` 将下载及飞牛外挂的有界解压、文本处理放入后台 isolate；`subtitle_render_policy.dart` 区分文本叠层和原生位图渲染，页面不自行复制一套解码规则。
- `subtitle_language_preferences.dart` 与原生平台策略负责语言/Forced/Default 排序；双语只在语言已经匹配时加分。剧集手动偏好优先于全局设置，缺失轨道回退全局策略，不跨集复用外挂文件。

## 播放能力

| 路径 | 内封单字幕 | 双字幕 | 在线/本地文本外挂 | 偏移 |
| --- | --- | --- | --- | --- |
| 非 Web MPV | 文本与位图 | 两条独立内封文本轨 | 支持 | 支持 |
| Android Exo | Media3 支持的文本与位图 | 两条独立文本轨 | 支持 | 外挂文本 |
| iOS AVPlayer | 系统可用字幕轨 | 回退系统语言 | 尚未完成挂载闭环 | 不支持 |
| Web 仓库 | 取决于播放后端 | 不承诺 | 仓库未实现 | 不承诺 |

MPV 文本使用 Flutter 字幕层，ASS 样式/动画不完整保留；位图使用 MPV 原生显示，不再依赖文本事件。副字幕关闭原生显示，防止与 Flutter 双字幕重叠。

`MpvSubtitleRenderBinding` 同时响应所选轨道、完整轨道列表和原生 `sid` 变化，以最新列表补全 codec/image；`auto` 不当作文本轨。元数据尚未到达时暂保留原生显示，识别出文本后再交给 Flutter。属性写入串行合并，关闭后不提交迟到状态，失败写结构化日志并在下次变化时重试。渲染、双字幕候选、剧集偏好及飞牛外挂拒绝共用位图类型判断，兼容仅有 codec 的轨道。

Android 使用 `NativeSubtitleRenderer / NativeSubtitleOutput` 合并过时 UI 更新；PGS/VobSub/DVB 积压每轮最多追赶 32 条，只交付追赶后的当前状态，跨轮追赶期间保留最后状态但不补播旧字幕。`BitmapSubtitleSampleStream` 限制 resolver 最多持有一条未来样本，但每帧仍推进 Media3 的呈现/清屏时钟；不限制 extractor 的媒体缓冲。清屏参与同一 UI 队列，seek/换轨/释放使旧更新失效，disable 通过公开 position reset 清空 resolver。时间轴仍由 Media3 管理，不通过固定字幕偏移补偿卡顿，也不保证修复网络未到达或设备解码能力不足造成的延迟。

## Android 位图解码

- `PgsReader` 只负责 TS 段组装与 PCS PTS，`NativeSubtitleParserFactory` 在 progressive TS、MKV 及 MediaSource 字幕入口统一分派；自定义 Blu-ray `0x90` 识别仍仅限 progressive TS，不宣称 HLS 新增同等流识别。
- `BoundedPgsParser` 负责 PCS/PDS/ODS/WDS/END，按 ID 保留调色板和编码对象，检查 ODS 版本及碎片完整性，支持两对象组合、裁剪和窗口裁切。正常组合复用缓存，epoch/acquisition、seek 和异常重置状态；零对象 PCS 明确清屏。不缓存跨 cue 的 ARGB 位图，不推测丢失对象。
- 每个压缩前/解压后 sample 最多 `4 MiB`，PGS 编码对象缓存最多 `8 MiB`、64 对象、8 调色板；尺寸每边最多 4096，单对象及一次组合总像素不超过 `3840 × 2160`。这些是拒绝异常输入的上限，不是应用总内存预算，4K 全屏位图仍可能有较高瞬时内存成本。
- `BoundedVobsubParser` 基于 Media3 1.10.1 的 Apache-2.0 实现，增加尺寸/解压限制、控制序列前进检查、RLE 截断终止；不靠捕获 OOM 修复输入问题。DVB 保留 Media3 像素算法，预检显示/区域尺寸及缓存规模，修正非零输入 offset，reset 重建 parser 以释放画布。
- progressive TS/MKV 等 extractor 的 seek/release 按作用域重置字幕 parser；PGS/DVB payload 的连续性重置按轨道 ID 清理对应 parser，不清空其他字幕流。丢弃原因通过 `subtitle.decode.drop` 限频记录，PGS `subtitle.decode` 记录解码耗时/像素/编码缓存，`subtitle.catch-up` 记录追赶批次，不包含字幕正文；`lagMs` 是 cue 时间与播放位置之差，不是解码耗时。

飞牛外挂支持文本或 ZIP，经共享解码器转为 UTF-8；位图外挂明确拒绝。Emby 外挂下载接口仍未实现，不将媒体服务器统一接口等同于所有服务端都支持外挂。

## 资源与生命周期

- 在线下载验证管线响应体最多 16 MiB、等待上限 30 秒；OpenSubtitles 点选后的下载授权在此之前单独等待，不能将整个点击到挂载流程承诺为 30 秒。ZIP 最多 256 项，声明总解压量最多 64 MiB，单项实际输出最多 16 MiB，拒绝符号链接。网络共享客户端不因某次字幕操作而被关闭。
- 在线下载保存到临时目录 `starflow/online_subtitles/download-*`，每次点选重新下载。旧 `session-*`、`validated_online_subtitles`、`native_subtitles` 一并统计清理；下载时回收超过 7 天的旧缓存。
- MPV 加载文本数据而非依赖下载文件继续存在。Android 单线程 worker 解码、校验和偏移，零偏移也规范化编码；缓存原始文本避免滑杆每次重读，挂载使用 `playback_subtitles/session-*` 独立副本，正常关闭后删除。
- Android 准备完成后检查请求代际、播放器、目标和 Activity 生命周期；只在实际挂载成功后更新飞牛字幕选择记忆，失败保持当前媒体。偏移输入有 250ms 防抖，换源和关闭取消待执行回调。播放副本持有文件锁，下次创建会话时回收超过 7 天且无锁的崩溃遗留目录，不删除另一活动播放器的目录。
- 手动清理只针对下载/旧版缓存，不删除活动播放副本；操作恰逢下载完成但尚未挂载时可能需要重试，不能承诺尚未加载的缓存文件始终存在。

## 验证边界

单元/组件测试覆盖协议、编码、格式、包限制、选集、缓存与语言策略；不替代真实账号的额度验证、NAS 联调、MPV/TV 屏幕显示及 iOS 系统字幕操作。实际位图坐标、字体和双字幕布局仍需设备验证。

在仓库根目录运行主要 Flutter 回归：

```sh
flutter test --no-pub test/online_subtitle_validation_pipeline_test.dart test/subtitle_pipeline_regression_test.dart test/subtitle_search_page_test.dart
```

Android 的 `BoundedBitmapSubtitleTest`、`NativeSubtitleContentTest`、`NativeSubtitleOutputTest`、`NativeExternalSubtitleLifecycleTest`、`NativeSubtitleTrackSelectionPolicyTest` 与 `PgsReaderTest` 覆盖原生管线；`mpv_subtitle_render_binding_test.dart` 覆盖元数据迟到、auto/sid、合并、关闭和属性失败。执行方式和全量回归的已知失败见 [主机验证](performance.md)。

`test/fixtures/subtitle_language_contract.json` 由 Dart、Android JVM 与 Swift 共同读取。Swift 纯策略回归可在 macOS 执行：

```sh
xcrun swiftc ios/Runner/NativeSubtitleLanguagePolicy.swift scripts/test_subtitle_language_contract.swift -o /tmp/starflow-subtitle-contract
/tmp/starflow-subtitle-contract
```

2026-09-20 本机 Swift 契约检查 16 项通过；它只验证语言匹配策略，不编译 AVPlayer 容器，也不是 iOS 字幕显示验收。
