# Starflow 架构说明

本文件是组件边界与数据流说明，按 **2026-09-20 当前工作区**（含未提交修改）核对，不是早期规划稿。目录和逐模块入口见 [代码地图](code-map.md)，平台能力和发布约束见 [README](../README.md)，请求协议见 [开发网络](development-network.md)。

## 阅读索引

2026-09-24 作品聚合：`library/domain/media_work_aggregation.dart` 只生成列表投影，`librarySeedItemsProvider` 在分页前合并作品，首页最近新增在截取展示数量前合并；指定来源分区和 `fetchLibrary / fetchChildren / findById` 保持原始资源查询语义。类型限定为电影或整剧，优先 TMDB／IMDb，缺 ID 时仅用规范化标题和已知年份；相互矛盾的 ID 与歧义标题不传递合并。`MediaItem.workResources` 与导航的 `MediaDetailTarget.workResources` 为瞬态成员，不写回来源索引／媒体 JSON。详情恢复直接使用当前成员，沿用来源、季集和版本服务，即使关闭自动资源匹配也能切换；缓存只补展示与记忆选择，不能重新注入已消失的作品成员。作品身份不能取代来源、文件、鉴权及删除身份。验证范围见 [主机回归](performance.md)。

| 范围 | 入口 |
| --- | --- |
| 全局基础设施 | 第 2-5 节：技术基线、目录、状态、网络、日志与启动 |
| 内容读取 | 第 6-8 节：首页、媒体服务器/外部存储、详情与元数据 |
| 搜索与副作用 | 第 9、11 节：验链、转存、同步、设置与缓存失效 |
| 播放 | 第 10 节及 [字幕链路](subtitles.md)、[音频审查当前状态](reviews/audio-decoding-review-2026-09-19.md) |
| 存储与平台 | 第 12-14 节；[主机回归](performance.md) 与 [设备验收](performance-device.md) 分开记录 |

本文中的“已实现”描述代码路径，不表示真实 NAS、账号、HDMI 或全部设备已经验证。`part` 文件仍属于原 Dart library，不是独立服务边界。

普通文字由 `AppColors.foreground / foregroundBody / foregroundMuted` 提供标题、正文、辅助三档亮度；`AppTheme` 和普通 `secondary / ghost` 按钮复用该层级。强调色按钮前景仍由 `AppAccent.onPrimary` 决定，TV 焦点框统一保持纯白，不随强调色或选中状态改变；普通叠层与轻量 painter 共用规则。

`StarflowButton` 与 `StarflowIconButton` 在 TV 上通过共享调色板统一将 `primary` 映射为 `secondary`，覆盖普通页面、`Dialog`（含 `AlertDialog / SimpleDialog`）及 `BottomSheet`，低亮度背景与白色焦点描边分离；`TvAdaptiveButton` 和共享操作弹窗自动继承规则。`ghost / danger` 保持原语义，非 TV 不受影响，业务调用处无需重复判断平台。该规则不接管初始焦点、回调或 Android 原生系统弹窗；播放器设置、更多、字幕的 TV 关闭按钮也使用 `StarflowButton`。

## 1. 总体定位

### 性能实现边界（2026-09-20）

- `bounded_http_request.dart` 管理单请求总期限、正文上限与中止；`AsyncWorkPool` 管理整段异步操作名额。图片传输四路，UI 放行不等于网络完成；IO 缓存使用持有者计数取消共享请求。
- 详情缓存使用真实 16ms Timer 批量入串行写链；清理先排完已接受更新，dispose 冲刷已接受批次。评分人数 mutation 串行且只写变化 shard，全量保存也跳过字节相同的 shard/manifest。
- NAS 冷读共享 Future，128 条起在 compute 中排序、全源/分区分组与构建查找表，回填前验证来源状态/revision；尚不是增量按系列重建。搜索 128 条起后台打分/排序，列表筛选按结果引用缓存；来源完成仍增量显示。
- 首页 seed 按模块类型订阅库修订；豆瓣模块不订阅 NAS/库 revision，最近播放继续订阅历史。集合分页 provider autoDispose。构建信息不再阻塞 runApp，启动阶段移除合计 150ms 人工等待，身份协调与全部模块等待契约保留。
- 播放记忆共享冷读，大 JSON/较多 series 编码走 compute；不裁剪用户历史/偏好。iOS 仅在 UserDefaults 原文不变时复用解析对象，外部写入仍失效。
- TMDB/WMDB 已解析结果各最多 512 项 LRU；图片压缩字节仍 256 项/72 MiB，内存压力时只清该内存层。磁盘成功写后最多每小时维护一次，按修改时间淘汰超过 30 天或超过 512 MiB 的文件，最近五分钟文件受保护，故为软上限，不是访问 LRU。字幕过期扫描最多每小时一次。
- Android 普通日志为单线程后台写、256 条有界队列、配置缓存 1s；满文件保留约半容量完整尾行，崩溃同步写与会话标记保留。Dart 普通日志 16ms 批量、待写最多 256 条/约 1M 字符，超量计数在后续日志报告；关键错误、flush、清理维持串行顺序。预览每文件最多 2 MiB 尾部，在 isolate 解析；导出按块收集，但接口仍返回完整 bytes，不是恒定内存流式导出。
- 帧监测仅在记录 `info` 时按约 600 帧或有新帧时满 30 秒汇总 build/raster p50/p95 与超 16.667/33.333ms 数量；`warning` 独立控制 250ms 严重长帧检查。关闭日志时不遍历帧，关闭采样时清除旧窗口。不能把 Flutter 帧统计当视频首帧或解码掉帧。
- MPV 释放前仅在记录 `info` 时并行读取解码器、音频输出、掉帧等 11 项纯诊断属性；缓存速度和既有 5 秒带宽采样仍用于功能性调参。释放顺序、恢复预算、进度保存和缓冲 UI 不变。
- IMDb 数据集下载与后台解压/索引共享 Future，保留 TSV 字节及每行 4 字节偏移，按 ID 二分查询；下载上限 32 MiB、展开上限 128 MiB、400 万行、单行 256 字节，校验 gzip 校验和与长度。网络与解析失败不永久缓存，清空后的旧结果不回填，新查询不逐影片解压。查询及建议缓存各 512 项；NAS 配置开关默认关闭，详情设置切片不再订阅该无关字段。
- Flutter assets 显式列出主 Logo 与启动 Logo，不打包两张设计源图或性能样本视频；源文件和图标生成链保留，bootstrap 目录继续支持显式嵌入设置。

Starflow 不是单一播放器，而是一个面向个人影音库的统一入口，把这些能力放进同一个 App：

- 本地媒体源：`Emby`、`飞牛影视`、`WebDAV`、`Quark`
- 内容发现：豆瓣
- 聚合搜索：本地资源、`PanSou`、`CloudSaver`
- 播放：内置 `MPV` + App 内原生播放器容器页 + 系统播放器
- MPV / Android Exo 可靠性契约：`config/playback_policy.json` 经 `dart tool/generate_playback_policy.dart` 生成 Dart / Kotlin / Swift 常量，`--check` 校验同步；应用层共享 HTTP 分类/地址刷新范围、缓冲高水位进展和恢复预算，状态优先级为失败、结束、恢复、准备、缓冲、播放/暂停。Swift 当前接入其中的播放记忆规则，不据此宣称拥有 MPV / Exo 的全部恢复能力。内核错误提取、FFmpeg/Media3 加载退避、解码/渲染及各端 UI 适配仍留在原边界。自动重建预算由页面/原生恢复控制器持有，不随播放器实例释放清空；切集和手动重试重置。
- 入库联动：夸克 / 115 保存、`SmartStrm` Webhook、自动增量刷新索引
- 本地持久化：设置、详情缓存、图片缓存、`WebDAV` 元数据索引
- 诊断与运维：结构化本地日志、Android 原生退出信息、日志预览与导出

## 2. 技术基线

### 共享规则边界

- `details/domain/cached_artwork.dart` 把每类图片 URL 与 headers 作为同一个来源选择；多背景图列表不跨鉴权来源拼接。`cached_metadata.dart` 统一标题、评分、简介、演职员及外部 ID 装饰；播放身份和季集结构由各入口保留，首页 / 媒体库继续在内容不变时返回原对象。
- `library/data/nfo_metadata.dart` 是 WebDAV / Quark 共用的纯解析模型、解析器和主次合并策略。WebDAV 通过回调解析相对图片地址；夸克不把相对地址当远程下载链接。列目录、读取文件、鉴权和本地 sidecar 优先级仍由各客户端负责。
- `search/application/cloud_save_postprocessing.dart` 统一延迟下限、SmartStrm 部分失败与后台刷新失败边界；夸克仅重复项转存仍刷新原生夸克源，115 零新增保留原来的提前返回行为。
- `PlaybackMemoryRepository` 串行执行完整读改写与清空，持久化成功后才更新内存快照；失效代次阻止迟到读取重新装入旧快照。2026-09-20 起移动端通过 `NativePlaybackMemoryPreferences` 的 read / compare-and-set 桥接，与原生播放器共用原生串行写队列；冲突时重新读取并重做 mutation，不以旧全量快照覆盖新数据。Android 队列和 iOS 队列均跨 store 实例共享。原生播放返回仍须失效并重读缓存；此协议只保证本应用内参与该队列的写入顺序，不保证强杀瞬间磁盘持久化或第三方进程直接改偏好的一致性。
- `config/playback_policy.json` 生成 Dart / Kotlin / Swift 常量；播放记忆共享 5 秒起点、12 秒续播剩余下限、8 秒完成剩余阈值、98.5% 完成比例和 20 条最近项目上限。原生时间戳统一比较实际时间、毫秒单调递增，同时间按 key 倒序；三端用 `test/fixtures/playback_memory_contract.json` 验证阈值，内核操作仍由平台实现。
- `library_resource_deletion.dart` 只收敛确认弹窗、mounted 检查、反馈与日志；远端删除和索引清理由仓库承担。设置加载、导入、来源编辑 / 删除对两个网盘的 WebDAV 目录引用采用同一协调规则。

- 框架：`Flutter`
- 状态管理：`flutter_riverpod`
- 路由：`go_router`
- 播放：`media_kit`
- 设置、详情缓存与 Emby 分片缓存：`SharedPreferences`
- `WebDAV` 索引库：`Sembast`
- Android：Media3 `1.10.1`，`minSdk 23 / compileSdk 36 / targetSdk 35`，JVM 17；release 仅 ARM32/ARM64
- iOS / macOS 工程最低系统版本分别为 `13.0 / 10.15`
- `pubspec.yaml` 声明依赖范围，本机解析版本看 `pubspec.lock`；Android / iOS full MPV 使用本地依赖覆盖，Web 使用浏览器后端而非 libmpv

应用入口在 `lib/main.dart`，启动时完成：

- Flutter 绑定初始化
- 读取本地设置，配置运行期代理与结构化日志
- 安装全局异常捕获、帧监控并记录构建信息
- 写入启动标记；上次启动未完成时只启用本次临时恢复，不覆盖用户设置
- `media_kit` 初始化
- `ProviderScope` 注入与关闭 Riverpod 默认自动重试，随后进入 `BootstrapController`

`BootstrapController` 的 10 秒总上限不包含上述 `main()` 的前置读取、日志初始化或原生初始化，不能描述为从进程启动到首页的绝对上限。

## 3. 代码组织

### 组件所有权整理（2026-09-20）

本轮按详情、搜索与转存、缓存、播放器与 iOS 四组推进，验证记录独立见 [重构记录](reviews/review-closure-2026-09-20.md#组件边界重构)。拆分以任务和资源所有权为边界，不以新增 `part` 文件或主文件行数下降证明解耦与性能收益。

- `DetailLibraryMatchCoordinator` 拥有多来源匹配执行流程，复用 `DetailLibraryMatchService` 的候选模型、评分及合并规则。优先来源阶段结束后才进入后备来源；并发、结果上限和取消检查保持原契约。详情页保留缓存恢复、交互和结果提交。
- `SearchRequest` 捕获来源选择与查询，`SearchSession` 拥有请求代次、搜索/验链排队、去重及批量发布的不可变视图状态；`SearchShareValidator` 适配两种分享协议。输入、TV 焦点、收藏入口和提示仍在 presentation 层。
- `CloudSaveDispatcher` 统一搜索、收藏与详情的保存分发、分享凭据准备及错误结果映射；原有 Quark / 115 工作流保留协议差异、零新增行为和 STRM 后处理，页面复用反馈 session。未知 115 失败显示保存未确认，客户端已有的批次未确认提示原样保留，不自动重试。
- 公共存储仓库保留调用入口；`DetailCacheStore` 持有详情数据、串行写链和 revision 通知，`MediaServerCacheStore` 持有媒体服务器分片、manifest、读复用与写队列。详情缓存使用当前 v2 key，旧 key 不读取或迁移，也不因组件边界触发远端刷新。
- 2026-09-20 缓存失败恢复补强：`MediaServerCacheStore` 在写分片前记录独立分片索引，清理时同时枚举严格分片 key 前缀，manifest 提交失败或损坏不会使分片失去清理入口；只清理媒体库缓存，不扫描或删除其他偏好。设置加载将 JSON 解析与凭据 IO 分离；读取或协调保存失败不再用默认配置覆盖有效设置，格式损坏的原文和独立凭据也保留供恢复。
- `MpvPlaybackLifecycle` 持有实例订阅并组合 `MpvSubtitleSession`，detach 同步隔离旧所有者，清理 Future 随旧播放器传递；字幕 sid 注册迟到时仍由旧所有者移除。`PlaybackPlatformSessionOwner` 持有系统会话绑定、代次和发布快照。页面级自动恢复预算不移入单个实例，也不合并 Dart、Media3 与 AVPlayer 能力；现有 `part` 仍属于页面 library，不能称为全部运行逻辑已独立。
- iOS `AppDelegate` 保留通道与宿主装配；`NativePlaybackModels / NativePlaybackMemoryStore / NativePlaybackViewController / SettingsDocumentExporter` 分别负责模型、存储、容器和文档导出。Swift 纯模型/存储测试不替代 AVPlayer 真机操作。

### 2026-09 代码整理

- `media_repository.dart`、`discovery_repository.dart`、`search_repository.dart` 是真实仓库入口，不再使用 `mock_` 文件名。媒体查询由 `AppMediaQueryService` 负责，夸克扫描与 sidecar 读取由 `QuarkExternalStorageClient` 及索引链负责；仓库中迁移后未调用的查询、夸克扫描和 NFO 解析实现已删除，刷新与同步删除仍保留在原职责边界。
- `detail_metadata_service.dart` 统一 WMDB/TMDB 请求、单集图片解析、豆瓣评分补全及元数据结果状态。详情刷新和后台解析复用同一服务，后台按需补缺、强制刷新允许替换，NAS 后台元数据仍优先由索引负责。字段合并复用 `DetailLibraryMatchService`，不以系列简介覆盖单集简介或覆盖已有单集类型。
- 执行结果区分 `skipped / noMatch / succeeded / partialFailure / failed`。现有持久化格式不变：未执行时保留原刷新状态，部分失败、全部失败写入 `failed`，正常完成但无匹配仍为已完成尝试；首页和详情不再用“是否改了字段”推断请求成功。部分成功的数据仍保存，页面离开后的会话校验不变。
- 评分合并统一到 `media_rating_labels.dart`，按来源去重并以有效值替换零分；已有有效评分保持优先，豆瓣实时评分刷新仍可更新对应值。展示顺序固定为 `豆瓣 -> IMDb -> TMDB`，与数据写入先后和缓存命中路径无关。
- `core/storage/resource_path_identity.dart` 为详情缓存和播放历史提供来源内路径相等、目录范围比较。URL 按段解码一次，普通路径按字面处理，保留大小写、百分号和编码分隔符的身份，来源隔离仍由仓库校验。
- 首页两种 Ref 入口共用刷新调度，返回表示已调度；启动等待仍由 `waitForHomeModules` 承担，移除无条件 `140ms` 延迟。来源列表直接读取配置，移除原 `120ms` 人工等待。废弃 body inset 接口、无效底栏参数和未调用的 trace 去重集合已移除；结构化本地日志与原生退出捕获保持启用能力。
- 公共逻辑继续收口：`details/domain/cached_artwork.dart` 保持图片 URL 与 headers 同源合并；`library/data/nfo_metadata.dart` 共享 WebDAV / 夸克的 XML 解析及字段合并；`library/presentation/library_resource_deletion.dart` 复用媒体库删除确认；`search/application/cloud_save_postprocessing.dart` 共享 STRM 触发及刷新失败反馈；`core/widgets/tv_text_input_launcher.dart` 统一遥控器按键释放后才打开输入。
- 整理期间新增文件按源码核对职责，测试结果仅对应各自执行时快照；公共组件、发布版本工具和位图字幕解析器的后续改动尚未在本次重新全量验证。

```text
lib/
  main.dart
  app/
    app.dart
    lifecycle/
    router/
    theme/
  core/
    logging/
    navigation/
    network/
    platform/
    scheduling/
    state/
    storage/
    utils/
    widgets/
  features/
    bootstrap/
    details/
    discovery/
    home/
    library/
    live_tv/
    metadata/
    playback/
    search/
    settings/
    storage/
```

分层上仍然遵循 `presentation / application / domain / data` 的思路，但以 feature 为第一组织单位。

### `app`

负责应用壳、主题和主路由：

- `app.dart`：`MaterialApp.router`
- `router/app_router.dart`：主导航和独立页面路由
- `theme/app_theme.dart`：当前全局主题

`AppRoutes.shellBranches` 保留六个一级路由，直播追加为索引 5，原有索引不变：

- 首页
- 搜索
- 收藏（复用 `SearchPage(favoritesOnly: true)`）
- 媒体库
- 设置
- 直播

可见菜单由 `navigationDestinationIds` 决定；默认依次为首页、直播、搜索、媒体库、设置，不含收藏。设置项始终保留。路由分支索引与可见菜单索引不可混用。

2026-09-20 默认直播第二项调整：主机配置与导航回归 47 项通过，相关静态检查通过；包含 TV 从首页下移一次进入直播的焦点与自动隐藏检查，不代表真机验证。

### `core`

放业务无关或弱相关的公共基础能力：

- 平台识别
- HTTP 客户端包装
- 统一网络失败分类、策略化超时、幂等重试约束与按主机熔断
- 结构化日志 API、敏感字段脱敏、文件轮转与帧性能监控
- 本地图片缓存抽象
- 持久化图片缓存的 `URL + headers` identity、磁盘 metadata、过期与 stale fallback 策略
- 通用组件
- 网络图片请求头和调试工具
- `TV` 焦点组件、菜单键动作和页面边界处理
- 详情季标签不设置固定或最小宽度，由文字和对称内边距决定宽度，选中时不添加对号或改变宽度，季选择区域维持 `52dp` 高度。共享 `StarflowChipButton` 默认关闭 `showSelectedCheckmark`，各页面 Tab / 标签按钮保留原有功能图标和文字、底色、边框高亮；复选框与菜单勾选标记不变。`_DetailSeasonTabs` 用稳定 key 保留标签，只在实例首次布局后调用一次横向 `ScrollPosition.ensureVisible(alignment: 0.5)`，按打开详情时的当前季实际布局定位，并夹紧首尾滚动边界；不再使用 `index * 120` 估算，也不监听选中季或可用宽度触发重新定位。季标签使用完整 Row 以便定位远处选中项，剧集卡片仍保持懒构建；切换季、手动滚动、尺寸变化和播放器返回不重置横向位置，不滚动外层页面，不请求焦点。
- 详情页的延迟内容一旦显示，不再使用 `TickerMode` 控制其挂载寿命；播放器覆盖期间保留剧集组件和滚动状态，剧集 provider 的监听仍由页面可见性与 `TickerMode` 共同限制。
- `DetailHeroSection` 监听 `playbackMemorySnapshotProvider`，使用仓库同步快照计算续播入口。“从头播放”只依赖 `MediaDetailTarget.hasMatchedResource`（已有直接播放目标，或来源 ID 与资源 ID 均非空）；不依赖历史、剧集加载或地址解析。历史 readiness 仅控制自动首焦点，避免记录晚到前先抢焦点。操作行由稳定 key 的 `KeyedSubtree` 包装，补充续播位置文字时不重建按钮子树。剧集区域将 `DetailBlock` 放在异步分支外，保留加载到完成期间标题的 Element 和布局位置。Hero 背景图使用 gapless playback；元数据替换图片源时保留上一张已解码帧到新图就绪，候选列表只新增或重排且当前源仍在时直接沿用当前候选。
- 详情启动将 `_seriesSourceReady` 与 `_detailEnrichmentReady` 分开：本地缓存和版本恢复后允许剧集读取，在线元数据刷新结束后再订阅 enrichment，保留解析防重约束。剧集 provider 在区域内的 `Consumer` 监听，卡片角标通过 `select` 订阅最终显示文字；无关快照更新不会重建图片。季列表和可选历史查询使用 record `.wait` 并行，历史失败回退默认季。单季列表高度按 `16:9` 卡片、三行简介、内边距和文字缩放动态计算，多季另加 `68dp` 季选择条空间；错误态按内容高度显示，无可用分组仍隐藏。
- `TV` 主要页面和弹窗的普通方向键使用 Flutter 默认寻焦，不再声明 `OrderedTraversalPolicy / NumericFocusOrder`；文本编辑弹窗仅在输入框局部把上下键映射为前后焦点，选择弹窗只在首帧请求一次初始焦点，不安排延迟补焦点
- `TvFocusableAction` 与描边按钮通过自身 State 更新焦点视觉，海报使用 `ValueNotifier + ValueListenableBuilder` 局部更新；`TvFocusVisualStyle.none` 供自绘焦点外观使用
- `TV` 页面级焦点边界、页头回顶锚点和统一的上下方向焦点兜底
- `TV` 页面级焦点壳与方向动作面板，便于首页、搜索、媒体库、详情、设置等页共用同一套焦点边界
- `TvPageFocusScope` 安装 `TvSafeDirectionalFocusTraversalPolicy`：方向寻焦读取候选节点坐标时若遇到动态刷新产生的暂时未布局 `RenderBox`，忽略当前按键并保持原焦点；其他异常仍继续抛出
- `core/widgets/tv_remote_input.dart` 统一命令键周期，替代旧 `tvPressOnlyShortcuts`：`TvRemoteKeyHandler` 记录物理键和原焦点，消费按下、重复与松开，只有配对松开才执行一次；失焦、应用失活、合成松开或销毁取消待执行动作。`TvRemoteShortcuts` 在 rebuild 中保留处理器，执行前重新检查当前 Action 和路由。共享按钮确认／菜单、海报、弹窗返回、MPV 页面命令、元数据编辑返回、剧照预览和直播覆盖层使用同一规则，应用入口提供 TV 返回／确认快捷键兜底。普通页面返回、弹窗焦点分层与系统返回语义不变；方向遍历、seek 与数值连调不使用该规则。`TvFocusableAction` 用 `ExcludeFocus` 明确排除普通禁用目标，保焦仅由 `focusableWhenDisabled` 显式开启。
- Android `NativePlaybackRemoteController` 对返回／菜单／选集等界面切换命令按 deviceId、keyCode、downTime 配对，在松开且窗口仍有焦点时执行；取消、失活和播放会话 reset 清空等待。原生播放／暂停保留即时响应并持有按键直至松开，方向长按 seek、Android 标准按钮与系统输入法保留原生处理，不强行接管所有硬件键。
- `scheduleTvFocusRecovery` 是一次帧末缺焦检查，并主动安排帧；执行时检查页面仍挂载、路由当前、TickerMode 可见、应用前台、目标可用且全局不存在可操作焦点。WebDAV／夸克目录及首页模块合集、媒体库合集、演职员作品页复用，不增加全局监听、循环补焦或焦点历史存储。合集和作品页以常驻页头作为首焦点，媒体库多页边界按钮显式保焦但仍禁用确认。完整清单见 [TV 焦点](tv-focus.md)。
- `TvTextInputLauncher` 从设置输入组件提取到 core，设置与搜索编辑入口共用。等待打开按键释放时拒绝重复启动，焦点已移走则取消；路由不再当前或组件销毁也不打开，并移除键盘监听。独立字幕页复用设置文本编辑入口，TV 搜索按钮忙碌时保焦；每条字幕结果只有外层焦点，内部同义按钮排除寻焦，下载期间外层保焦且禁用确认。媒体库删除确认以“取消”为首焦点。
- 安全寻焦策略、页面边界和侧栏横向移动复用 `TvSafeDirectionalFocusAction` 的异常处理；未布局中断返回已处理，阻止页面边界将它当成正常寻焦到头。`wrapTelevisionDialogBackHandling` 在退出输入状态时优先聚焦已挂载且可请求的操作节点，避免只留下焦点域；未挂载按钮不会被选作返回目标
- `TvDialogOption` 在 TV 复用轻量高亮与确认键映射，普通端仍为 `SimpleDialogOption`；播放器字幕/音轨/倍速/循环与配置路径选项由首项申请焦点。来源多选优先“全部”或首项，无选项时聚焦取消；字幕偏移、片头片尾和删除/覆盖确认框也有明确首焦点。夸克目录页由常驻“选择”按钮持有首焦点，不依赖异步子目录存在
- `StarflowApp` 仅覆盖默认 `DirectionalFocusIntent` Action，补齐页面级策略覆盖不到的路由/Overlay 焦点：只捕获 `RenderBox was not laid out` 并忽略当次按键，不做下一帧重试、候选过滤或顺序改写；警告按 Action 实例做 `5s` 限频
- App 外观由 `app/theme/app_colors.dart` 的固定近中性色阶与 `AppRadii`（12/18/28/999）控制；共享控件、首页和详情组件复用这些 token。`AppAccent` 是无 Flutter 依赖的设置枚举，`appAccent` 持久化为 bone/teal/indigo/coral/amber/rose/lime/violet，当前设置只接受这些值。`StarflowApp` 只监听该字段重建主题；`ColorScheme` 保持中性，`AppActionColors` ThemeExtension 显式提供交互强调色：主行动、导航选中态、开关开启态、勾选/单选、筛选与排序选中项、线路选中标记、已收藏图标、进度/滑块和输入框聚焦描边。共享 `StarflowChipButton` 在聚焦时保留选中颜色，TV 外侧焦点框统一保持纯白；错误语义色、禁用弱化与中性背景不变。`surfaceTint` 固定透明，页面背景不绘制彩色光晕
- `app/theme/app_typography.dart` 维护内容行高、六档字号与公共内容间距：字号为 36（Hero）、24（页面／大标题）、18（区域标题）、16（列表标题）、14（正文）、12（辅助说明）；行高为 Hero 1.15、普通标题 1.3、辅助说明 1.4、正文 1.45／大正文 1.5，详情长简介普通端 1.6、TV 1.7。`AppTheme` 为 TextTheme 提供默认字号，首页／详情 Hero、剧集卡片和播放器选集显式复用相同档位，字号不按 TV／普通端分支；Android `NativePlaybackEpisodePicker` 和手机／TV 原生控制布局同步使用 24/18/16/14/12 档位，不再按端切换语义字号。`AppSettings.uiTextScale` 持久化全局倍率（85%–130%，5% 步进，默认 100%），`StarflowApp` 将其乘到系统 TextScaler，Android 原生播放器通过 `uiTextScale` Intent extra 调整 Activity `fontScale`。品牌字标宽度、用户字幕倍率和头像首字母等动态尺寸保持独立。内容关联间距 6dp、Hero 后直接内容 8dp、区域标题到正文 10dp、上一内容到下一设置标题 12dp、正文模块和设置分组默认项间距 8dp；电影和单集直接接 `DetailOverviewSection` 时使用 Hero 后间距，剧集先渲染卡片区块，不叠加。设置显式 spacing 覆盖仍有效，不缩小按钮 padding 或 TV 焦点区域。搜索结果标签为空时连同前置 8dp 间距一起隐藏。字体放大通过现有 TextScaler 和布局约束处理，不固定裁切正文。
- 详情 Hero 的“继续播放 / 从头播放”继续使用与普通操作按钮相同的 `secondary` 中性样式，不读取 `AppActionColors`；详情线路选择使用淡强调色底、边框与选中图标；当前播放剧集使用中性白色选中样式。详情上次播放剧集由 `findLastPlayedEpisodeIndex` 匹配，在卡片上半部图片区的 Stack 内居中显示中性历史图标和“Last Played”文字，配半透明黑底，下方简介统一最多三行；无匹配时不显示，不增加强调色边框，不改变卡片尺寸、滚动恢复或焦点行为。播放器显式绘制的已播放进度段同样读取 `AppActionColors`，缓冲段与未播放轨道保持中性
- 首页在重新变为活动页以及 `hasPendingSections` 从 `true` 变为 `false` 时各安排一次下一帧检查；仅在主焦点为空、落在 `FocusScopeNode`、已卸载或不可请求时调用现有侧栏恢复入口，已有可操作焦点时不做任何处理
- TV 菜单上下键按显示顺序在可见菜单项之间移动，首尾保持原位。搜索页异步结果只在主焦点为空、落在 `FocusScopeNode`、已卸载或不可请求时恢复到搜索输入框；收藏页优先恢复 `favorites:sync`，设置首页优先补到 `settings:header`。菜单或其他已挂载的可操作焦点不会被页面恢复逻辑抢占
- 菜单显示顺序由 `AppSettings.navigationDestinationIds` 同时承载可见性与顺序；规范化保留首次出现顺序、过滤未知 ID，并在缺少设置入口时追加，不改变路由分支编号。`NavigationDestinationDialog` 维护本地排序/勾选草稿，保存时统一提交既有 SettingsController；普通端提供拖拽和移动按钮，TV 移动到边界后按钮保焦但禁止继续移动。`AppNavigationShell` 按已保存 ID 顺序映射固定分支，底栏和侧栏共用；不增加网络请求。
- 菜单排序验证（2026-09-20）：主机菜单/配置/路由/设置导航联合回归 82 项通过，其中弹窗专项 5 项覆盖普通端/TV 保存、取消、设置入口不可隐藏、TV 边界保焦与 320px 窄屏实际拖拽；相关源文件与测试静态检查通过。此记录不是 Android TV 真机测量，遥控器实机体验仍待验证。
- TV 主壳处理返回键时先以 `UnfocusDisposition.scope` 清理当前焦点及作用域历史，再聚焦当前页面对应的侧栏入口；仅当该入口已经持有主焦点时，再次返回才进入退出确认
- `AppNavigationShell._focusCurrentDestination` 显示菜单后在帧末聚焦当前分支对应的入口，并通过 `ensureVisualUpdate` 主动安排更新帧。常驻菜单显隐状态不变时也不会让聚焦回调滞留到下一次按键；自动隐藏模式仍先解除 `ExcludeFocus` 再请求焦点。回归测试在按左后、主动补帧前检查帧已调度，覆盖五个一级分支及两种菜单模式。
- `PageActivityMixin` 在应用非 resumed 时同步分发失活，避免后台停帧或快速失活再恢复漏掉取消处理；前台激活与路由可见性变化仍在帧末分发，并主动调度帧。重复状态不重复通知，隐藏页恢复前台不激活，已销毁页面不执行待处理回调。首页和设置页的缺焦恢复及首页 `_waitForNextFrame` 使用 `ensureVisualUpdate`，帧末嵌套回调与滚动边界无位移时也能继续；保留现有焦点保护、重试上限及取消版本检查。
- 设置页监听 `isTelevisionProvider` 从未识别为 TV 到 true 的变化，复用首焦点恢复入口，并在调度与执行时检查 `isPageActive / isPageVisible`，不抢已有可操作焦点。`StarflowButton` 与 `TvAdaptiveButton` 透传默认 false 的 `focusableWhenDisabled` 到既有焦点包装层；信息管理页自动更新按钮显式启用，忙碌时 `onPressed` 仍为 null，保留焦点和方向移动但不重复触发更新，完成不主动 requestFocus。
- TV 主壳根据自动隐藏设置切换布局：关闭自动隐藏时使用 `Row`，菜单常驻并让内容区从左侧 `48dp` 后开始，面板颜色跟随主题 `surface`；开启自动隐藏时使用 `Stack`，内容区通过 `Positioned.fill` 保持全宽，侧栏作为 `Positioned` 浮层只做 `AnimatedSlide + AnimatedOpacity`，显隐不改变内容区布局，避免首页与媒体库网格重排。自动隐藏面板在启用透明磨砂时使用 `BackdropFilter`，关闭特效时使用半透明纯色。菜单栏仍为垂直居中的图标窄栏：栏宽 `48dp`、按钮 `44×44dp`、四周外边距为 `0`，图标保持 `24dp`。按钮统一 `18dp` 圆角；常驻 `Row` 面板保持直角，自动隐藏 `Stack` 面板使用 `28dp` 圆角。未选中项和聚焦描边均做了弱化，降低内容浏览时的视觉存在感
- TV 菜单聚焦标签通过 `OverlayPortal` 和 `CompositedTransformFollower` 跟随按钮；浮层根部用仅指定 `left/top` 的 `Positioned` 解除 Overlay 全屏紧约束，标签以自身尺寸和按钮垂直居中、文字水平间隔 `12dp`，不参与页面布局。标签使用半透明强调色胶囊背景、文字使用对应强调色的对比色，无描边，不接收指针事件，失焦或目标卸载后不显示；两种 TV 菜单布局均有标签尺寸、锚点和卸载回归测试
- 焦点诊断统一写入 `tv.focus-recovery`：首页实际缺焦恢复为 `info`，返回清理为 `trace`，未布局候选为限频 `warning`；正常寻焦与普通方向键不写日志
- WebDAV STRM 文本解析在返回播放 URL 前把裸 `#` 替换为 `%23`；已编码地址保持不变，避免文件名中的集号被 URI fragment 规则截断
- `TV` 普通方向遍历使用 Flutter 默认可见性滚动；首页恢复与选集等特定路径另行显式定位，不由共享按钮强制居中
- 页面级保留态异步结果封装：`core/navigation/retained_async_value.dart` 与 `core/navigation/retained_async_controller.dart`
- 桌面端横向列表的统一左右翻页按钮容器，供首页海报流、剧集横排、剧照横排复用，保持原有固定步长。首页普通海报流把 `12dp` 左右留白移到横向滚动视口外层，使滚动内容本身从 `0` 开始；TV 方向键回到首张海报时不再把首部留白滚掉，与详情页横排结构一致。2026-09-22 的主机 widget 回归覆盖竖版/横版卡片连续两轮方向键往返，未替代 TV 真机验证。
- `MediaPosterTile` 是首页、媒体库网格、豆瓣模块列表、演员/导演作品网格共用的海报组件。其 TV 焦点样式由默认参数统一提供：`1.6dp` 白色描边、`1.06` 缩放，调用方不再复制这些配置；未聚焦时边框透明，避免焦点进入/离开时挂载或卸载描边层产生闪烁，也不增加淡入淡出动画。描边只包裹海报图片帧，不包裹图片下方的标题、年份或评分角标之外的文字区。
- 设置区共用页面骨架和交互组件
  - 统一的设置页容器、顶部工具栏按钮、操作按钮
  - 统一的选择条目、开关条目、可展开区块
  - 统一的选项弹窗与 `TV` 文本编辑弹窗入口

### `features`

直播新增 `features/live_tv/`，采用独立 `LiveSource / LiveChannel / LiveLine / LivePreference / LiveProgramme`，不扩展影视媒体源枚举，也不借用 `PlaybackTarget` 的电影语义。`LiveRepository` 持有 Sembast 数据库、串行 mutation、来源代次和合并刷新请求；下载/解析在成功后事务提交，旧响应不能恢复已删除来源。频道与 EPG 分别提交，频道成功而 EPG 失败是部分更新，不称为全部成功。

`LivePlaybackController` 持有单个 `LiveEngine`、换台代次、180ms 连续换台合并、5s 开流等待、5s 无进展监测和最多三次自动恢复。恢复预算不因短暂就绪重置；手动换台/重试才重置。MPV 与 Android `LiveTvView` Exo 通过同一接口报告状态，Exo 原生视图只持有 Media3、TextureView 和音轨操作，不读取点播历史。播放器注册全局清理所有权并参与播放优先调度，后台停止，退出串行释放。2026-09-21 起直播标准 Media3 renderers 注册随包 FFmpeg 音频扩展并启用 decoder fallback，仍不继承点播 TS、双字幕及自定义输出策略；`LiveTvDiagnostics` 只持有单实例音轨、缓冲、音频输出及掉帧摘要，经原生结构化日志记录，不拥有恢复决策。完整边界见 [直播电视](live-tv.md)。

直播页面和持久化的具体所有权：

- `live_player_page.dart` 不提供底栏，顶部固定 112dp，独立全屏设置视图拥有频道、节目单、线路、音轨和 Android 内核入口，不提供上下频道按钮。频道／节目单／设置共用一个 `LocalHistoryEntry`，返回先移除局部界面并恢复画布焦点；弹窗／下拉由自己的路由优先返回，退出播放器后才释放会话。设置期间禁止自动收栏，不新增播放控制器。
- 播放器顶部背景 alpha 0.2（20% 不透明），设置／频道／节目单背景 alpha 0.7（70% 不透明），仅背景混合，设置内部 Material 不重复叠加底色。`live_logo.dart` 独立承载频道首页的 `LiveLogo`，使用 64×40 占位、192×120 上限等比解码及失败占位；展示 URL 由首页按 `LiveSnapshot.logo` 解析，下载与取消仍归 `live_logo_provider.dart`。播放器选台菜单只用本地图标，不依赖台标组件／provider，也不发起台标下载或解码；节目查询与播放所有权不变。

- `live_widgets.dart` 的 `LiveIconButton.selected` 与 `LiveSelectionLabel` 统一消费 `AppActionColors`，分别承载收藏状态及线路、分组、内核、更新间隔、恢复方式的选中勾。下拉标记固定 24dp，长标签单行省略；禁用优先弱化。播放器当前频道／节目 `ListTile` 显式配置强调色与 9% 淡底，不依赖保持中性的 `ColorScheme.primary`。`live_channel_picker.dart` 拥有左分组／右频道叠层的筛选、固定行高惰性滚动和 TV 焦点，每次挂载定位当前播放频道；选台通过回调交回 `LivePlayerPage`，不修改播放控制器或全局换台范围。原有白色焦点框、黑色视频底色、音轨查询和播放控制器接口不变，MPV／Exo 共用这些 Flutter 样式。
- `liveSnapshotProvider` 订阅仓库变更，`liveGuideProvider / liveNowNextProvider` 读取本地节目单；频道页激活及活动时每分钟刷新 now/next，播放页仅在选台列表打开时订阅批量 now/next，打开、列表回前台及前台列表每分钟重读。`LiveChannelPicker` 只接收结果快照，不逐频道读库；频道页和选择器按来源 + 手动覆盖后的 EPG ID 匹配，`LiveCurrentProgramme` 共享标题／空态／完整语义标签，节目刷新不改变列表身份或播放会话。播放页当前频道完整节目查询保持独立，前台每分钟更新显示时间，不发起分钟级网络轮询。`refreshDue` 只在页面激活时检查来源期限，离开/后台阻止开始下一来源，已开始的有界请求允许收尾。
- `LiveTvPage` 拥有搜索、分组、收藏筛选和整理 UI；现有“整理频道”状态同时管理频道与分组的隐藏、上下移动，分组偏好按生效分组名持久化。`LiveSourcesPage` 拥有来源编辑、文件选择、首次/手动刷新和删除确认。只有 `/live-tv` 是具名壳路由；订阅页用 `MaterialPageRoute`，播放页经 root navigator 打开 `LivePlayerPage(initialChannel, snapshot)`，没有契约草稿中的 `/live-tv/sources` 或 `/live-tv/player?channel=...` 路由。
- 首页独立持有 `LiveChannelProbeController`，每次可见且 `refreshDue` 结束、列表就绪后自动补测未测／过期频道，不依赖首次标记。`LiveProbeViewport` 检查行与视口相交、排除离屏缓存；controller 连续可见 200ms 准入、TV 焦点优先、两路并发，离屏取消并等待清理后复用名额。一个定时器合并准入和可见项最近到期，成功 TTL 5 分钟，连续失败 45／90／180／300 秒退避，成功／线路／网络变化重置；停止保留有效缓存但清除定时器和视口。刷新保留旧结果并显示图标。快照按 ID 与 URL／headers／首选线路协调，元数据保留匹配工作，隐藏／删除／停用移除对应任务。`live_probe_network.dart` 提供系统连接事件流，页面存活期间被动订阅；网络和代理变化使缓存失效但不重启已停止任务，正常路由返回复用缓存，后台或监听异常后返回保守失效。监听随销毁解除。分组菜单临时覆盖暂停；真正失活／后台停止任务，返回自动恢复；手动暂停本次停留不被筛选／网络解除，下次真正返回重置。标签／进度局部刷新。`LiveChannelProbe` 独占 HTTP 客户端和响应流，慢清理只报警、不伪造释放，开播等待清理；无数据库、后台检测、解码或 HLS 子请求，Web 隐藏入口。
- TV 文件入口由 `LivePlaylistTransferDialog` 持有临时 `LivePlaylistTransferSession`，复用 `LanTransferQrAddressCard` 和 TV 对话框返回处理；返回/后台/销毁都会关闭会话，启动后迟到的 session 也会立即关闭。接收服务只校验并返回文件名与原始字节，不接触数据库或应用配置；`LiveSourcesPage` 收到后保留草稿，仍由保存动作交给 `LiveRepository`。非 TV 保留本地文件选择，Web 使用不启动 HTTP 服务的 stub。
- `LivePlayerPage` 拥有画布/工具栏/频道/节目单的 Flutter 焦点、当前频道与内核切换、生命周期和播放优先状态。`LiveTvView` 的根视图与 TextureView 不接受焦点，Flutter 的 `AndroidView` 也被 `ExcludeFocus` 包装；原生不接管遥控器、EPG 或影视历史。音轨弹窗只向当前 engine 回写，频道及线路记忆在当前代次首次 progress/frame 时提交，而非 ready 时提交。
- IO 库为应用支持目录 `starflow-db/live_tv.v2.db`，Web 库为 `starflow-live-tv-v2`。`sources / channels / preferences / channelOwners / epg / epgLogos / meta` 分离直播数据；直播内核、收藏、线路偏好和 JSON 编码的分组隐藏/顺序偏好不写入 `AppSettings`。只有菜单可见项属于应用配置。`LiveBackup` 负责独立版本化备份校验，仓库以单事务合并/替换七个 store，并使旧刷新 epoch 失效；替换恢复分组偏好，合并只补充新来源涉及且本机不存在的分组偏好，不覆盖已有整理。`LiveBackupDialog` 负责非 TV 文件选择/路径、TV 手机扫码、凭据提示和恢复确认。没有缓存容量管理或自动过期清扫入口。
- `live_logo_provider.dart` 拥有独立四路传输池、15s/2 MiB 单图边界和 provider 释放时取消；不接入影视海报磁盘缓存。订阅、EPG 和台标不携带媒体 headers，`LiveSource` 无自定义请求头字段；`LiveLine.headers` 仅来自播放列表的媒体选项。代理与正文边界以 [开发网络](development-network.md#直播订阅与媒体流2026-09-20) 为准。
- `LivePlaylistTransferService` 以 `file / backupImport / backupExport` 模式启动单次 LAN 会话，返回 `LivePlaylistUpload / LiveBackupDownloaded` 类型结果，不访问仓库。导出模式只持有已校验的备份快照，导入模式只返回校验后的字节；`LiveBackupDialog` 确认后才调用仓库恢复。`LivePlaylistTransferDialog` 复用二维码、遥控器焦点和前后台清理，不扩展普通应用配置接口。
- TV 文本扫码统一属于设置输入层：`SettingsTextInputField` 在输入弹窗右侧提供扫码按钮，`TextInputTransferDialog` 拥有二维码会话生命周期，`TextInputTransferService` 仅接收单次 UTF-8 文本，不依赖直播、配置仓库或业务 URL 校验。回填时执行单行及 `inputFormatters` 规则，弹窗保存才更新外层 controller 并触发 `onChanged`，取消不修改原值。直播订阅 URL 确认后可清除文件草稿，来源页保存后才刷新；名称/EPG 同样使用共用入口。独立搜索/播放器输入框不隐式迁移。
- 5s 开流计时触发失败；生产适配器实现 `CancellableLiveEngine.cancelOpen`，取消请求绕过开流队列，但串行 stop/dispose/新 open 必须等待原生卸载确认，不能仅以 `Future.timeout` 释放所有权。无取消能力的适配器仍等待旧 open settle，原生卸载本身挂起也不授权并发重开。5s 看门狗仅由 progress/frame 续期；音频焦点暂停/抑制停止检测与重连。手动选线路重置恢复预算，前台恢复不重置；切换内核建立新控制器但继承页面静音。Exo 与 MPV 的首次 progress/frame 不自动等同于可比的像素首帧。

收尾源码补充：仓库增加 `channelOwners / epgLogos` 保存历史频道归属和来源台标缓存，删除来源同时清理可归属的旧偏好及上次播放标记；停用来源不开始刷新，刷新合并按来源及版本隔离。设置入口使用 `LiveTvPage(showBackButton: true)`，一级直播页不显示该返回按钮。播放页增加 session/attachment 代次、切换内核防重入和显式工具栏返回模式；这些后续实现不自动获得前置测试结果背书。

数据收尾边界：单表 10000 频道、每频道 64 线路、全表 50000 线路；手动排序后的新频道追加。刷新按 generation 合并，删除/禁用/同 ID 重建使旧响应失效；EPG 失败保留节目及台标，偏好新增来源归属，来源日志 ID 哈希化。数据专项 38 项、播放生命周期 19 项/Exo 通道 6 项与导航 48 项均单列在主机记录，不相加为最终全套结果。

直播取消、EPG 与备份的有效约束已归入 [实现契约](live-tv.md#实现契约)，不再维护实现前类名和任务分工草稿。实际入口以代码地图为准，历史验证见 [主机记录](performance.md#2026-09-20-直播前置验证快照)，不替代真实源或设备验收。

按业务拆分：

- `bootstrap`：启动预热
- `home`：首页模块装配与 Hero
- `library`：媒体源接入、`WebDAV` 索引、`Quark` 目录源、刷新、删除
- `live_tv`：独立直播订阅、频道、EPG、整理偏好与 MPV/Android Exo 专属播放会话
- `details`：详情页、详情缓存、手动索引入口、人物 / 公司关联影片页
- `metadata`：`WMDB / TMDB`
- `search`：本地搜索、在线搜索、夸克保存、`SmartStrm`
- `playback`：播放器
- `settings`：设置、配置导入导出
- `discovery`：豆瓣客户端、发现仓库与模型，没有独立主导航页面
- `storage`：详情缓存 revision 等辅助状态

### `tool`

仓库里的 `tool/` 目录除了开发辅助工具外，还承担外部品牌资源导出：

- `tool/generate_brand_assets.py` 会生成 Android、iOS、macOS、Web、Windows 的外部 App Icon
- 同一脚本也会同步生成启动页所用的 `assets/branding/starflow_launch_logo.png` 与 iOS `LaunchImage.imageset`
  这条链路使用最新的无白边满版彩色 PNG 原图，保留完整构图
- 同一脚本也会同步生成 Android 启动页使用的 `android/app/src/main/res/drawable-nodpi/launch_logo.png`
- 同一脚本也负责生成 Android TV Banner
- 所有品牌 Logo 当前以 `assets/branding/starflow_logo_source.png` 为设计源，应用内通过 `Image.asset` 加载生成的 `starflow_logo_primary.png`
- 脚本会先从 PNG 原图直接生成 `build/brand_assets/app_icon_raw_capture.png`
- 脚本会生成统一分发母版 `build/brand_assets/starflow_app_icon_master.png`；旧 Swift 入口转发到同一脚本
- 最后再缩放分发到各平台资源目录

### `scripts`

仓库里的 `scripts/` 目录当前除了开发辅助脚本，也包含 TV 与 Windows 打包链路：

- `scripts/build_tv_apk.ps1` 默认把 TV 安装包输出到桌面
- 支持按需临时嵌入配置 JSON，打包结束后自动清理
- TV 发布脚本内部固定使用 `flutter build apk --release --target-platform android-arm,android-arm64 --android-skip-build-dependency-validation`，单个 APK 仅保留 ARM 32 位与 ARM64，不包含 `x86_64`
- `android/app/build.gradle.kts` 的 release ABI 过滤同步限定为 `armeabi-v7a` 与 `arm64-v8a`，防止第三方原生库带入 `x86_64`；debug 构建不受此限制
- TV 文件名使用 `starflow-tv[-config]-主版本.月份.序号.apk`
- 当前显示版本号按标准三段式 `主版本.月份.序号` 自动递增
- TV PowerShell / Bash、iOS Bash 和 Windows PowerShell 发布脚本统一调用 `tool/release_version.dart`；默认按月递增，显式同批发布可用 `STARFLOW_RELEASE_VERSION`。Android `versionCode` 与 Dart 范围校验共用 `config/release_version.json`，显示三段版本与数字版本码是不同概念；运行工具会写入 pubspec
- Release 启用 `v1 + v2` 签名，通过忽略提交的 `android/key.properties` 显式配置既有安装身份；不回退自动生成的 debug key。历史证书为 Android Debug，发布校验固定其 SHA-256，保留覆盖升级能力，不代表已经迁移为新正式证书。
- `scripts/build_windows_installer.ps1` 默认把 Windows 安装器输出到桌面
- 这条脚本会先执行 `flutter build windows`，再调用 Inno Setup 生成单个安装器
- 当前安装器文件名使用 `starflow-windows-版本号-setup.exe`
- Inno Setup 编译器当前会优先在 `E:` 和 `C:` 下的常见安装目录查找 `ISCC.exe`
- `scripts/connect_mumu.ps1` 会扫描 MuMu 的 `vm_config.json`，优先尝试桥接模式的 `guest_ip:5555`，再回退到 `127.0.0.1:host_port`

## 3.1 缓存与调度策略

这一轮已经落地的 `P0` 收口主要有这些：

- 首页拆层：`_homeSectionSeedProvider` 负责来源抓取，`homeSectionProvider` 负责基于详情缓存 revision 的轻量装饰；详情缓存变化不再把首页整轮抓取一起打掉
- 首页重建范围收口：普通 section 改成各自独立订阅，`Hero` 当前项和分页状态也改成局部 `ValueNotifier` 监听，减少首页根节点重建
- 首页 presentation 落点也已进一步收口到 `home_page.dart`、`home_page_hero.dart`、`home_page_sections.dart`；页面主文件保留页面级状态、预取和焦点编排，厚的 Hero / section / shell UI 分别下沉到独立 part 文件
- 首页 `Hero` 后台补数新增快照去重与预取协同；同一批条目在首次进入、返回前台和高频 rebuild 时不会重复排队刷新
- 详情缓存批量化：`LocalStorageCacheRepository.loadDetailTargetsBatch(...)` 已接入首页和媒体库的卡片装配链，减少同一批条目的重复本地读取
- Emby 缓存分片化：`LocalStorageCacheRepository` 使用 `v2` manifest 管理来源 summary / fallback / section shards；来源根列表和分区清单读取最多 `400` 条 summary，分区查询只读取目标 shard，完整匹配才按最多 `2` 路解码全量分片；相同 snapshot / shard 的并发读取会复用同一个 Future
- 设置粒度收口：`home_settings_slices.dart` 以及设置 / 搜索页里的 slice provider 开始替代整份 `AppSettings` 宽监听，优先只让高频页面订阅自己真正依赖的配置片段
- 页面级保留态异步模式：媒体库、详情页、人物作品页已经改成 `RetainedAsyncController / resolveRetainedAsyncValue`，避免页面 inactive、路由切换和播放让路时重复闪回 loading
- 页面 inactive 任务治理：详情、媒体库、人物作品、搜索等页在失活时优先取消当前会话，而不是顺手 `invalidate` 掉已成功 provider，减少返回页时的重复拉取
- 搜索页渲染收口：结果区切到 `CustomScrollView + SliverList`，让长结果集按需构建，不再一次性把整个列表塞进单个 `Column/ListView`
- 详情页局部状态收口：完整候选仍由同一个 `ValueNotifier` 保存，UI 派生出按来源去重的“本地资源”视图和当前来源内的“播放版本”视图；两个 `ValueListenableBuilder` 分别刷新资源信息区与 Hero 下方版本区，不再带动整页详情重建
- 图片缓存收口：持久化图片缓存 identity 使用 `URL + headers`，并提供磁盘 metadata、`30` 天 TTL、stale fallback、坏条目定向淘汰与双阈值内存策略；图片 HTTP 请求统一 `15s` 超时，组件失败后按 `1s / 4s / 12s` 有限重试，同一候选图的进行中请求继续共享
- 绘制范围收口：页面背景 glow、桌面横向翻页按钮和海报卡片布局已经分别加上独立重绘边界或局部 notifier，滚动和焦点切换时避免整段区域跟着重建
- 性能设置解耦：移除统一性能档位，路由、导航壳、首页 Hero 和播放器分别读取独立设置；`AppSettingsPerformanceX` 只保留平台固定规则与必要的 `effective*` 入口
- 读链路与后台任务分离：空索引时的自动重建通过 `EmptyLibraryAutoRebuildScheduler` 后台 best-effort 调度，读链路不再同步阻塞一次重建
- 播放启动拆分：`PlaybackStartupCoordinator` 串起目标解析、续播/跳过准备与路由判定，`PlaybackStartupExecutor` 负责执行系统播放器 / 原生容器 / 内置 MPV 分支，`player_page.dart` 只保留页面壳和内置 `MPV` 打开编排
- `TV` 播放控制层收口：播放器页把高频控制状态合并成单个 notifier，替代多层 `StreamBuilder` 套娃，减少播放中叠层刷新成本
- 播放页 presentation 收口：`player_page.dart` 已继续瘦身，平台会话、启动/MPV、运行期动作和播放器控制拆到 `player_page_platform_session.part.dart`、`player_page_startup_mpv.part.dart`、`player_page_runtime_actions.part.dart`、`player_page_controls.part.dart`；控制叠层、播放设置、启动覆盖层、TV chrome 与运行期对话框拆到独立 widget 文件
- `mpv_tuning_policy.dart` 负责收口 `MPV` 的远程/直播识别、重片源判定、缓冲参数调节和本地 `ISO` 设备源判断，避免这些策略散落在页面状态里
- 首页 application 收口：`home_controller.dart` 现在主要保留 controller 与 provider wiring，`home_controller_models.dart` 承载 view model，`home_feed_repository.dart` 承载首页 seed/cached section 装配
- `PlaybackMemoryRepository` 已补单调递增 `updatedAt` 策略，保证最近播放在 Windows 或高频保存场景下仍按真正“最后一次写入”稳定排序
- NAS 索引链收口：`NasMediaIndexer` 已拆成 `nas_media_indexer_refresh_flow.dart / nas_media_indexer_storage_access.dart / nas_media_indexer_indexing.dart / nas_media_indexer_grouping.dart / nas_media_indexer_refresh_support.dart` 多段 `part` 文件；分别承载刷新编排、存储访问、metadata 匹配和分组。`IndexStore` 已有增量 upsert / patch 及分区查询，多层预算已有调度入口，不把这些能力继续描述为未来规划
- NAS 分区读链收口：显式分区查询直接交给 `NasMediaIndexStore.loadSourceRecords(..., sectionId: ...)`，Sembast 在数据库层组合 `sourceId + sectionId` 过滤；只有整源查询继续复用来源级内存缓存
- 首页模块加载与元数据预取已拆成独立调度器：前者限制首页数据源扇出并串行应用结果，后者统一约束 Hero、评分、元数据补全和显式维护任务；两者共享一个持久化最大并发值，各自保留首批数量和后续批次间隔
- 元数据调度器在前台交互结束后按可配置静默期恢复；首页、媒体库和集合页只在进入“内容加载中”状态时申请一次静默期，避免 widget rebuild 持续推迟后台任务
- 单击导航栏首页会触发统一软恢复边界：页面 revision 终止旧的 Hero/评分预取会话，媒体刷新协调器取消后台 NAS/WebDAV/Emby 刷新，首页与元数据调度器只清除自身的批次/静默等待并继续 drain；活动任务、前台 lease 和并发计数不会被强制归零
- `TV` 退出确认框使用短生命周期的元数据前台 lease，只在对话框显示期间阻止新的后台预取；取消后以零延迟释放，真正确认退出仍走播放器与系统会话清理，不复用导航软恢复
- 首页重新 active 或模块 ID 顺序变化时会在下一帧校验焦点所属路由；编辑器等已退出路由遗留的 FocusNode 不视为有效首页焦点。Hero 已可用时优先恢复到当前 Hero 卡；`homeNavigationResetRevision` 明确变化时即使当前停在普通模块，也会回到 Hero，但普通模块晚加载或内容变化不会抢焦点
- 首页按 `sectionId + resourceId` 为每张海报、轮播卡和 view-all 入口保留稳定 FocusNode，并给纵向模块与横向资源列表提供 key 到新索引的映射；标题或来源元数据补全和重排因此不会替换焦点节点。Hero 另跟踪来源 section，切换来源不会误继承同名资源的旧页码。焦点恢复优先选择已可见的 Hero；Hero 来源仍处于 pending 时保留 Hero slot 等待，不先把普通模块作为首焦点，Hero 到齐后才聚焦当前卡。Hero 未启用或为空时继续按首个实际有卡片的 section 定位，连续空 section 通过渐进滚动定位，全部为空时才使用“编辑首页”兜底
- 首页额外跟踪 section/item/view-all 的可聚焦拓扑；刷新移除当前聚焦目标时，下一帧只在焦点确实失效的情况下恢复到仍存在的首卡或其它有效内容。Hero 按资源 ID 同步页码和焦点，边界翻页按钮失效时退回当前 Hero 卡，普通列表更新不抢焦点
- 首页编辑器按模块 ID 保留开关焦点，并在来源异步变化、模块重排/删除、移动按钮到达边界及 sheet/dialog 关闭后校验当前路由焦点；只有原目标失效时才请求同模块或首个有效目标
- Android / TV 真正确认退出时，Flutter 先清理播放会话、媒体通知、画中画和后台播放，再通过 `starflow/platform` 进入原生退出窗口。`MainActivity` 持续跟踪按下的遥控器键并吞掉退出后的尾部事件；确认键已经抬起时等待 `120ms`，仍按住时等到全部按键抬起，未收到抬起事件则以 `2s` 超时兜底，再枚举 `ActivityManager.appTasks` 移除本应用全部 task。退出请求后的 `5s` launcher guard 会拒绝按键穿透或电视启动器自动恢复造成的 `MAIN / LAUNCHER / LEANBACK_LAUNCHER` 重启，桥接不可用时才回退 `SystemNavigator.pop()`
- `AppRuntimeRecoveryBoundary` 统一监听应用生命周期和内存压力。后台状态通过引用计数 lease 暂停首页 load/apply 与元数据 prefetch/maintenance 的新准入；恢复前台后等待首帧和固定 `400ms` 静默期再释放。内存压力使用独立 `2s` lease，并 best-effort 取消媒体库后台刷新，因此生命周期与低内存两种暂停可以安全叠加
- Flutter 的 `PaintingBinding` 会在内存压力时清理内存图片缓存；应用层只记录 `app.memory-pressure` 和降低后台负载，不重复清空 live/persistent 图片、不篡改活动请求计数，也不碰播放会话
- `NetworkRequestGuard` 的熔断状态增加显式半开探测配额。手动首页/详情/信息管理/媒体库刷新会为当前已打开的每个主机熔断器武装一次探测；第一个请求独占配额，成功移除失败状态，失败重新延长熔断，自动任务不会绕过熔断
- `QueueWaitDiagnostics` 为连续排队周期最多写一条 warning：首页和 metadata 阈值为 `5s`，TV raster 图片阈值为 `4s`；生命周期全局暂停期间首页与 metadata 计时器停止，恢复后重新计算诊断窗口，避免把正常后台驻留误判为阻塞
- TV 空焦点恢复不做常驻监听：只由 app resumed、branch 切换和退出弹窗关闭三个 revision 边界触发。连续两帧都没有可操作 FocusNode 时才显示侧栏并聚焦当前导航项；页面 autofocus 若已成功则第二帧再次检查并放弃恢复，不会晚到抢焦点
- 冷启动刷新已增加 Bootstrap 完成标记，主壳不会再重复执行同一轮首页刷新；是否刷新首页及 Emby 由独立持久化设置控制
- 网络层新增 `NetworkFailureInfo / NetworkRequestPolicy / NetworkRequestGuard`，统一错误分类、超时、幂等重试边界和按策略/主机隔离的熔断状态
- 诊断链新增结构化本地日志、敏感信息脱敏、文件轮转、固定区域预览、按级别记录/展示、日志清理及平台化导出；Android 还会合并上次 ANR、崩溃、低内存与资源异常退出信息

聚焦验证结果：

- 相关关键文件的 `flutter analyze` 已通过
- 首页装配、详情缓存批量读取、媒体库缓存合并、播放启动拆分、搜索仓库和空库后台重建相关测试已通过
- `test/perf/bootstrap_smoke_test.dart`、`test/perf/home_settings_slices_smoke_test.dart`、`test/perf/player_open_smoke_test.dart` 已通过
- `test/home_controller_test.dart`、`test/home_settings_slices_test.dart`、`test/playback_memory_repository_test.dart`、`test/nas_media_indexer_test.dart` 已通过
- `NasMediaIndexer` 拆分后的定向验证已通过：`dart analyze lib/features/library/data/nas_media_indexer*.dart` 与 `flutter test test/nas_media_indexer_test.dart`

## 3.2 跨模块调用关系

这一轮收口后，几条高频链路已经形成明确的“编排层 -> 解析层 -> 数据层”关系：

### Home

- `HomePageController`：负责首页模块 `prime / refresh / sections` 的页面级编排。
- `HomeFeedRepository`：负责首页模块 seed 数据装配（最近新增、最近播放、分区、豆瓣）和缓存装饰入口。
- `HomeHeroPrefetchCoordinator`：负责 Hero 后台补全调度（会话隔离、去重、暂停态跳过）。
- 首页 application 入口：
  - `home_controller.dart`：controller/provider 装配与页面级 refresh/prime 编排
  - `home_controller_models.dart`：`HomeSectionViewModel`、`HomeCardViewModel` 等视图模型
  - `home_feed_repository.dart`：首页 seed section 构建、批量详情缓存合并、最近播放标题映射
- 首页 presentation 入口：
  - `home_page.dart`：页面级 retained async、Hero 选择同步、prefetch 和焦点编排
  - `home_page_hero.dart`：Hero item 组装、分页、焦点、视觉层与背景素材选择
  - `home_page_sections.dart`：section slot、背景 shell、carousel、loading/empty、view-all 与海报 fallback 装配
- 首页 provider 关系：
  - `_homeSectionSeedProvider` 负责来源抓取
  - `homeSectionProvider` 负责详情缓存批量合并（`loadDetailTargetsBatch(...)`）
  - `homeSectionsProvider` 负责页面聚合

### Detail

- `DetailTargetResolver` 已作为详情解析入口，统一负责：
  - seed + 详情缓存合并
  - 自动元数据补全（`WMDB / TMDB`）
  - 通过既有来源客户端按需补全播放目标；飞牛在真正启动时仍重新解析临时地址
  - 解析结果回写详情缓存
- `HomeHeroPrefetchCoordinator` 与详情链路复用同一套详情缓存与 enrichment provider，避免首页和详情各自维护一套补全逻辑。
- 详情页 presentation 入口已经进一步拆成 `detail_page_providers.dart`、`detail_hero_section.dart`、`detail_resource_info_section.dart`，`media_detail_page.dart` 主要保留页面级 session / callback / section wiring。
- 详情首屏图片恢复独立于延迟启动：页面初始化通过 `peekDetailState` 同步检查内存缓存，未命中则立即读取本地详情缓存，期间不请求入口旧图片。初始展示目标沿用 `DetailCachedStateRestorer` 的来源与版本选择；普通单条缓存只叠加 artwork，不设置手动覆盖状态，不改变自动资源匹配条件。延迟启动复用这次本地读取，在线补全仍在资源状态恢复后开始。读取完成后检查页面存活和目标 generation，来源或季集切换后的迟到结果不能更新新页面。
- `mergeCachedDetailArtwork` 由首屏展示和 `DetailTargetResolver` 共用，缓存中非空的 `poster / backdrop / logo / banner / extraBackdrop` 优先，缺项保留入口值；图片 URL 与对应请求头成对选择，避免加载缓存图片时混入入口图片的鉴权头，也避免补全返回后退回旧背景图。图片占位目标仅用于展示，不传入联网解析或保存缓存。

### Playback

- `PlaybackTargetResolver`：先把播放目标解析到可播地址/headers。
- `PlaybackStartupCoordinator`：统一串起目标解析、续播/跳过配置读取与路由判定输入准备。
- `PlaybackEngineRouter`：封装路由判定（系统播放器 / 原生容器 / 内置 MPV）。
- `PlaybackStreamRelayService`：MPV/iOS 的 NAS/Quark 敏感凭据传输边界，逐跳隔离来源认证；每个播放器或原生会话拥有并释放自己的代理。传输目标与持久化媒体身份分离，认证清单格式限制见网络文档。Android 点播由 `NativePlaybackHttpDataSource` 保护实际媒体子请求。
- `PlaybackStartupExecutor`：执行路由动作，并返回是否继续走内置 `MPV` 打开链。
- `player_page.dart`：只保留页面壳、状态字段和顶层装配；平台会话、启动/MPV、运行期动作和播放器控制已经沉到 `presentation/widgets/player_page_*.part.dart` 与独立 widgets。
- `PlaybackMemoryRepository`：负责最近播放/续播记忆，并通过单调递增 `updatedAt` 保证最近播放列表稳定排序。
- `FntvSessionOwner`：管理新旧转码会话、回退和迟到结果清理；控制链接不作为下次播放的历史入口。

### Library

- `AppMediaRepository` 继续作为统一接口层。
- 查询职责已下沉到 `AppMediaQueryService`：
  - `fetchSources / fetchCollections / fetchLibrary / fetchRecentlyAdded / fetchChildren / findById / matchTitle`
- 刷新、删除、同步删除夸克与缓存清理等副作用仍在 `AppMediaRepository` 收口，避免查询链路混入副作用分支。

### Settings Slices

- 首页 slice：`home_settings_slices.dart`
  - `homeModulesProvider / homeDoubanAccountProvider / homeMediaSourcesProvider`
- 通用 settings slice：`settings_slice_providers.dart`
  - `settingsHeroSliceProvider`
  - `settingsPlaybackSliceProvider`
  - `settingsPerformanceSliceProvider`
  - 以及 media/search/network/match 相关 slice
- 依赖方向保持单向：
  - `SettingsController -> AppSettings`
  - `AppSettings -> 各 feature slice provider`
  - `Home / Detail / Playback / Library` 仅订阅所需 slice，减少整份 `AppSettings` 宽监听导致的重建。

## 3.3 网络与日志基础层

运行期网络入口分成“共享传输层”和“业务策略层”：

- `StarflowHttpClient` 是 Emby、WebDAV、豆瓣、元数据、搜索、字幕、夸克和 SmartStrm 等客户端的共享传输包装；默认等待响应头上限为 `20` 秒
- `NetworkProxyConfig` 保存运行期 HTTP 代理地址、可选 Basic 认证和局域网直连策略；`NetworkProxyRuntime` 提供进程内当前快照与 revision，IO 传输层在 revision 变化后为后续请求切换连接池，不中断已经交给旧连接池的请求
- 持久化图片缓存的网络读取也复用 `StarflowHttpClient`；`networkOnly` 图片先通过共享传输取得字节再交给 `MemoryImage`，不会绕过代理配置
- `network_failure.dart` 把错误统一归类为 `timeout / tlsHandshake / dns / connection / connectionClosed / httpStatus / circuitOpen / cancelled / unknown`
- `NetworkRequestGuard` 按 `policy + host` 保存连续临时故障状态，提供总请求超时、可选的幂等重试和熔断；`maxRetries` 默认 `0`，幂等请求也需调用方显式启用重试
- 豆瓣与元数据策略当前使用 `6` 秒总请求超时、连续 `3` 次临时故障后熔断、熔断 `2` 分钟；保留原有业务异常类型以兼容调用方
- HTTP `408 / 425 / 429 / 5xx` 视为临时状态；鉴权失败、资源不存在等永久状态不会触发临时故障策略
- 共享传输日志只记录 method、scheme、host、port、path、status 和错误分类，不记录请求头、Cookie、Token 或完整 query

日志层由 `app_log_api.dart`、平台实现和设置页组成：

- IO 平台使用 JSON Lines，保存当前日志、上一份轮转日志和 Android 原生日志
- 容量默认 `20 MB`，会在应用日志和原生日志之间预留预算并自动裁剪最早内容
- `TRACE / INFO / WARNING / ERROR` 的记录级别与预览级别独立持久化；默认记录 `INFO / WARNING / ERROR`，高频 `TRACE` 为排障时的可选级别
- 元数据成功缓存命中、加入已有请求，以及没有可用 NFO/图片的空 sidecar 上下文不逐条写入 `TRACE`；真实请求、失败和阶段完成仍保留
- 预览读取最近 `300` 条、展示筛选后的最新 `100` 条，TV 端条目和滚动区域均可聚焦
- 导出会合并轮转文件；TV 通过临时局域网 HTTP 页面和二维码下载，iOS 使用系统文件导出器，其他支持文件的平台使用对应文件流程
- Android 11 / API 30 及以上读取 `ApplicationExitInfo`，把上一进程的 ANR、Java/Native 崩溃、低内存和资源异常退出合并进日志；API 23 仍有原生日志，但没有这个系统退出信息接口
- Web 日志实现为不支持文件存储的 stub，不提供 IO 轮转和导出能力；这不表示 Android、iOS 或桌面的结构化日志关闭

## 4. 核心设计取向

### 本地优先

项目当前最重要的架构选择是“本地优先”：

- 设置先落本地
- `WebDAV` 先建立本地索引
- 首页、媒体库、详情页优先读取本地缓存或索引
- 在线元数据是补全链路，不是页面实时依赖

这让核心浏览体验更稳定，也避免让详情页承担过重的实时抓取职责。

### 统一模型

UI 不直接依赖第三方协议，而是尽量消费统一领域模型：

- `MediaSourceConfig`
- `MediaCollection`
- `MediaItem`
- `MediaDetailTarget`
- `PlaybackTarget`
- `HomeModuleConfig`
- `SearchProviderConfig`

### 已选分区作用域一致

无论是首页、媒体库、搜索还是手动匹配，都尽量以“已选分区”为同一作用域：

- UI 展示范围一致
- 刷新范围一致
- 搜索范围一致

## 5. 启动与路由

启动流程由 `BootstrapController` 驱动：

1. 读取本地设置
2. 对齐媒体源引用并清理已删除或资源身份已变化的来源缓存
3. 预热首页模块
4. 完成启动页过渡
5. 跳转主壳首页

启动阶段是轻量预热，不做重型阻塞初始化。

主路由之外，还有这些关键独立页面：

- 首页编辑器
  - 非 TV 端使用 `ReorderableListView` 拖拽普通模块；Android TV 为每个普通模块提供可聚焦的上移 / 下移按钮，两种交互复用同一模块移动与持久化路径。Hero 模块固定置顶，不参与排序
- 首页模块完整列表
- 分区列表页
- 详情页
- 详情页搜索页（`/detail-search`，复用搜索页并带返回工具栏，当前无转场）
- 人物 / 公司关联影片页
- 元数据索引管理页
- 字幕搜索页（`/subtitle-search`，可由 Android 第二个 Flutter engine 承载）
- 播放器页

## 6. 首页链路

首页不是固定模板，而是由设置驱动的模块容器。

当前模块类型：

- `Hero`
- 最近新增
- 最近播放
- 指定来源分区
- NAS / WebDAV 整个来源根
- 豆瓣兴趣条目
- 豆瓣个性化推荐
- 豆瓣片单
- 豆瓣首页轮播

首页装配特点：

- 模块配置持久化在设置里
- `HomeModuleConfig.libraryCollection / librarySource` 共用首页标题规则，为新添加的分区生成“来源类型 · 分区名”，整个来源根只显示来源类型，不追加“全部内容”；前缀固定为 `Emby / WebDAV / 夸克 / 飞牛`。只改变首页模块的 `title`，保留原始 `sourceId / sourceName / sectionId / sectionName`（来源根的 `sectionName` 仍为“全部内容”），不迁移已有标题，也不覆盖用户编辑的标题。
- 普通模块的 `HomeModuleDisplayStyle` 随 `HomeModuleConfig` 持久化，支持 `poster / landscape`；缺失或未知值回退 `poster`。页面保留相同 section、焦点键和详情路由，只按模块切换卡片宽度、图片比例和图片候选顺序
- `landscape` 使用 `16:9`，优先 `backdropUrl`，再回退 `bannerUrl / posterUrl`；Hero 与豆瓣轮播继续使用专用布局，不参与普通模块样式选择
- Hero 只引用选中的 `HomeSectionViewModel`，不会从普通模块列表中移除同一 section；自动 Hero 选中首个完成模块时，“最近播放”等首模块仍保留在 Hero 下方
- 首页设置读取已经开始从整份 `AppSettings` 拆到 `home_settings_slices.dart`
- 首页卡片最终统一映射到 `MediaDetailTarget`
- 首页条目当前分成两段装配：
  1. `_homeSectionSeedProvider` 先构建 seed section
  2. `homeSectionProvider` 再基于详情缓存 revision 做批量缓存合并
- 详情缓存 revision 更新时只会重跑第 `2` 段装饰层，不会把第 `1` 段来源抓取层一起重新执行
- 首页和媒体库读取详情缓存时会优先复用 `loadDetailTargetsBatch(...)`，避免同一屏卡片逐条走本地读取
- 首页页面层当前已经拆成 `home_page.dart + home_page_hero.dart + home_page_sections.dart`；Hero 子树、桌面翻页按钮和 section slot 不再和页面级状态堆在同一个主文件里
- 首页控制层当前已经拆成 `HomePageController + HomeFeedRepository + view models` 三层，页面、数据装配和 provider wiring 的职责边界更清晰
- 首页普通模块已经改成各自独立订阅；某个 section 更新时，不再让整个首页树跟着重建
- 首页 `Hero / item` 的运行时局部 overlay 更新现在可由设置统一关闭；关闭后，首页会保持当前静态快照，只在应用启动、保存设置或显式刷新边界后重新合并缓存
- 如果缓存里已经有刮削或手动关联后的标题，首页 `Hero`、卡片和后续详情入口都会优先展示这份标题，而不是继续显示原始文件名或 seed 标题
- 最近播放模块直接读取本地播放记忆，并优先尝试从详情缓存补海报
- 最近播放卡片会从 `PlaybackTarget.sourceName` 读取来源媒体库并以 19 号加粗、无边框、无背景的文字显示在海报右上角，使用双层黑色文字阴影提升亮色封面上的可读性，保留原有间距，其他海报角标样式不变；来源名为空时退回来源类型标签，不使用详情缓存里的来源字段覆盖播放记录
- 最近播放卡片的主标题会优先显示电影名或剧集总名；对于单集，`SxxEyy`、进度等信息继续留在副标题，不再把具体集名作为首页主标题
- Hero 当前主要外显配置是 Logo 形态标题、`normal / borderless` 展示方式和背景图
- 首页滚动区外层 `LayoutBuilder` 按实际可用高度计算 Hero 高度：扣除 Hero 外边距后取 `62%`，常规下限 `220dp`，普通/无边框上限分别为 `440/500dp`；空间不足时以预留 `140dp` 给分页区、下一模块标题和卡片露出为优先。加载占位和真实内容共用计算值与 `20dp` 分页占位，单项也保留分页高度。简介最多两行，元信息限制一行；局部布局结合文字缩放在矮窗口下依次隐藏简介、元信息，优先保留片名。
- `homeHeroAutoPlayEnabled` 默认 false，经设置模型、序列化、controller 和 `SettingsHeroSlice` 持久化；首页设置提供独立开关，TV 不禁用。`_FeaturedHeroState` 复用 `PageActivityMixin`，以可取消的单次 `6s` Timer 调度自动翻页；仅在首页活动、滚动区顶部且至少两项时准入，触摸按住、鼠标悬停、TV 焦点离开当前 Hero 卡时取消，恢复后重新计时。手动翻页与按键重置计时；列表或来源、展示模式、开关变化重置，dispose 释放 Timer 和监听。自动切换完成后仅在页面仍活动、来源和目标仍匹配且主焦点未被用户移开时跟随到可见 TV 卡片。
- “简化首页 Hero”仅控制翻页动画和装饰效果，与自动轮播独立；TV 不强制开启。简化时自动切图不执行动画，末项回首项也直接切换。
- Hero 页面由 `_HeroFocusedCardRetention` 按自身 `FocusNode.hasFocus` 申请 `AutomaticKeepAlive`：自动翻页结束并完成焦点交接前，旧持焦页面不被 `PageView` 回收，防止 Flutter 恢复到下方模块的历史焦点；失焦立即释放保留请求，不常驻全部页面。不放宽自动翻页末尾的用户焦点保护，主动移到其他控件仍暂停。
- 无边框自动翻页可能卸载旧卡片；旧焦点已卸载且当前没有可操作焦点时允许补到新的可见卡片，已有菜单或其他内容焦点时仍不抢焦点。
- Hero 会根据横竖屏优先选择对应方向的素材；横屏优先横图、竖屏优先竖图，只有单张图可用时会直接按海报布局展示
- `Hero` 当前项、翻页按钮和指示状态已经收口到局部监听；切换当前 Hero 时不会再带动首页根节点整块重建
- 首次进入首页时，如果 Hero 条目信息不全且还没有 metadata refresh 成功 / 失败标记，会后台 best-effort 补一次信息，并把结果写回详情缓存
- 首页 `Hero`、背景图与海报图会按显示尺寸传递 decode 尺寸；移动端 `PageController` 也做了边界稳定化，降低首屏切换和大图解码抖动
- 静态 Hero 与精简 Hero 视觉由一个界面开关原子更新，全屏背景图仍单独持久化
- `TV` 首页会给 Hero、模块标题和内容区之间补齐明确的方向焦点路径，避免焦点停在 Hero 图片层后无法继续下移
- 首页存在 Hero 时，首个有内容的普通模块通过局部上键动作直接请求 Hero 当前卡片；因此从该模块返回页头不会落到 Hero 的内部焦点作用域或不可用翻页按钮
- `TV` 信息管理页的搜索输入框只用 `goBack / escape` 退出编辑状态，不在输入框外层覆盖 `backspace`；软键盘删除键因此继续交给 `EditableText` 删除字符并保持输入焦点
- 桌面端首页普通横向内容流也会复用统一的左右翻页按钮，而不是只让 Hero 独占这套交互

## 7. 媒体库链路

媒体库通过 `MediaRepository` 统一对外，底层分两条主链路。

### Emby

`EmbyApiClient` 负责：

- 登录鉴权
- 分区获取与选择
- 媒体列表
- 子项读取
- 播放信息解析

`LocalStorageCacheRepository` 保存 Emby 库快照时使用一个轻量 manifest、最多 `400` 条的来源 summary 以及来源 / 分区 shards，并从 fallback 中剔除已经写入分区的重复条目。来源根列表与只需要分区清单的调用共用 summary，首页或媒体库读取指定分区时只解码目标 shard；完整标题匹配仍可读取所有分区，但解码并发固定封顶为 `2`，相同 snapshot / shard 的并发读取直接复用进行中的 Future。大分片 JSON 在后台 isolate 编解码。旧 `v1` 单文件 payload 不再读取、迁移或清理，只有当前格式可作为有效缓存；缺少当前缓存时会由正常 Emby 刷新重新生成。分片加载超过 `500ms` 时会写入 INFO 级 `storage.emby-cache` 诊断日志。

### 飞牛影视

2026-09-20 音轨补强：`NativePlaybackAudioTracks.serverStream` 反向映射保留不支持轨道的原始位置，语言别名归一化并结合声道，仅在完整列表数量一致时使用序号兜底；字幕回写也不再使用过滤后的序号。MPV / Exo 原画菜单额外列出服务端返回但实际流不可用的音轨，用户显式选择服务端转码档位后才重新申请会话，复用旧播放回退和迟到清理。Dart resolver 对显式且已消失的音轨 GUID 报错，避免静默回退。此改动不代表多声道转码、仅转音频、外挂位图字幕、FN ID / 双重验证或直播链路已经实现。

- `MediaSourceKind.fntv` 使用独立类型、来源身份和会话；`MediaSourceKindX.isMediaServer` 仅用于 Emby / 飞牛共享的媒体服务器调用边界，不表示两者协议兼容。
- `MediaServerClient` 定义分区、条目、子层级、播放解析和文件版本接口，family provider 按类型选取 `EmbyApiClient / FntvApiClient`；网络实现仍位于 library/data。飞牛客户端负责 v1 签名、鉴权、分页和统一模型映射，设置页负责会话测试及自动保存。
- `AppMediaQueryService` 复用现有来源 / 分区缓存布局，内部 `Emby` 命名的快照和刷新 API 为兼容现有调用保留；所有分片按来源 ID 隔离，每分区当前最多 `200` 条。飞牛图片 URL 保留在分片中，鉴权头在读取时从当前会话恢复，仅对同源图片添加；失败的飞牛刷新不会替换旧快照。
- `FntvApiClient` 的媒体库根列表按飞牛 Web 客户端契约传入完整浏览类型并排除了已归组的视频条目；直接目录浏览使用 `parent_guid` 并保留归组视频。剧集详情仍只通过 `season/list` 和 `episode/list` 建立季 / 集层级，不把根列表中的单集当作剧集。
- `fetchChildren` 的业务错误按父条目、季列表和剧集列表分别标记 operation，保留业务码且不输出服务器任意响应文本。只读条目 / 季 / 集接口的 `-6` 标记为 `isMissingItem`，由 `AppMediaQueryService` 精确解除该 parentId 的详情关联并继续抛出错误；不自动重试、重登或转换成空列表。刷新写接口的 `-6` 不触发关联清理。空标题的季 / 集使用 file_name 或季集编号兜底，负季号显示“未分季”。
- `LocalStorageCacheRepository` 的记录共享和结构恢复均拒绝同一飞牛来源下不同 GUID 的剧集之间恢复资源身份，防止删除重入库后 title / provider-ID 别名把新条目映射回旧条目；读取、批量读取及写入合并使用同一约束，不影响其他来源或同 GUID 文件版本恢复。
- 主页分区、媒体库筛选、本地搜索、详情匹配及版本选择包含飞牛；季 / 集通过服务端层级接口读取，连播队列不使用 NAS 索引。播放启动统一通过 `PlaybackTargetResolver` 重新解析飞牛地址，避免复用详情缓存中过期的临时链接。
- 飞牛来源每次进入媒体服务器缓存刷新前，`FntvApiClient.requestLibraryRefresh` 会对当前选中分区逐一致 `POST item/refresh`，请求体仅含 `item_guid`；未限定分区时先读取 `mediadb/list` 后刷新除音乐 / 直播外的库根。通知失败被记录并降级为仅本地刷新，不阻止随后 `fetchCollections / item/list` 和缓存快照落盘。手动“更新”、启动同步及“转存后刷新媒体库”选中的飞牛来源共用该顺序。
- `FntvApiClient.resolvePlaybackTarget` 按云盘类型和所选质量决定直链 / NAS 代理，不因 `pcm_bluray` 或 MPEG-TS 改写端点。STRM（9001）沿用服务端解析出的直链，不附带 NAS 凭据；本地文件与原本需代理的云盘类型保留 `media/range` 及质量索引。TS seek 兼容由 Android extractor 负责，而非在跨平台地址解析层强制绕行。
- `FntvApiClient` 在媒体流协商中传入当前会话摘要（协议字段 `ip`）及数组格式的 `header.User-Agent`，并向播放目标传递一致的默认 UA；服务端提供的外链 UA 优先。业务错误仅记录安全的阶段和错误码，不让请求体、会话摘要或响应正文进入日志。
- `PlaybackTarget` 携带飞牛音轨 / 字幕流描述、服务端默认流 ID 和 `direct_link_qualities`；`playback_server_track_resolver` 将服务端流映射到 media_kit 实际轨道。播放器启动只自动应用服务端默认轨道，已有剧集字幕偏好和“关闭字幕”设置优先；外挂字幕通过原始字节下载，播放器侧支持 ZIP 中的文本字幕和常见 UTF-8 / UTF-16 / GBK 编码，并拒绝位图字幕文本化。多个质量可在播放设置中选择，切换会保留当前位置并重新解析播放地址；播放器按节流策略调用 `play/record` 回写进度。
- `FntvPlaybackQuality.serverTranscode` 区分 `qualities` 与直链列表；直链保留非负协议索引，服务端转码使用负的本地选择 ID，不会写入 `direct_link_quality_index`。`qualities` 首项按飞牛契约视为原画，其余有效分辨率 / 码率成为可选转码档位。默认不申请转码；明确选择后由 `FntvApiClient` 调用 `play/play`，保留原始 `fntvSessionLink` 控制链接与完整轨道列表，同时输出 HLS 播放地址和 H264 / AAC 描述。显式轨道选择包括“字幕关闭”，不再被 `play/info` 默认值覆盖。
- 画质菜单由 Dart `fntv_quality_menu` 和 Kotlin `NativeFntvQualityMenu` 按相同规则分组：`2160 / 2160P / 4K` 统一显示 `4K`，数字分辨率统一为 `1080P` 等，原画及供应商命名保留；同名分组优先当前选择，否则使用服务端第一档。分组不改原始索引或档位列表；有重复分辨率时提供“自定义”，仅在二级菜单展示分辨率和码率，不显示 HLS / 转码技术标签。2026-09-20 增加分组策略及 Flutter 菜单回归测试，属于主机验证，不代表真实设备性能测量。
- `FntvSessionOwner` 管理活动和待打开的转码会话；MPV 页面与 `NativeFntvService` 分别持有 owner。切换使用新会话，不对旧会话原地调用 `media.resetQuality`，使解析 / 首帧失败时可以恢复旧地址；新画质就绪才释放旧会话，换集 / 退出 / 迟到结果调用 `media/p` 的 `media.quit`。Android resolver 仍只负责跨平台协议调用，Kotlin 不复制签名实现。MPV 已解析的切换目标通过显式 `targetAlreadyResolved` 跳过二次申请；外部首次播放仍重新解析。观看历史去除控制链接、起播参数及转码选择，避免恢复已释放会话或后台预取触发转码。原画继续走本地轨道选择，转码模式按服务端完整列表重新申请音轨 / 字幕组合；外挂文本字幕保持客户端渲染。
- 媒体源编辑器在地址、用户名、密码变更时清除飞牛会话和分区；过期登录及分区请求结果不覆盖已修改的草稿。来源删除、账户切换及地址改变沿用 `MediaSourceCacheLifecycle`。
- Android Exo 的 `NativeFntvController` 接入原生设置、字幕、运行期和换集生命周期。播放设置按飞牛目标生成固定可见的“画质 / 音轨 / 字幕”标签，并附带当前画质、音轨数和内置 / 外挂字幕数；画质不足两项时给出不可切换原因。TS 解复用额外识别 Blu-ray `HDMV/PGS` 文本轨；reader 跨 PES 聚合 `PDS / WDS / ODS / END` 等段，在显示集完整后交给 Media3 解析为位图 cue，字幕菜单与自动选轨因此可以正常显示；飞牛外挂文本字幕仍走原有下载链路。画质解析复用现有 episode resolver；字幕下载和进度通过同一 resolver channel 调用 Dart，`NativeFntvService` 持有来源与临时字幕目录，仍由 `FntvApiClient` 统一签名和鉴权。服务按 resolver session 隔离，退出后等待 `NativeFntvProgressQueue` 排空最后进度再关闭；初次画面就绪不是会话结束。换集 / 关闭使旧画质及字幕结果失效，质量切换首帧失败或启动超时会尝试回退；原生轨道偏好按新轨道匹配，不复用旧轨道组 override。
- 飞牛与 Emby 共用后台刷新并发预算和启动刷新开关，进度标题按实际来源类型展示。该接入不新增扫描服务，不改 WebDAV / Quark 索引；转码只由显式画质 / 转码轨道选择触发，不执行 FN ID 中继发现。

### WebDAV

`WebDAV` 页面消费模型不是“页面实时扫目录”，而是“索引驱动”：

1. `WebDavNasClient` 扫描目录
2. `NasMediaIndexer` 做识别、聚合和补元数据
3. `NasMediaIndexStore` 把结果落到本地
4. 首页、媒体库、详情页优先读取索引

补充约束：

- 媒体库只保留“增量更新”和“重建索引”入口。手动增量按来源清除持久化 WebDAV 子目录快照、遍历所选分区，保留扫描上限和并发预算；完整扫描才更新已有结构或删除缺失记录。不引入目录级缓存迁移、持久化刷新队列或后台轮换补扫
- 保存后的自动刷新沿用普通增量刷新路径，OpenList/AList 中的 STRM 通过其 WebDAV `/dav/...` 地址读取
- 增量阶段的 sidecar 和在线元数据补全只针对新发现文件执行；已有记录的缺失或失败状态不在增量阶段重试，旧条目修复交给重建索引或显式元数据操作
- 只有当当前作用域索引为空时，才允许在后台调度一次自动全量重建；读链路本身不再同步等待这次重建
- 指定分区的普通读取保持媒体源原有索引作用域：先由 Sembast 使用 `sourceId + sectionId` 精确过滤；若记录统一归属扫描根，再读取同源记录并按规范化 URI 目录段边界过滤。点击 `quark` 等子目录不会把它临时冒充成新的索引作用域，也不会误混入 `quark-old / 115` 等相邻目录
- 每份 NAS / WebDAV / Quark 索引状态持久化媒体源资源身份；同一 `sourceId` 的 endpoint、根路径或 Quark 根目录变化时，启动与设置保存链会停止旧扫描并清除该来源的索引、WebDAV 目录快照、内存聚合结果和详情页本地资源关系，再由当前来源正常重建
- 媒体源删除或配置导入后，索引 state、记录、WebDAV 子目录快照、Emby snapshot 或详情缓存中找不到对应设置来源的孤儿缓存都会按来源清理；在线海报、简介和评分仍保留，播放历史不作为来源缓存删除
- 本地存储页清理“媒体库索引”走同一失效版本与取消链，同时清持久化和内存态，不再直接只删 Sembast 表
- 旧静默 trace 调用、专用格式化函数和兼容 helper 已删除；异常记录直接进入结构化日志系统，原生退出捕获、预览、筛选、清理和导出保留

`NasMediaIndexer` 负责的事情包括：

- 文件指纹
- 标题、年份、类型、季集识别
- 目录名 / 文件名里的 `{tmdbid-...}`、`{tvdbid-...}`、`{imdbid-...}`、`{doubanid-...}` 等嵌入式外部 ID 标签清洗，避免污染识别标题、系列分组标题和 metadata 查询词
- 包装目录 / 版本说明忽略，例如 `分段版 / 特效中字 / 会员版 / 导演剪辑版 / 清晰度 / 音轨 / 字幕` 等目录不会再被当成系列名
- 电影版本目录使用保守的兄弟目录规则：同一影片根目录下至少两个技术标签目录同时存在，且所有文件都无明确季集信号时，才会被标记为同一 `movie` 的多个可播放版本；技术标签包含清晰度、音轨/语言（如英语、日语、韩语）、字幕和码率等组合；版本目录下的 `Disc / CD / Remux` 等嵌套组织层会继续沿用外层影片根目录，`S01E01` 等剧集标记和 `4K 12集` 这类剧集包装层不进入该分支
- 结构推断无法确认版本或季集时，索引仍优先采用媒体源下的一级媒体目录作为叶子项名称；文件名仅在文件直接位于媒体源根目录、没有可用目录名时作为最后兜底。电影目录名中的年份等括号内容会原样保留，但发布文件名即使包含目录标题也不会覆盖稳定的目录标题，例如 `两杆大烟枪/Top026.两杆大烟枪...strm` 仍以“两杆大烟枪”入库
- 在线元数据的类型偏好以索引最终类型为准：明确的 `movie` 强制按电影候选匹配，只有 `episode / series` 或尚未明确为电影的识别结果才允许启用系列偏好，避免同名电影被目录启发式误配为电视剧。完整增量扫描更新未手动锁定记录的本地分类和季集，保留在线元数据；重新搜刮通过重建索引或显式元数据操作进行
- 单个电影发布包装目录是上述兄弟规则的窄例外：外层是有效片名、仅有一个“片名 + 年份 / 语言 / 字幕”子目录、子目录内只有一个无季集信号的视频时，直接使用外层目录名并索引为 `movie`；不会把 `strm / quark` 等传输目录当标题，也不会覆盖明确 NFO 标题
- 一级影片目录如果遍历后只有一个直接视频且没有子目录、季集号或 NFO 剧集信息，会在结构分配前锁定为 `movie` 并使用一级目录名作为卡片标题，不会被上层媒体库的剧集候选根误挂为 `webdav-series`；公共 `strm / quark / WebDAV` 目录下其他剧集的证据不会跨片名串入；但若同一片名目录的祖先存在明确季目录、集号、剧集 NFO 或其他强剧集证据，则保留剧集分配，兼容“一集一个文件夹”的剧集布局，结构规则版本变化时旧分组会自动重算
- 非传输目录一旦拥有子媒体目录，子目录和子文件统一归属于该父媒体；没有明确季标记且直接只包含一个视频的子目录折叠为单集包装目录，多个此类目录归入同一第 1 季。包含多个视频且无法识别为电影版本或明确季集的子目录仍按隐式季分配，不会把子目录名或子文件名提升为新的剧名/电影名
- 子目录即使继续包含更深层文件夹，也保持最近父媒体目录的归属；结构分组先按 `sectionId` 与资源路径公共前缀自动剥离来源/分区根，再跳过内置的 `movies / strm / quark / WebDAV / NAS` 等常见包装层，取其后的第一个有效媒体目录作为剧名，不依赖手动过滤设置。只有传输目录之外的父根才能建立剧集分组，例如 `我的事说来话长/剧版/01.strm` 的 `剧版`只能作为隐式季，不能生成第二个系列；同一系列根目录下的特别篇进入第 0 季
- `NasMediaPathPolicy` 是外部存储路径语义的唯一入口：统一解析设置路径/分区路径与资源路径的公共前缀、默认及自定义包装层、首个电影目录、系列标题与结构根、嵌套电影发布目录。`WebDavNasClient` 的扫描分类与 `NasMediaIndexer` 的入库、搜刮和展示分组只消费该策略结果，不再各自维护目录常量和回退链
- 系列路径解析一次返回 `NasSeriesRootResolution`，其中同时包含标题、结构根片段和公共边界状态；展示标题与 `webdav-series` 分组键必须来自同一结果，避免标题使用父目录而分组键使用子目录
- 结构候选根会排除 `movies`、`strm`、`quark`、`WebDAV` 等传输或媒体库包装目录；扫描从具体媒体目录开始时仍保留空相对根作为有效剧集根，兼容分区扫描
- 当前作用域版本为 `NasMediaIndexer._webDavMetadataSchemaVersion = webdav-v17`；版本变化会使旧作用域重新索引。`ExternalMediaStructure` 随 seed/record 持久化作品目录、类型、角色、季集与证据强度；结构指纹包含归属与证据。完整增量扫描可本地重分类旧记录，不重新发起 sidecar/在线请求；显式 episode NFO 数字优先于文件名和推断值，人工锁定继续保留
- 电影多版本会在详情页 Hero 下方提供直接可见的“播放版本”选择控件；“本地资源”仅按来源分组并负责来源切换，播放版本仅按当前来源展开，两个选择互不混用，版本辅助行统一收口为来源、分辨率、首个格式和文件大小；`.strm` 包装文件的格式和大小不会进入辅助行，只有当前选中版本经详情解析器取得真实地址后才展示源视频格式和大小；NAS / WebDAV 详情路由没有携带原始目录范围时，会使用已经确定的 `sourceId + sectionId + itemId` 读取现有索引，而不是错误地重算整源范围键，因此选中目录索引里的版本不会被隐藏；WMDB / TMDB 匹配统一使用影片根目录名，清晰度和编码等文件名后缀只保留给版本展示，明确匹配的 NFO / sidecar 标题优先
- `顶层推断目录` 仅补充一级媒体目录之前的非标准自定义包装层；来源根、所选分区根和内置常见包装层由扫描上下文自动过滤。确定一级媒体目录后，更深处的公共或过滤目录不能重置边界。
- 2026-09-24：结构推断开启时，一级媒体目录是最高优先级归属边界，每个目录最多一个剧集或电影入口。`groupSeriesRecords` 将同一目录的混合类型记录纳入已有剧集；无剧集证据的多资源目录由 `groupMovieVariantRecords` 统一生成电影入口，并保留全部播放版本。目录分组身份只含来源和完整实际目录路径，不依赖浏览分区，也不按同名或元数据 ID 合并不同目录。扫描以配置根目录解析归属，子树刷新不能另起作品；全源分组结果复用于分区查找表。`全10集` 等发行目录不能走电影版本分支；母目录名紧接数字的文件补充集号，同集多版本保留。未带集号的旧电影记录进入剧集后按资源保留，不按相同电影标题吞并。
- 已知音频及音频 STRM 在视频结构分析前排除；花絮先分离，再附回作品，不参与主体类型判断，电影代表资源优先选非花絮。无剧集证据的平铺画质版本或明确电影 NFO 不按文件数量推成剧集。删除路径读取同一归属，使用前校验目录确实是资源祖先；没有有效作品目录的根部散文件不能扩大为整个来源根删除。
- 2026-09-24 结构证据：`structure_evidence.dart` 定义字段、来源、三档置信度、稳定规则编号及冲突观察；`ExternalMediaStructure.fieldEvidence` 覆盖 `rootPath / rootTitle / itemType / role / seasonNumber / episodeNumber`。扫描模块在实际分配分支记录 `number.filename / number.directory / episode.title-suffix / episode.grouped-leading-number / episode.unnumbered-order / season.sibling-directory` 等规则；文件名与完整路径的解析结果仅在当前扫描内复用。根目录所有权与由类型派生的角色仍是策略推断，不伪装为 NFO 或人工确认。
- 季集证据合并使用显式 `priority`，不依赖枚举顺序：manual > sidecar > filename > directory > inferred > unknown；相同优先级使用新值，旧的空值不能压过有效新值。此优先级只用于已有编号合并，不允许 NFO 更改一级目录所有权。NFO 编号、类型冲突及扫描时的名称/sidecar 冲突保留选中值、被舍弃值和各自规则，冲突是历史观察而非待应用指令；重复去重并限定 32 条，不保存原始 NFO、认证信息或整条请求地址。
- 证据与冲突参与结构相等比较，完整增量复用即使仅证据变化也会落盘，仍不重抓在线元数据。旧 JSON 的季集证据标为 `legacy.evidence`，其他字段未知；未知未来字段忽略、未知来源降为 unknown。保持当前作用域版本，不因新增诊断字段强制全库重新搜刮；已有人工锁定和不完整扫描保留语义不变。没有新增手动结构编辑 UI，也不把已有元数据锁定伪称为逐字段人工证据。
- `ExternalScanResult.complete` 区分完整与截断扫描；WebDAV 条数/深度截断、夸克缺少凭据或客户端不可用均不可据缺失删除。任一分区不完整时，整次来源刷新保守保留未见旧记录与已见旧记录分类，包括强制重建及其补全候选；新发现资源仍可入库。不宣称按单目录精细清理或自动补扫。
- 综艺/节目文件名轻量识别，例如 `第X期`、`01 会员版` 这类“集号 + 版本说明”形式会继续归到对应集，而不是把版本说明当标题主体
- 结构已经确认属于同一剧集分组时，如果同组中尚无显式季集标记的文件全部具有 `数字 + 分隔符 + 标题` 前缀，则该数字作为稳定集号参与排序与聚合；因此 `1 / 2 / 10 / 28` 按数值顺序展示并保留缺号，不把这条规则扩散到未确认类型的普通电影目录
- `NasMediaRecognizer` 解析父目录单集提示前移除 `E01-16 / EP01-16 / E01-E16` 等递增范围，避免合集目录将全部子文件赋为第 1 集；范围中的 `S01` 仍可提供季号。结构推断的组内数字前缀允许紧接括号说明，保留 `16(1080x264).(mp4).strm` 的真实集号。该分类变更纳入 `webdav-v17`；命名样本回归覆盖《局部》三季的 `16 / 16 / 12` 个独立文件。
- sidecar 读取
- `streamdetails`
- 外部 ID 提取
- `WMDB / TMDB` 在线补全，并继续保留上游返回的 `IMDb ID / IMDb` 评分标签
- 对开启目录结构推断的剧集条目，`WMDB / TMDB` 先统一使用目录推导出的剧名匹配，同剧各集共享进行中或已缓存的系列结果，不再将每个单集文件名反复提交给在线搜索；可选的“剧集复用系列级图片”还会跳过单集 still 请求，并把匹配年份固定为系列目录年份（目录无年份时统一使用无年份键），避免单集上映年份拆散系列缓存
- `MediaItem` 生成
- 剧集父子关系聚合
- 电影多版本聚合以影片根目录为边界：媒体库只生成一个代表卡片，底层索引保留每个真实资源（包括版本目录下的嵌套文件），详情页的“播放版本”优先正片，再按可播放性、元数据完整度和画质排序展开。该结构规则使用条目级指纹；完整增量重算本地结构，NAS 索引数据库升级时旧索引不读取，由当前版本重新建立
- 目录名里如果能识别出明确季号，例如 `Season 1`、`S02`、`SE08`、`第2季`、`Stranger.Things.S02.2160p.BluRay.REMUX`，会直接把这一层当作季目录
- `SE08.06` 这类文件名会同时提供季号和集号；结构推断确定母目录为剧集根后，母目录名是唯一剧名，子目录/文件只提供季集与单集展示信息。标题中间的 `#19`、子目录开头的 `#004`，以及名称修正去掉井号后保留的三位补零编号 `004` 都可作为第 1 季集号，子目录不能另起剧名或独立季。母目录若已有 `S01E01` 或明确数字集号，`4K HDR / DV / SDR` 等子目录中的数字文件也沿用第 1 季，不会落入电影或特别篇。当前 schema 为 `webdav-v17`；完整扫描才允许刷新已有结构，不能用截断树覆盖旧归属
- 对 `2.巴以 / 5.美国 / 9.韩国` 这类“数字 + 标题”的专题目录，会额外要求同级里存在多个同类兄弟目录，避免把普通数字目录误判成季
- 明确剧名下面的多个年份分组目录（如 `2025 / 2026（4K）`）保留原目录名作为季名，索引与在线系列查询都继承上级剧名；`4K 12集` 这类只表达画质、版本或总集数且看不出季名的目录会折叠为包装层，文件有明确季号时按文件季号归组，否则进入默认季；媒体源顶层的纯年份目录不会因此被强制吞并
- 当年份已经作为独立字段识别时，WMDB / TMDB 客户端会从查询标题末尾移除同一个年份；纯年份标题不会被清空，标题中不同年份也不会被误删
- `DetailCacheStore._enqueueMergedDetailTargetSave` 用 `16ms` Timer 合并待保存详情目标，再通过 mutation tail 串行写入；`LocalStorageCacheRepository` 保留公共入口并委托给该组件。编码结果与最后落盘内容完全一致时跳过写入；清理先排完已接受批次，dispose 冲刷批次并停止通知。这保留了组件拆分期间已有的批量写入优化，不再是历史 `scheduleMicrotask` 实现。
- 一旦当前层被识别为季目录，上一级目录就会作为剧名；像 `怪奇物语/Season 1/Season 2`、`怪奇物语/Stranger.Things.S02.2160p.BluRay.REMUX` 都会把 `怪奇物语` 当剧名
- 当路径里已经确认存在显式季目录时，即使当前只有一季，也会继续保留“剧 -> 季 -> 集”层级，不再因为单季而直接拍平成集列表
- 当前实现上，`NasMediaIndexer` 已拆成 grouping / refresh flow / storage access / indexing / refresh support 多个 part 文件；并发预算在 indexer 内按 `source / collection / enrichment item` 三层收口，三层与首页、元数据调度统一读取同一个最大并发设置，并分别受来源最多 `2`、集合和单源补全最多 `4` 的内部保护。同一来源的 sidecar / 在线补全由固定 worker pool 处理，每个条目同时进入全局元数据并发预算；用户主动全量重建的条目使用 maintenance permit，绕过普通后台批次与交互静默等待但仍受并发上限约束；每轮任务开始前读取最新持久化设置，修改后无需重启
- `WebDavNasClient` 在一次扫描周期内按来源与目录缓存 sidecar 共享上下文；同目录条目复用父级 / 祖父级目录列表、季与系列 NFO、通用海报及背景图片解析，只保留每个视频自身 NFO 和同名图片的必要检查
- Emby 来源的分区缓存刷新不再直接 `Future.wait` 无界并发所有分区；每个分区作为 maintenance 任务进入同一个全局 metadata limiter，与 NAS 条目补全共享上限并优先排空显式刷新

当前文件组织上，`NasMediaIndexer` 已按职责拆成：

- `nas_media_indexer.dart`：公共入口、共享小工具、对外方法与少量胶水代码
- `nas_media_indexer_refresh_flow.dart`：刷新编排、后台补全、自动重建、作用域删除、详情补全入口
- `nas_media_indexer_storage_access.dart`：记录复用、手动 metadata 回写、source records cache、library match cache
- `nas_media_indexer_indexing.dart`：识别、在线 metadata 匹配、query 规范化、指纹与 scope key 计算
- `nas_media_indexer_grouping.dart`：剧/季/集分组、结构推断、展示排序与合成 item
- `nas_media_indexer_refresh_support.dart`：source/collection 级并发辅助、取消控制与刷新句柄

媒体库页额外提供这些运维动作：

- `增量更新 WebDAV`
- `重建 WebDAV 索引`
- 单条资源手动索引
- 单条资源删除 `WebDAV` 文件或目录
- 删除文件时会优先使用记录里的真实 `resourceId / URI` 发起远端 `DELETE`
- `DELETE` 返回成功后还会重新检查父目录，确认远端文件确实已经消失；如果远端仍存在，则不会继续把本地当作已删成功
- 如果网盘与转存里开启了“同步删除夸克目录”，并为它选中了监听的 `WebDAV` 目录，那么只要删除命中了这些目录下的文件或文件夹，就会按当前夸克保存目录去匹配并同步删除对应影片或剧集目录
- `TV` 模式下媒体库筛选、分区入口、分页按钮都使用可聚焦控件，并尽量恢复到上次浏览位置
- 媒体库卡片读取详情缓存时也会复用批量缓存读取，不再为同一批条目逐条扫描本地详情 payload
- 媒体库当前可见页现在也支持切到“静态快照”模式；关闭运行时 overlay 后，只会在当前分页首次装配时做一次缓存合并，后台 metadata 更新不会再把可见页之外的条目带进重算

### 网盘工作流与 Quark 来源

目录型剧集详情的资源选择优先匹配入口 `sourceId + itemId`（或播放目标的 seriesId），再使用来源偏好，防止同一 NAS 下的同名副本覆盖入口目录。

详情缓存兼容性校验对 `webdav-series|` 目录型剧集额外比较 `sourceId + itemId`，不同根目录不能通过同名或元数据 ID 别名共享整份详情记录及本地资源选择。普通读取、保存合并和结构不匹配恢复均执行该检查，旧别名指向其他目录时视为未命中；单集手动版本选择的既有规则不变。

`Cloud115SaveClient` 统一网盘 API 和验链请求头，保留 GET 读取、POST 表单写入的接口契约，禁用重定向；HTTP 失败按操作阶段反馈，405 不自动重试，也不判为永久失效。此变化不影响夸克客户端。

搜索页在网盘分流前通过 `resolveSearchSaveFolderName` 统一选择转存目录名：普通搜索取当前搜索词，收藏优先 `favoriteFolderName`，缺失时回退标题。`cloud_save_rules.dart` 管理公共路径、目录名、文件主体名称清理和匹配键；`CloudSavePlanner<T>` 管理目录创建/复用决策、单层分享展开、递归去重、冲突检查和新增条目范围。两客户端只适配各自分享/网盘列举、创建和接收接口；不再维护独立递归规划器。默认目录末段已同名时直接使用，复用目录返回实际大小写路径。两工作流均使用保存结果的实际目标路径触发 STRM；夸克旧函数名与结果类型别名仅保留调用兼容，不含第二份规则。

`DetailOnlineResourceUpdateService` 匹配夸克与 115 在线收藏，排除本地详情收藏，按既有外部 ID / 标题评分稳定排序；页面有多个候选时显式选择更新来源。仅使用所选网盘的 Cookie、目录 ID / 路径和名称修正设置，接收码通过 `prepareSearchResultShareCredentials` 传递，不回退到另一网盘账号。确认后调用各自保存工作流，复用独立 STRM 任务名和实际目录刷新，不在详情页重写转存后处理。

两客户端的 `previewSave` 适配 `CloudSavePlanner.preview`，与 `build` 共用目标目录解析及单层展开；预览不调用建目录回调。递归收集双方目录的相对路径，`CloudSavePreview` 按公共文件名键比较缺失视频，启用改名时逐段清理并保留文件扩展名；路径来自实际遍历，不依赖网盘条目携带的绝对路径。缺失目标不创建，重复 ID、同名歧义、文件/目录冲突、异常路径或过深目录报错；不按集号或内容去重。检查开始即锁定按钮，关闭选择/结果弹窗不保存，页面销毁或切换目标后忽略旧结果。新增规则与接口测试位于 `test/features/search/application/`、`test/features/search/data/`，详情服务和交互测试位于 `test/features/details/application/`、`test/features/details/presentation/`。

`CloudSavedNameSanitizer` 统一新增范围解析、冲突预检和递归改名计划，`processCloudSavedNames` 统一开关、转存完成状态、失败提示及 STRM 放行条件。`CloudSavedEntry` 记录目标父 ID、名称、类型及转存前已有 ID，排除旧文件；文件扩展名保留，目录按全部名称清理。先完整读取改名范围再写入；同名歧义、读取失败或子树不完整时不盲目改名。夸克通过既有任务 API 确认落地；115 开启改名时通过规划器记录待存子树清单，公共改名器最多 3 轮只读核对其完整可见性，随后调用 115 改名 API，并按父目录复查已接受改名的 ID / 新名称。未完成或失败时保留转存成功数量、提示警告且不触发 STRM，不自动重试写操作。此能力不需要单独网盘业务规则；115 特有的是完成确认与接口适配。

`NetworkStorageConfig` 新增 `cloud115SanitizeSavedNamesEnabled / cloud115SanitizedNameCharacters`，默认关闭与 `#%?`；夸克原字段不迁移，独立保存、导入、导出和同步。两网盘编辑页复用同一组改名控件，只写当前网盘的改名字段。公共规则测试位于 `test/features/search/application/cloud_save_rules_test.dart`，115 接口测试位于 `test/features/search/data/cloud115_name_sanitize_test.dart`；不修改独立同步删除的路径匹配边界。

115 对已有命名目录预先构建递归转存计划：完整分页读取目标目录，去首尾空白且不区分大小写匹配文件名，同名文件跳过、同名目录下钻，缺失项按目标父目录分批转存。所有读取和冲突检查结束才开始提交；新建目标不额外扫描空目录，无有效保存名时维持直接转存分享顶层结构。多候选、文件/目录冲突、标识缺失或重复、目录名缺失、分页不完整均停止；创建目录必须返回有效 ID，不回退根目录。多批次中途失败显示已确认保存数量，当前批次不确定结果要求先检查远端且不自动重试。全部重复不触发 STRM 或刷新，不以内容哈希或集号去重，不整理历史 `(1)` 目录；也不改变 SmartStrm 的输出命名规则。

115 扫码登录由 `Cloud115LoginClient` 和 `Cloud115LoginPage` 负责：获取二维码、串行轮询、确认后换取 Cookie；页面关闭或刷新时废弃旧请求结果并停止定时器。Cookie 返回网盘编辑器，仍复用普通自动保存链触发保存，但 `NetworkStorageConfig.toJson()` 不输出该字段；本机仓储将 Cookie 写入独立的本地凭据项。普通配置导出、导入、局域网传输和 WebDAV 同步均不携带 115 Cookie，导入配置也不会覆盖当前设备凭据。登录请求不使用记录 HTTP 错误的包装客户端，异常提示不输出响应、二维码令牌或 Cookie。

115 删除由 `Cloud115SyncDeleteService` 独立预检和执行，接入媒体库 WebDAV 删除链。`syncDelete115Enabled / syncDelete115WebDavDirectories` 独立持久化，默认关闭。只匹配精确 sourceId 与 URI 路径段范围，逐层解析监听目录到保存目录的相对路径；STRM 可映射到唯一同名视频。不允许根目录、多个候选或跨网盘重叠，预检失败不会删除 WebDAV。WebDAV 成功后才调用 115 回收站接口，115 失败提示部分完成并保留本地索引。115 不复用夸克的模糊删除匹配或 403/405 回退，但来源编辑、删除和配置导入已通过公共来源路径规则协调两种监听目录，无法确认的引用移除后需重新选择。两种网盘的同步删除配置和目录管理均位于各自设置页；目录管理复用现有确认交互，115 使用自己的客户端。直接管理网盘不会清理 STRM 或触发生成任务。

整剧条目的 `actualAddress` 使用公共 `NasMediaPathPolicy.resolveSeriesRoot` 提供的实际目录深度，从原始资源路径截取同一剧名根目录；保留大小写、编码和 `(1)` 后缀，不从展示标题反推路径。`NasMediaIndexer.buildSeriesItem` 要求组内根路径一致，不能因全部视频位于一季或一个子目录就把整剧地址缩到这一层。单季仍取该季资源共同目录，单集仍取文件 URI。NAS 索引数据库升级时旧记录不读取，当前版本重新物化文件记录，不改变剧集分组 ID，也不自动清理历史残留目录。

WebDAV 与 115 同步删除接收同一选定目录范围，包含范围内全部图片、字幕、NFO 等附属内容。`WebDavNasClient.deleteResource` 对文件和目录均直接读取父目录确认，不复用扫描缓存或排除关键词过滤，也不吞掉读取失败；目录 URI 比较忽略末尾斜杠。`Cloud115SyncDeleteService.execute` 在回收站接口返回成功后完整读取父目录，确认目标 ID 消失才报告成功，未确认不重发写操作。确认弹窗说明整目录及附属文件范围；回归测试在 `test/features/library/data/` 覆盖单季整剧、单季删除、单集删除、特殊字符、独立 `(1)` 路径及远端结果未确认。

115 分享转存由 `Cloud115SaveClient` 与 `Cloud115SaveWorkflowService` 适配公共规则，不作为新的直连媒体源。网盘与转存配置保存 `cloud115SaveFolderId / cloud115SaveFolderPath / cloud115SmartStrmTaskName` 等非敏感选项；`cloud115Cookie` 只作为当前设备的本地凭据参与运行，不进入配置 JSON。默认根目录、未登录、无 115 STRM 任务。目录选择器通过可选加载回调复用现有 TV 焦点及面包屑交互。搜索及收藏结果按链接类型分流保存。115 转存有新增内容后先完成可选名称修正，再复用 `SmartStrmWebhookClient` 和公共 Webhook、延迟配置，使用独立 115 任务名及本次实际保存路径（根目录省略路径覆盖），最后调用媒体源刷新协调器安排后台刷新；115 任务名留空时不触发，也不回退到夸克 `smartStrmTaskName`。各自网盘设置页承载自己的任务名与测试按钮，测试使用该页当前草稿中的任务名和默认保存目录；公共 SmartStrm 页只包含 Webhook 和延迟。STRM 失败仍尝试刷新，后续失败保留保存成功状态，后台刷新失败单独提示。Webhook 应答仅表示触发已受理，不等待远端生成任务完成。不调用夸克同步删除；若 STRM 重命名导致相对路径与 115 不同，独立删除预检仍拒绝猜测映射。

115 同步删除预检的 `resourcePath` 由 `WebDavNasClient.resolveResourceUri` 从实际删除入口解析，与 DELETE、STRM 读取及 sidecar 地址解析共用同一方法；不使用索引中仅供显示及缓存清理的 `record.resourcePath` 匹配绝对 URI。已入库文件保留原资源 URI，目录和分区相对路径按原 WebDAV 规则补齐域名及路径，不放宽跨域或根目录限制。`115.sync-delete` 记录配置跳过原因、来源范围数量、匹配深度、目标类型和接口确认，异常只记录类型、不写路径正文或凭据。

115 同步删除开关已开但监听目录为空（包括仅含空来源 ID 或空目录地址的记录）属于配置不完整。`Cloud115SyncDeleteService` 在路径匹配和网盘读取前以 `no_directories_configured` 记录告警并抛出配置提示，使媒体库删除链保留 WebDAV、索引、详情缓存与播放记录；设置页显示未就绪状态，选择目录后消失，移除最后一个目录后恢复。开关关闭或资源不在已配置范围内时仍保持原有普通删除行为；不自动推断监听目录、扩大删除范围或将文件提升为父目录删除。两网盘监听配置保持独立。

115 与夸克的保存反馈分为两个公共模块：领域层 `cloud_save_feedback.dart` 定义 `CloudSaveDrive / CloudSaveProgress / CloudSaveSummary`，统一网盘名称、保存和名称处理阶段、最终总结及下游失败文案；表现层 `cloud_save_feedback_controller.dart` 通过任务级 session 管理 SnackBar 的替换、关闭、2 分钟兜底和页面生命周期。搜索、收藏共用的 `SearchPage` 以及详情页两种网盘的在线资源更新都接入此控制器，不再各自维护提示队列。新提示同步清除旧进度归属及队列，避免旧任务的 `finally` 关闭新任务提示。等待 STRM 时保留当前进度，不显示短暂的“STRM 触发中”或单独的保存路径；路径只供客户端和工作流传递实际转存、STRM 目标。

两种保存工作流保留各自的网盘接口、任务名、刷新目标及删除规则，只把反馈数据交给公共模块。刷新交给后台 Future，结果只承诺刷新已安排，不承诺 STRM 已生成或索引已完成。后台调度异常分别记录 `115.save / quark.save`，通过独立回调在仍活动的页面提示；若异常早于保存总结到达，先保留，等成功总结显示后排队提示。115 全部重复不触发下游任务，夸克全部重复仍可刷新其直连来源，不触发 STRM。追更由显式再次保存触发，媒体库增量刷新只处理已出现在 WebDAV 的新文件，不轮询分享或主动转存。

`Quark` 媒体源当前走“目录直连”模型：

- 复用 `设置 -> 内容与来源 -> 网盘与转存 -> 夸克云盘` 中保存的全局 `Cookie`
- 通过选择一个夸克目录，把该目录作为本地媒体源根目录
- 可继续选择根目录下的子目录作为分区范围
- 索引、结构推断和在线搜刮配置复用 `WebDAV` 同一套外部存储扫描与 `NasMediaIndexer` 规则，包括本地 sidecar、顶层推断目录和“剧集只按剧名层级搜刮”
- 普通媒体库读取优先使用 NAS 索引；刷新或首次空索引重建通过 `QuarkExternalStorageClient` 递归列目录，再由索引器生成 `MediaItem`。Quark 空库路径可等待重建，不应套用 WebDAV 空库一律后台调度的描述
- 播放地址不提前持久化；详情页只会在真正播放前按需请求一次夸克下载直链

## 8. 详情与元数据

详情页主模型是 `MediaDetailTarget`，它把：

- 展示信息
- 搜索词
- 来源上下文
- 外部 ID
- 播放目标

放在同一个详情上下文中。

详情读取顺序大致是：

1. 使用 seed target
2. 读取本地详情缓存
3. 合并缓存中的缺失字段，并优先保留已缓存的本地资源状态
4. 视情况补全在线元数据
5. 对 `Emby / Quark` 播放目标补全真实播放信息
6. 写回本地详情缓存

对 `WebDAV` 条目，详情页默认优先信任索引阶段产物，不重复做实时在线刮削。

详情页的两个补充点：

- “匹配本地资源”命中 `WebDAV / NAS` 后，资源侧字段会优先使用匹配结果，当前详情页已有的在线元数据只做补充，不再反向覆盖匹配到的本地资源信息
- 豆瓣等在线 seed target 如果已经命中过本地资源，后续再次进入详情页时会继续优先采用缓存里的资源状态、来源和播放信息，而不是回退到 seed target 自带的“无 / 豆瓣”
- 如果恢复到的缓存命中项是某个单集或具体文件，详情页仍会保留原来的剧集结构目标，继续显示季/集浏览区，而不是把整页退化成单文件详情
- 如果本地详情缓存或手动索引结果里已经有更新后的标题，详情页会优先显示这份标题；媒体库与首页也会沿着同一条缓存合并链路复用它
- `LocalStorageCacheRepository` 的 `season / episode` 内容查找键同时包含季号与集号（季条目仅季号），优先读取详情字段，缺失时读取播放目标字段；不完整的季集身份仅生成 `sourceId + itemId` 资源键。缓存读写均校验条目类型及季集身份，记录 ID 冲突时新建独立记录，不继承错误候选，也不删除其他条目的缓存。同集多版本选择与整剧入口的显式结构恢复仍保持原流程。
- 详情页与人物作品页已经收口到 `RetainedAsyncController`；页面 inactive、切回前台或播放期间页面让路时，会优先保留最近一次已解析结果
- 详情页在 inactive 时会取消当前匹配 / 刷新会话，但不会再无条件失效成功缓存；重新回到页面时优先复用已有详情结果
- 详情页失活时解除相应 provider 监听并取消当前工作，但已展示的剧集、剧照不因 `TickerMode` 关闭而卸载；播放器返回后复用季选择、滚动和已加载结果。剧照预览支持双指缩放、双击切换 2.5 倍缩放、放大后拖动，以及未放大时向下滑动关闭和点击图片外空白关闭；不放置右上角缩放/关闭按钮，双指缩放围绕实际两指中心，手机、桌面和 TV 通过系统返回键退出，TV 由不可见焦点宿主承接返回键，返回或确定只关闭预览并回到详情页，失败重试按钮仍可导航。剧照组件在路由销毁或目标身份变化时只驱逐自身源图、缩略图和预览尺寸的内存缓存，不调用全局 `ImageCache.clear()`，因此不会误伤海报、头像或 Hero 背景
- 剧照预览的关闭键在按下时记录物理键，消费重复事件，到匹配的松开事件才关闭路由，避免焦点提前返回详情页后将未消费的 BACK 松开重派发成系统返回。系统返回仍由预览 `PopScope` 处理；手势与按键共用单次关闭入口，仅关闭当前预览路由。
- 网络图片在展示层支持候选图回退，主图 `404` 或解码失败时会自动尝试下一张候选 artwork；全部候选失败会清空当前失败 Future 并有限重试，持久化图片解码失败时同时淘汰对应磁盘条目
- 详情页已经移除内联字幕搜索与外挂字幕选择；在线字幕搜索只保留在播放器页与独立字幕搜索页，仍按 `设置 -> 播放 -> 字幕` 里的配置使用 `ASSRT API / OpenSubtitles / SubDL`
- 详情页不再把字幕候选或选中项写入详情缓存，也不会在进入播放器前向播放目标注入外挂字幕；字幕选择改由播放器页会话独立持有
- 详情页资源信息区可直接切换播放器；这个入口最终会调用 `SettingsController.setPlaybackEngine(...)`，因此会和设置页里的全局默认播放器保持同一份持久化值

当前详情页与元数据链路还额外承担这些能力：

- 顶部 Hero 优先使用背景图，不再重复放置海报；文字覆盖区域单独加阴影，未覆盖区域保持原图
- 非 TV 使用标准详情 Hero；TV 固定使用精简详情 Hero
- `TMDB` 已接入 `poster / backdrop / still / profile / logo` 等图片字段，并把 `TMDB x.x` 写入统一评分标签链路；详情不主动请求 IMDb。NAS 索引仅在配置 `imdbRatingMatchEnabled=true` 时调用独立 IMDb 客户端，默认关闭；上游 `WMDB / TMDB` 与既有索引的 IMDb 标签继续展示和保存
- `MediaItem.ratingCount` 与 `MediaDetailTarget.ratingCount` 共用豆瓣评分人数。详情 Hero 使用 `buildRatingCountLabel` 显示 `☆31.6万`；`douban_rating_stats_service` 获取 `rating.count` 后，`MediaRepository.updateRatingCount` 会把人数写回 Emby / 飞牛分片缓存或 NAS / WebDAV / Quark 索引。索引建条目、系列 / 季 / 特殊集分组和增量刷新均保留该字段，因此媒体库入口再次打开详情时可直接恢复人数。
- 人数不再作为独立预取条件：resolver 在缺豆瓣评分、豆瓣 ID 新匹配或强制刷新时同步获取评分与人数。`DoubanEntry` 保留列表响应的 `rating.count`；首页（含轮播）和媒体库批量缓存合并、可见页变化检测、资源匹配、剧集变体及清理失效资源关联时均保留人数；仅人数变化也归入 `LocalStorageDetailCacheChangedField.ratings`，沿评分缓存订阅更新入口。人数随当前详情缓存保存。
- 详情页评分标签会按来源归一去重，并固定按 `豆瓣 -> IMDb -> TMDB` 排列；`豆瓣 / IMDb / TMDB` 各最多保留一条，避免 seed target、详情缓存和后续在线补全合并后出现重复评分标签或位置互换；评分人数不占用标签条目
- 人物头像统一来自 `TMDB profile`，详情页公司 Logo 来自 `TMDB production_companies.logo_path`，不再把 `networks` 混作公司展示
- 详情页公司 Logo 位于资源信息之后的页面底部，使用带柔和高对比度背景卡片的单行横向 `PlatformRail`，超出可视区域时可左右滑动，TV 端每个 Logo 都有独立焦点目标并带轻微放大提示，不再通过多行 `Wrap` 换行；点击 Logo 会直接使用详情数据里的 `TMDB` 公司 ID，并打开与人物作品页共用的电影 / 剧集作品浏览页
- `MediaItem` 只持久化演职员姓名，`MediaDetailTarget.resolved*Profiles` 负责无头像时的姓名占位；占位不写入真实 profile 列表。详情缓存、资源匹配和 TMDB 结果通过 `mergeMediaPersonProfiles(...)` 合并，同名条目优先保留已有顺序并用非空头像升级。NAS 索引已有完整文字元数据但没有人物图时，只允许一次面向 `TMDB profile` 的详情补全，不重新请求 WMDB
- 演职员头像可跳转到人物关联影片页，公司 Logo 可跳转到同一作品浏览页的公司模式，`TV` 焦点动作只包裹圆形头像并采用圆形焦点框与 `1.06` 缩放，姓名在头像下方但不参与焦点区域。作品列表继续复用首页同款海报卡片；卡片右上角会优先显示题材/类型标签，左下角继续显示可用评分标签
- 剧集详情里的单集卡片已拆成两个入口：图片区继续走播放，图片下方的简介区进入单集详情
- 详情模块标题与下方正文读取 `AppContentSpacing.sectionHeading = 10dp`、模块自身底部读取 `section = 8dp`：`DetailBlock`、`DetailOverviewSection` 与已匹配资源时无标题剧集分支一致，覆盖简介、剧集、剧照、演职员、资源信息和公司。剧集横排自身底部保留 10dp 焦点空间，因此卡片边界到后续区域为 18dp；卡片简介内边距不参与此次模块间距调整。
- 资源信息的 `FactRow` 与豆瓣链接行统一让标签、普通值和可选值使用 1.5 行高；链接按钮保持 30dp 点击高度，但内容顶部对齐，因此来源、链接、时长和状态等单行项的字形起点一致。长地址等多行值仍与标签顶部对齐。
- 详情“演职员”的“导演 / 演员”使用 `DetailGroupLabel`（16、`w700`、次级灰色、标题行高 1.3），与 18 的 `DetailBlock` 区域标题和 14 的人物姓名形成三级结构；资源信息里的“本地资源 / 播放器 / 播放版本”等字段标签继续使用 12 的 `InfoLabel`。
- 简介由 `core/utils/metadata_text.dart` 使用 HTML DOM 解析成纯正文与去重来源 URI，原始 `overview` 仍在 WMDB/TMDB 结果、MediaItem 和详情缓存中保存；显示清理不写回数据。正文保留段落，链接及其附带换行被移除；标签删除仅接受明确分隔的已知来源标签或短地址标签，不向前吞掉正文。安全来源限制为无用户凭据的有效 HTTP/HTTPS 地址。
- `DetailOverviewSection` 独立管理六行折叠、展开/收起、空简介及“更多 → 视频来源”；复用详情选择弹窗与 TV 焦点组件，来源打开失败可恢复，关闭弹窗后回到更多按钮。剧集卡片使用三行摘要并保留现有集数/时长/文件名兜底，不增加卡片内外链按钮。`DetailEpisodeBrowser` 横排高度由 292dp 宽的 16:9 图片、随文字缩放的三行摘要、顶部 8dp／底部 14dp 内边距及顶部 14dp／底部 10dp 滚动留白组成，卡片保持等高，不额外预留第四行空间。`DetailHeroSection` 内容底部偏移统一为 8dp，缩小播放操作到后续内容的空白；此偏移与横排留白不按 TV／普通端分支，不增加设置项。首页 Hero 和元数据预览也在展示时清理简介。缓存没有来源 URL 时只能通过重新读取元数据恢复来源。
- `TV` 短简介保留正文焦点；展开控件固定在正文上方，长正文可获得独立焦点并上下滚动，到达边界后交回页面方向寻焦。正文确认键可收起并将焦点送回展开控件，避免长段落推动控件离屏后难以返回。
- NAS / WebDAV 的系列与季层级会随来源索引缓存一次构建，并按分区直接查找；切季和重新进入详情页不再重复扫描、分组整个来源索引
- 单集横排继续使用惰性列表；`TV` 单集图纳入全局四路图片加载门，卡片离开视口或页面失活时会取消尚未取得 permit 的任务；gate 直接追踪活动 permit，并为每个 permit 设置 `8s` 自恢复租约，避免隐藏组件漏释放后让全局图片队列永久停住
- `AppNetworkImage` 在 `TickerMode` 关闭时同步释放未完成的 TV permit 并取消排队，隐藏期间不重新申请；已完成的图片保留原包装树。SVG、raster provider 和 permit 的 `FutureBuilder` 分别以当前 Future / request 为 key，不把旧候选的 error / data 带进下一候选的 waiting 状态。候选切换的帧末回调主动请求更新帧，成功后普通父级重建不重置图片。
- `TV` 详情页额外拆成了明确的方向焦点带：
  - `Hero` 主操作按钮左右只在顶部操作区切换
  - 剧集浏览区拆成“季标签一排 / 卡片上半播放区一排 / 卡片下半简介区一排”
  - 剧集卡左右切换默认优先停留在上半播放区，只有主动按下才进入下半简介区
- 单集详情仍然复用统一的 `MediaDetailTarget` 详情链路，但会继承剧集级搜索词与外部 ID 上下文，保证该集的本地资源匹配和在线补全不会只依赖单集标题
- `TV` 模式下详情页主操作默认优先聚焦“继续播放 / 立即播放”或“搜索资源”，并记住人物、剧集等横向列表的上次焦点
- 桌面端剧集横排与剧照横排会复用统一的左右翻页按钮，避免鼠标只能手动拖动或滚轮横移
- 详情页命中多个来源时，资源信息区只按 `sourceKind + sourceId` 去重并展示“本地资源”；当前来源存在多个可播放候选时，Hero 下方才展示“播放版本”。两级选择最终映射回同一份完整候选列表，覆盖 `movie` 和单集等可播放叶子项，`series / season` 仍保留聚合态浏览

`WebDAV` 详情页还提供 `建立/管理索引` 页面，用于：

- 修改搜索词
- 修改年份
- 切换是否按剧集匹配
- 手动搜索 `WMDB / TMDB`
- 直接写回本地索引和详情缓存
- 手动应用命中结果时会强制覆盖本地已存在的标题、简介、图片、人物、公司 Logo 和外部 ID，不再只补空字段
- `TV` 模式下进入信息管理页后，会在路由首帧结束时主动请求首屏“自动更新”按钮焦点，不依赖离屏搜索按钮的 autofocus
- 详情页“手动更新信息”同样会直接重新搜索，并把命中的在线结果覆盖到当前详情缓存
- 人物 / 公司关联影片页支持按年份新到旧 / 旧到新排序，也支持按类别筛选，并统一提供上一页 / 下一页。公司作品页通过 `TMDB` 电影 / 剧集 Discover 的同一页码读取数据，以 `total_pages` 驱动分页，排序切换会回到第 1 页并更新服务端 `sort_by`；导演 / 演员作品页仍使用一次人物作品响应，在本地排序筛选后按每页 40 条切页。`TV` 分页与作品网格使用显式焦点边界，上方分页向下进入首张卡片，下方分页向上回到末张卡片

详情页本地资源匹配当前还有这些约束：

- 自动匹配由 `设置 -> 元数据 -> 元数据匹配 -> 自动匹配本地资源` 控制，默认关闭
- 当自动匹配关闭时，详情页只保留“重新匹配资源”这一条手动触发路径
- `设置 -> 内容与来源 -> 媒体源管理 -> 详情页匹配来源` 会直接限制详情页本地资源匹配的实际扫描范围；只会扫描被选中的已启用 `Emby / 飞牛影视 / WebDAV / Quark` 来源
- 如果“匹配来源”未单独勾选，则默认使用全部已启用来源；如果保存的来源 ID 已失效，则自动回退到全部已启用来源
- 如果详情页 seed target 本身来自媒体库卡片或指定来源模块，并已经带了 `sourceId / sourceKind / itemId / sectionId` 这类来源上下文，匹配链路会先优先处理这个来源，而不是把所有来源完全等价并行处理
- 对非 `series` 聚合页，如果入口 target 本身已经是该来源下的已解析资源，候选列表会先直接补入这条入口资源；手动重新匹配时也会跳过对这个入口来源的重复扫描
- `series` 入口具备非空 `sourceId / itemId` 时，`resolvePreferredEntryLibraryChoice` 也会补入原始剧集 target；缓存恢复与匹配的分批结果共用该规则，旧 NAS 候选不能覆盖飞牛入口的首屏或季集请求。补入时保留入口结构身份，不从其他来源拼接播放目标；`skipPreferredSourceSearch` 仍只适用于非剧集入口，剧集匹配继续查询优先来源。无来源发现页仍恢复缓存选择，进入后手动切换来源不受影响。
- 如果入口来源当前还没有命中项，但 seed target 带了明确 `sourceId` 或分区上下文，`Emby` 会先优先扫描同来源分区，`WebDAV / Quark` 也会先优先扫描同来源，再回退到其他已启用来源
- 手动匹配按多个搜索源并发执行，先命中的结果会立刻显示，但不会取消其余源的搜索
- 如果一次手动匹配命中多个本地资源，详情缓存会连同候选列表和当前选中项一起保存；后续重新进入详情页时会直接恢复这组候选
- 候选先按来源拆成“本地资源”选择；只有当前来源内存在多个可直接播放的叶子资源时，才额外展示“播放版本”，不会再把跨来源候选混入版本列表
- 如果候选本来就全部来自同一个入口优先来源，则仍保留原有选中项，不会仅因为“入口来源优先”而把选中项强行重置到第一个
- 外部 ID 强匹配不要求 `IMDb / TMDB / 豆瓣 / TVDB / Wikidata` 同时命中；任一 ID 命中即可成立，命中原因会按实际命中的 ID 组合展示
- 删除某个已匹配本地资源时，详情缓存只会精确剔除当前资源对应的命中关系；如果还有其他候选，则继续保留并回退到剩余候选
- 如果删除的是当前唯一命中的本地资源，则只清空这条资源状态、播放目标和来源上下文，影片自己的在线元数据与详情缓存仍然保留
- 退出详情页时，当前页的本地资源匹配会话会立即取消；未启动的后续队列不会再继续执行，已经返回的结果也不会再影响已离开的页面

## 9. 搜索与入库联动

普通端与 TV 端搜索页均不再提供切换到收藏视图的入口；独立收藏路由继续复用 `SearchPage(favoritesOnly: true)`，搜索结果条目的收藏与取消收藏操作保持不变。

收藏海报补全由 `SearchFavoriteMetadataService` 负责：新增收藏保存匹配海报，旧收藏只补图片字段，不修改标题、文件夹名或资源标识；优先复用详情入口海报及其鉴权头，再调用既有元数据匹配器，已有 TMDB ID 与匹配结果冲突时不采用新图。`SearchPage` 在收藏视图激活并读完本地记录后后台串行补图，每次激活每个条目最多尝试一次，离开页面停止后续任务并忽略过期结果。`SearchPreferencesRepository` 串行执行收藏写入，补图时重新读取当前记录并按收藏 key 合并，避免恢复已取消的收藏或覆盖其他收藏字段。已有海报直接复用，失败不阻塞页面，重新进入可重试。

搜索、收藏和媒体库一级页面不渲染返回工具栏，也不保留工具栏高度的顶部占位；`SearchPage` 仅在 `showBackButton: true` 时显示返回工具栏，供 `/detail-search` 二级路由使用。媒体库分区等二级页面的返回入口保持不变。

搜索页会并发组合这些来源：

- 本地媒体源
- 在线搜索 provider

当前在线 provider：

- `PanSou`
- `PanSou` 认证优先级为完整用户名/密码登录取得新 JWT，其次才是手动 Token；这样同时保存两类认证信息时不会被过期 Token 抢先拦截，账号信息不完整时仍保留纯 Token 模式
- `PanSou` 使用独立传输客户端承载聚合搜索，搜索响应头最多等待 `60s`，登录与健康检查仍限制为 `20s`；响应正文遇到非法 UTF-8 字节时会替换坏字符并继续解析其余 JSON。搜索开始、完成和失败会记录 provider、主机、耗时与结果数量，但不记录搜索词正文
- `CloudSaver`

搜索结果会在 provider 侧和页面侧继续做：

- 同分享去重：`searchResultDeduplicationKey` 仅用于搜索结果聚合、provider 过滤与验链身份；标准已知 host 的 `/s/分享码` 按网盘类型和大小写敏感分享码合并，覆盖 115 / 夸克 / 阿里 / 百度 / UC / 123 / 迅雷。已知域名别名、协议、推广参数和提取码不影响分享身份；未知 host、非标准路径和明确目录 / 文件作用域回退 URL 规则，目录路由 fragment 保留。`normalizeSearchResourceUrl` 和收藏持久化键保持不变。
- `mergeSearchResultShareCredentials` 保留首条标题、来源与 ID，只补齐缺失接收码（同时补 URL 密码参数供打开 / 保存使用），不覆盖非空冲突密码。PanSou / CloudSaver 解析保留同 URL 不同密码的候选，provider 规则过滤后按分享键合并；跨来源用 `_SearchCandidate` 维护同分享的最新凭据和验证状态，同批先合并再验证。迟到凭据补齐时，在途旧验证结束后或已结束状态下重新验证，更新过滤计数并仅保留一条结果；不以标题或文件哈希判断同内容，不删除收藏或网盘文件。
- `prepareSearchResultShareCredentials` 在结果进入搜索聚合前把单独返回的接收码补到已识别链接的密码参数；夸克以 URL 的 `pwd` 优先，115 以 `password` 优先，已有非空参数不覆盖。使去重保留的条目能通过既有验链、打开及保存入口使用该密码；不改变收藏键计算规则。
- 网盘类型过滤
- Repository 类型过滤与页面筛选统一使用 `resolveSearchCloudTypeCode`：链接识别优先，无法识别时回退 `SearchResult.cloudType`，避免接口已声明类型的未知域名链接被误排除；不对链接有效性作额外保证。
- `detectSearchCloudTypeFromUrl` 将 `115cdn.com` / `www.115cdn.com` 与既有 `115.com`、`anxia.com` 一起归类为 115，补齐与 `Cloud115ShareLink.parse` 的域名兼容；新增 CDN 域名按 host 匹配，不因其他站点路径或查询参数含该域名而误判。类型过滤、筛选、验链和保存入口均复用该识别。
- `search.filters` 在每次在线服务返回后（含零结果）记录解析后与过滤后各类型数量、有效类型配置、强匹配开关、标题长度上限及按原因 / 类型聚合的排除计数；排除计数按现有过滤顺序归属首个命中规则。`search.results` 在搜索完成及页面类型切换时记录聚合数量、各类型数量和当前可见数量。共用 `countSearchResultsByCloudType`，未知类型归为 `unknown`，本地资源归为 `local`；不写入搜索词正文、标题、链接、提取码、过滤词正文或认证信息，便于区分接口未提供、provider 过滤、页面验证和显示筛选。
- 页面网盘类型备选取当前选中且可见的在线 provider 的 `allowedCloudTypes` 并集，再与 `_results` 中非本地资源的已识别类型取交集。不引入隐藏或未选来源的类型，沿用设置空列表表示允许全部类型的约定；选中类型消失时取消类型筛选。
- 网盘类型栏仅在非收藏视图且存在上述可选类型时挂载。选项来自完整聚合结果而非 `_displayedResults`，切换类型不会隐藏其他已有结果的类型。待验证或已判定无效的夸克 / 115 结果不进入 `_results`，不能贡献类型选项；无法验证但保留的结果仍可贡献选项，不视为已验证有效。
- 搜索页在来源选项下提供可取消的网盘类型单选，普通端与 TV 端复用 `StarflowChipButton`，不渲染“全部”选项。默认 `_selectedCloudType == null` 不限制类型，再次点击已选类型恢复该状态。页面保留完整聚合结果，仅展示时按链接识别类型（缺失时回退 `cloudType`）筛选，切换不请求网络，后续批次沿用当前选择；状态不持久化，不影响收藏页与 provider 配置。结果计数反映当前可见条数，原有过滤计数仍表示去重及有效性等处理排除的条数。
- 过滤词
- `search_result_resolution.dart` 独立识别在线结果声明的清晰度，不改写 `SearchResult.quality`（现有在线 provider 用该字段展示网盘名）或收藏数据。优先读取标题与 quality 中的明确标记，无标记时回退简介并排除来源、发布时间和 URL；`2160P / UHD` 合并为 4K，`1440P / QHD` 合并为 2K，`1080I / FHD` 合并为 1080P，480 / 576 的 P、I 标记归标清。合集明确列出多个档位时可命中其中任一档；“高清 / 蓝光 / 原画 / HDR”不推断具体分辨率，归入未标注。
- 页面清晰度备选仅来自完整 `_results` 中的在线条目，排除本地、待验证及无效结果，不随网盘筛选收缩。与网盘类型取交集展示；交集为空保留筛选控件并提示无结果。复用 `StarflowChipButton` 支持手机、桌面与 TV，再次选择取消、不持久化、不影响收藏；新搜索清空结果或所选档位消失时自动取消，后续批次继续应用有效选择。按不可变结果列表缓存识别及组合筛选，不探测视频或请求接口；`search.results` 仅增加所选清晰度枚举，不记录资源正文。
- 强匹配
- 标题长度限制
- 夸克（已配置 Cookie）与 115 搜索结果进入共用的 `_ShareLinkValidationJob` 页面队列，按 `taskMaxConcurrency` 限制总并发，复用去重、请求会话隔离和页面失活取消机制；本地媒体不验链。`ShareLinkValidationResult` 定义 valid / invalid / unavailable，原 Quark 名称保留为类型别名以兼容调用端。无需验证的结果先提交，验链结果逐条补入；明确取消、过期、不存在、接收码错误、确认内容为空则排除，其他失败保留并标记暂未验证。
- `Cloud115SaveClient.validateShareLink` 仅 GET 固定 `webapi.115.com/share/snap` 的根目录第一页（limit=1），不跟随重定向，整次 8 秒超时，使用链接密码优先于单独接收码。Cookie 缺失不请求；认证失败、HTTP 错误、限流、格式异常或不完整目录不视为永久无效，只有明确分享错误或 count=0 且 list 为空才判定无效。日志 `search.115-validation` 记录固定归一化原因，不写链接、密码或 Cookie。独立收藏页不启动批量验链，验证与转存 / 删除互不调用。
- 普通端与 `TV` 端共用本地最近搜索词和搜索来源记忆；`SearchPage` 在非收藏视图且历史非空时展示最多 8 条最近搜索词，使用固定高度的横向 `SingleChildScrollView` 和 `Row` 保持单行，支持触摸滑动、鼠标拖动和 TV 默认焦点遍历滚动。单个词条限制在视口宽度内，超长文本省略但保留完整搜索词；点击或遥控器确认复用 `_runRecentQuery` 发起搜索并将该词移到历史首位。独立收藏页隐藏该区域，存储键与已有历史数据保持兼容
- 搜索页顶部来源筛选、最近搜索和媒体库筛选统一复用 `StarflowChipButton` 这一类通用按钮规格，普通端横向列表容器也与统一按钮高度保持一致，避免单页样式漂移或裁切
- `SearchFilterRow` 统一搜索来源、网盘类型、清晰度的标签列与选项间距；可用宽度小于 600 的非 TV 页面每组横向滚动，超过 1.5 倍字体时改为标签在上，宽屏 / TV 使用换行选项。选项外层保留派生稳定 key，异步新增类型不会销毁原持焦按钮。结果计数旁的清除图标只重置两个结果筛选条件，保留来源、最近搜索和完整结果，不请求网络；始终保留按钮位置避免清除时 TV 焦点丢失。
- 空关键词会直接短路，不再启动整轮 provider 搜索
- 最近搜索区域使用 `Row + Expanded`：左侧固定标题，右侧保持既有固定高度横向滚动和 TV 焦点遍历，长关键词按右侧实际可用宽度省略。标题与词条垂直居中，包含大字体模式；不修改历史存储、数量上限或重新搜索行为。
- 多来源结果会先在页内聚合，再通过短定时批量提交 UI；不会再每个来源一返回就全量排序并触发一次大 `setState`

搜索来源分成“可见 tab”和“当前选择”两层：

- `设置 -> 内容与来源 -> 搜索服务管理 -> 搜索来源` 只决定搜索页展示哪些本地媒体源和在线 provider tab
- 如果该设置未单独勾选任何来源，则搜索页展示全部已启用来源 tab
- 搜索页来源 tab 支持多选并保存在本地；每次实际请求以搜索页当前选中的 tab 为准，“全部”会并发搜索所有当前可见来源
- 设置变更后会保留仍然可见的已选 tab；如果已保存的 tab 全部失效或被隐藏，则自动回退到“全部”
- 从详情页进入搜索时，会先恢复搜索页保存的 tab 选择，再使用详情片名自动发起搜索，避免初始化竞态误用默认“全部”
- 从详情页进入搜索时，会复用同一个 `SearchPage`，但通过 `/detail-search` 路由额外补上返回工具栏，并维持无转场进入，减少 TV / 低性能设备上的切页成本

搜索后的联动链路是：

1. 按资源类型保存到夸克或 115
2. 工作流通过公共 `CloudSaveProgress` 报告阶段，页面 session 显示对应网盘的“保存中...”及可选的“已保存 N 个，名称修改中...”。转存落稳后先执行可选名称修正，再按网盘与转存里的“STRM 触发等待时间”延迟触发 `SmartStrm` Webhook，三个依赖真实路径的阶段保持串行；之后直接显示 `CloudSaveSummary` 生成的最终总结，不额外显示 STRM / 刷新中间状态或完整保存路径。
   公共 UI 控制器按任务跟踪进度，成功、失败、`finally` 和页面销毁都会主动关闭，并以 2 分钟时长兜底，避免页面离开或请求异常时残留。
3. 按“索引刷新等待时间”延迟一次原有媒体源增量刷新，不阻塞保存结果返回。Quark 直连和 Emby 刷新不改变；不调用 OpenList API
4. 首页和媒体库读取到新的索引或缓存

同步删除会优先按当前 `sourceId`，其次按唯一来源名对齐监听目录；媒体源域名或挂载前缀变化时，设置协调器用稳定相对目录边界（例如 `strm/quark`）一次性改写到当前根并持久化，不把旧地址继续留作运行期来源。普通 WebDAV 删除仍要求远端成功；仅当路径明确命中夸克同步目录且服务返回 `403 / 405` 时，允许改由夸克源目录删除，夸克删除成功后才清理本地索引。

自动增量刷新的目标媒体源在网盘与转存里单独选择，默认会选中全部当前可刷新的来源。

网盘与转存页里的夸克链路当前还提供目录运维能力：

- 可直接浏览当前默认保存目录和子目录
- 可单独删除文件或文件夹
- 可一键清空当前目录
- 删除动作当前走夸克回收站语义，不做应用侧永久粉碎
- 可选开启“同步删除夸克目录”，让命中已选 `WebDAV` 监听目录的删除动作联动删除当前夸克保存目录里的对应影片或剧集目录

## 10. 播放链路

索引版本转为播放目标时，`PlaybackVariantResolver` 优先保留非空 `playbackItemId`，缺失时使用该候选自己的 `MediaItem.id`，不能复用上一个文件的 ID；候选缺失的类型及季集号由当前同作品／同集上下文补齐。此规则确保切换后设置入口仍可用，下一次版本查询仍定位到新文件，且经过原生 JSON 桥接或 STRM 地址解析后身份不丢失。

`PlaybackVariantResolver` 按当前 source/item 身份复用媒体服务器 `fetchPlaybackVariants` 或 NAS 索引的电影／单集版本分组，不跨来源按标题猜测，不为列出版本解析 STRM。MPV `PlayerVariantPickerDialog` 与 Android `browseNativePlaybackVersions` 共用版本标签、去重和当前项判断；飞牛版本候选清除旧文件音轨 GUID、画质和转码会话。MPV 与 Android 原生复用既有画质切换的解析、串行释放、重开和失败回退事务，换文件时保留时间、倍速、暂停状态并更新播放记忆身份和队列当前项，不复用旧文件的临时轨道选择。Android 入口暂由 `NativeFntvController` 的共享重开路径承接，非飞牛版本不执行飞牛请求重写。iOS 系统 AVPlayer 控制栏与外部播放器没有此入口。

2026-09-20 流畅度修复边界：iOS 与 Android 原生容器均接收完整延迟解析剧集队列，iOS 只在切集时经 `starflow/native_playback_resolver` 解析目标，30 秒截止及会话代次拒绝迟到提交。iOS 宿主更换请求身份前完成旧实例字幕/进度快照与清理，再异步读取新集记忆。`NativePlaybackMemoryStore` 在两端拥有串行写入队列，合并待写周期进度而保留强制最终快照；iOS 缓存最大时间戳及复用日期解析器，Android 高频跳过检查读取发布快照。写入完成通过 `nativePlaybackMemoryChanged` 使 Flutter 历史缓存失效，不能把主线程提交完成等同磁盘同步。

MPV 媒体就绪与非必要字幕准备分离，`PlaybackTrackGuard` 保持播放器代次和手动选轨优先；`PlaybackSeekCoalescer` 合并 TV 长按输入，稳定的播放页 key 不因 ready 状态销毁视频子树。AVPlayer StartupGate 只允许一个 preroll，ready 时间轴区分点播/直播，不以 `.m3u8` 判断直播。iOS 呈现回调和 `playing` 不是实际像素首帧。处理状态与限制见 [播放器审查](reviews/player-smoothness-review-2026-09-20.md)。

同日审查收尾：硬恢复仅释放旧 FNTV 会话，页面级 `FntvSessionOwner.close` 限于最终退出/销毁。`PlaybackRecoveryIntent` 在暂停、拖动、后台和退出时使延迟恢复失效；原生 iOS 以用户命令和 episode intent 拒绝迟到切集。手动飞牛字幕下载也使用 `PlaybackTrackGuard`，嵌套保护保留父任务有效性，过期结果不能挂载或回写目标/偏好。策略与设备证据分列于 [审查收尾记录](reviews/review-closure-2026-09-20.md)。

播放器页基于 `media_kit`，当前是“三种播放内核”分支：

- 内置播放器负责应用内播放、字幕增强、续播和跳过逻辑
- App 内原生播放器负责在 Android / iOS 上以原生容器页承载播放，尽量减少 Flutter 合成层干扰
- 系统播放器负责把播放地址交给平台默认视频应用
- Android `ExoPlayer（原生）` 的音频输出由 `NativePlaybackAudioPolicy` 和 `NativePlaybackRenderersFactory` 决定；FFmpeg 扩展始终作为备选注册，按实际音轨 MIME 决定 PCM 与 renderer 路由。扩展包含 `ac3 / eac3 / mlp / truehd / dca / mp1 / mp2 / mp3`，不是完整 FFmpeg。TV 自动模式对 E-AC-3/JOC 使用兼容输出，视频策略不随音频回退改变

主流程大致是：

1. 进入播放器页
2. `PlaybackStartupCoordinator` 解析播放目标，读取本地续播和按剧跳过偏好，并得到路由动作
3. 按 `Emby / 飞牛 / WebDAV / Quark` 来源解析真实播放地址和请求头；飞牛默认重新协商，已解析的会话切换目标可显式跳过重复申请
4. `PlaybackStartupExecutor` 按用户选择的播放器内核执行系统播放器、原生容器或内置 MPV 分支
5. 内置播放进入等待态，不做旧式独立启动测速；敏感凭据安全 relay 先验证有界媒体前缀，其余路径直接打开。SmartStrm 轻量格式探测只服务原生 Exo 分支
6. 调用内置 `MPV` 打开链并应用启动期调优
7. MPV 临时网络失败在同一启动期限内最多创建 `3` 次播放器（包含首次）；永久与未知错误不无条件重试
8. 超过配置的最大打开超时时间则终止

当前播放页已落地的能力包括：

- 播放速度切换
- 音轨切换
- 字幕轨切换
- 字幕偏移
- 外部字幕加载
- 在线字幕搜索入口（手动触发）
- 播放解码模式切换
  - `自动`
  - `硬解优先`
  - `软解优先`
- Android `PiP`
- Android 后台播放状态同步
- `TV` 播放页不再常驻显示右上角遥控器提示文案，菜单键仍可直接打开播放设置
- iOS 后台音频播放会话，`AppDelegate`、内嵌播放系统会话和原生 `AVPlayer` 容器共用 `StarflowAudioSession` 配置入口；helper 按调用方记录持有者，只有最后一个持有者释放时才停用共享 `AVAudioSession`，配置失败会写入结构化 native 日志
- `TV` / 定制系统环境下，如果外部字幕选择器或其他外部打开能力不可用，页面会优先提示失败而不是直接崩溃
- Android `TV` 从原生播放器拉起独立字幕搜索页时，会把当前 `query / title / input` 一并透传给 Flutter 路由，避免字幕搜索页空查询打开；页面只预填，不会自动发起搜索
- 播放设置里的字幕默认项已收拢到独立二级页，和播放中临时字幕操作分开
- 全局自动字幕先读取 `PlaybackDefaultSubtitle`：`双字幕 / 简体中文 / 繁体中文 / 英语 / 日语 / 系统语言`。双字幕再分别读取 `playbackDualSubtitlePrimaryLanguage / playbackDualSubtitleSecondaryLanguage`，两项都支持简体、繁体、英语、日语和系统语言，默认简体中文 + 英语；两条轨道必须不同。指定语言缺失时回退系统语言，再按 Forced > 片源默认收尾；未知字段也解析成系统语言。明确选择“默认关闭”时跳过自动选轨。MPV 与 Android Media3 支持默认双字幕；iOS AVPlayer 对双字幕按系统语言处理
- 字幕语言识别统一组合轨道 language 与 label，并规范化 ISO/三字码/发布组常用简写：简体覆盖 `zh-cn / zh-hans / chs / chn / chi / zho / cn / sc / 简中`，繁体覆盖 `zh-tw / zh-hant / cht / tc / big5 / 繁中`，英语覆盖 `en / eng / English / 英字`，日语覆盖 `ja / jp / jpn / Japanese / 日字`。MPV、Android Media3 和 iOS AVPlayer 保持同一语义
- 播放记忆的 `subtitlePreferences` 按 `seriesKey` 持有剧集专属选择指纹：用户在某部剧中手动选择内封字幕、关闭字幕或双字幕后，只覆盖该剧其他集；不会写入 `AppSettings`，电影和其他剧不读取。切集重建播放器时按规范化语言、标题、编码、默认/强制标记和稳定 ID 降权匹配，匹配不到才回退全局默认。外挂/在线字幕文件不进入剧集指纹，避免把单集时间轴套到另一集
- MPV 与 Android Media3 字幕菜单都暴露“使用全局默认”；该动作删除当前 `seriesKey` 的 `subtitlePreferences` 并立即重新应用 `AppSettings` 的默认状态、默认字幕及双字幕主/副语言。MPV 的底层 `auto` 轨道不再直接展示，避免与全局默认语义混淆
- 非 `TV` 内置播放复用 `media_kit_video` Adaptive Material / MaterialDesktop 控制层，Starflow 提供按钮、主题、留白和设置页适配：
  - 首层只保留返回、播放/暂停、进度、全屏和“更多”；音量、字幕、音轨与其他高级播放项统一收进播放设置弹窗
  - 顶部标题栏、底部控制区和播放设置弹窗都收敛到更官方的 Material 组件组合：`Material + IconButton + Slider + Text + ListTile + TextButton`；手机、桌面和 TV 顶栏都从最左侧返回按钮开始，实时网速紧跟在其右侧
  - `PiP / AirPlay` 入口继续按平台能力显示
- 内置 `MPV` 主动退出时先 detach 当前播放器并立即关闭路由，进度保存、平台会话清理和 `pause -> stop -> dispose` 在退出后继续完成；新播放器初始化前仍会等待 `_playerShutdownQueue` 清空，避免 TV 慢设备被释放流程挡住页面退出，同时防止旧实例与新实例叠音
- 详情缓存对元数据和传输字段使用不同复用边界：同影片/同集的海报、简介、评分仍可通过 TMDB/IMDb/标题键共享；`PlaybackTarget` 的 `streamUrl / headers / subtitle / container / videoCodec / audioCodec / width / height / bitrate / fileSizeBytes` 只有资源身份一致时才能从缓存补齐。资源身份由 `sourceId / sourceKind / itemId / preferredMediaSourceId / actualAddress` 判定，明确冲突时保留新 target 的空传输字段并交给 resolver 重新解析
- 播放器内的主动退出、关闭后台播放、外部清理请求和打开新片源统一收口到同一套 detach/shutdown 流程；后台播放只承接 App 进入后台，不让页面级播放器跨路由存活
- `PlaybackOptionsDialog` 只订阅设置项实际需要的轨道、循环模式和倍速；底部实时“播放信息”卡片及其进度、画面尺寸、播放/缓冲状态和缓冲百分比监听已经删除，避免设置弹窗为只读信息持续重建
- `PlaybackOptionsDialog` 一级只展示常用播放项和一个“更多”入口；主/副字幕布局、后台播放及 MPV 手势/恢复/调优开关由独立二级弹窗承载，修改仍立即写入当前会话快照
- 播放页 presentation 当前已分成：
  - `player_page.dart`：页面壳、字段与顶层 wiring
  - `player_page_platform_session.part.dart`：PiP、后台播放、系统播放会话
  - `player_page_startup_mpv.part.dart`：播放启动、打开重试、`MPV` / ISO / 调优链
  - `player_page_runtime_actions.part.dart`：续播、跳过、字幕、外挂字幕、在线字幕、飞牛画质与轨道切换
  - `player_page_controls.part.dart`：返回、进度、选择器、播放设置、视频 surface
  - `player_playback_options_dialog.dart`、`player_playback_overlays.dart`、`player_playback_dialogs.dart`、`player_tv_playback_widgets.dart`、`player_network_speed_label.dart`：纯展示层组件；旧自定义 `PlayerMpvControlsOverlay` 已删除，非 TV 统一使用 media_kit Adaptive 控制层
- 四类旧 trace helper 和 `DebugTraceOnce` 已删除，普通静默调用不再提前构造参数；错误调用直接使用 `appLogError`。MPV 不再为静默尺寸日志订阅 width/height；缓冲订阅继续用于性能会话、可靠性日志与 UI
- 内置 `MPV` 现已把 `ISO` 打开路径统一纳入同一条执行链：本地路径 / `file://` / UNC 优先尝试 `dvd-device / bluray-device`，远程 `ISO` 则直接回退普通 `Media(...)` 打开，并在回退前清理残留的 `dvd-device / bluray-device / http-header-fields`
- `TV` 分支当前仍保留自定义播放叠层：
  - 电视场景继续走“首层极简 + 二层高级”的 `NoVideoControls + 遥控器快捷键` 模式
  - 内置 `MPV` 首层只保留播放状态、进度、字幕和音轨快捷入口；菜单键 / 下键进入二层播放设置
  - Android 原生容器页首层会隐藏快进快退、外挂字幕、字幕偏移、在线搜字幕等高级按钮，改由二层“更多操作”入口承载
  - 这样可以把控件数量压到最少，并避免在当前 `TV` 分支里维护另一套复杂控制条
- `App 内原生播放器` 额外已接入：
  - 原生控制条与进度条
  - 本地续播记忆
  - Android 在线字幕搜索与挂载；iOS AVPlayer 暂未完成该闭环
  - Android 原生音轨/字幕选择、播放中音频输出切换、外挂字幕加载与外挂字幕偏移
  - Android 原生播放设置弹窗一级提供播放版本（支持的电影／单集）、画质（飞牛）、本剧跳过片头片尾、音轨、字幕和选择剧集；播放速度、音频输出、主字幕大小、主/副字幕位置、副字幕大小、在线查找字幕、加载外部字幕和字幕偏移全部收进列表最下方的“更多”二级弹窗
  - Android TV 原生控制层只让进度条参与遥控器焦点；播放/暂停及右下角字幕、音轨和更多按钮仍保留显示与点击，但不进入方向键焦点链。确定键由原生遥控器处理层直接切换播放状态。`NativePlaybackRemoteController` 无论控制栏是否可见，按下都统一优先打开选集；没有选集才打开播放设置。选集直接叠加在当前画面上，不主动收起或重新显示控制栏。长按重复不重开，已有弹窗和字幕搜索中的下键交还原界面；菜单键、字幕键快捷入口不变
  - Android 原生播放器的主字幕大小可在“更多”里按 `20–78号` 调整，主/副位置和副字幕大小按百分比调整；改完立即重新套用 `NativeSubtitleStylePolicy / NativeDualSubtitleController`，并通过原生播放回调调用 Flutter `SettingsController` 的字幕样式窄保存入口。设置页、MPV 与 ExoPlayer 因而共用同一份全局值，不再保留原生会话临时覆盖
  - Android 原生音轨与字幕轨选择使用单选即应用的轻量弹窗；点选轨道或“关闭”会立即更新 Media3 `TrackSelectionParameters` 并关闭弹窗，不保留额外的确定步骤
- Android `NativePlaybackActivity` 使用 `Theme.AppCompat.NoActionBar` 派生的全屏黑色主题；音轨、字幕轨与音频输出都使用原生单选对话框，选中即应用，不依赖额外确定按钮
  - Exo 设置、选季 / 集数范围、退出确认和播放失败的 `AlertDialog.Builder` 显式使用 `NativePlaybackSettingsDialogTheme`，以静态资源统一近黑底、白色主文字、浅灰值、弱分割线和零窗口 elevation，不改变 Activity 主题。`NativePlaybackEpisodePicker` 的面板背景与主 / 辅文字也直接引用同一组颜色资源，窗口 elevation 为零，保留选集焦点框及当前集高亮。`NativePlaybackSettingsAppearance` 仅在菜单创建时给首个 ` · ` 及其后状态文字添加颜色 span；数值调节标签直接引用同一浅灰资源。不新增布局层级、轮询、动画或模糊，原菜单层级、焦点、回调、窗口位置和数值弹窗不压暗画面的规则不变。顶底控制栏不单独铺设黑色长条，只由 `exo_controls_background` 提供整屏半透明遮罩；视频底色 / 黑边保留纯黑，系统文件选择器与 Toast 配色由系统负责
  - Android 原生字幕由 `NativeSubtitleStylePolicy` 把 Flutter 的 `20–78号` 设置分段映射到 `3.5%–9%` 画面高度，默认 `32号` 对应 Media3 的 `5.33%`；主位置默认 `80%`，副位置默认 `90%`，副字幕默认主字号的 `50%`。`SubtitleView` 默认使用 Canvas、白色中粗字、透明背景与黑色描边，保留 cue 内嵌样式但忽略内嵌字号；检测到系统 `CaptioningManager` 已启用时采用系统样式与字号，同时在双字幕模式保留应用设置的主/副布局
- 播放器页与独立字幕搜索页复用同一个 `OnlineSubtitleRepository`；仓库内部已经收口为 `searchStructured(...)` 一条结构化链路
- `searchStructured(...)` 会基于当前播放目标、详情外部 ID 和本地文件信息组装 `OnlineSubtitleSearchRequest`，优先尝试文件哈希、`IMDb ID / TMDB ID`、季集号、年份和标题
- 结构化源当前支持 `ASSRT API / OpenSubtitles / SubDL`；`ASSRT` Token 来自设置页，未填写时不会访问 API；`OpenSubtitles` API Key 通过 `--dart-define=STARFLOW_OPENSUBTITLES_API_KEY=...` 注入，账号密码来自设置页；`SubDL` API Key 直接来自设置页
- 多字幕源搜索会并行执行；`OpenSubtitles` 登录态会做短时会话缓存，避免同一轮搜索里重复登录
- 结构化搜索只获取元数据；OpenSubtitles 结果保存 `providerFileId`，点选时申请下载链接。手动编辑查询清除旧目标 ID、文件路径与季集条件，页面用 generation 丢弃旧请求和旧下载回调
- `SubtitleValidationPipeline` 是仓库实际使用的下载管线：流式有界下载、后台 ZIP 选集/语言排序、CRC/格式检查、UTF-8 规范化。`subtitle_content_decoder.dart` 提供共享编码、格式与 ZIP 限制；`subtitle_render_policy.dart` 区分 MPV 文本和位图渲染。详细边界见 [字幕链路](subtitles.md)
- 下载写入 `starflow/online_subtitles/download-*`，不做跨请求文件复用；仓库按当前根目录统计和清理缓存，下载时清理超过 7 天的条目。MPV 挂载文本数据，Android `NativePlaybackSubtitleFiles` 持有独立副本，正常退出后清理；不因清理下载缓存删除正在播放的文件
- 播放器页本身不再直接承载全部启动决策；目标解析、路由判定与执行分支已经拆到独立 application 文件，页面层主要负责装配、等待态和内置 `MPV` 运行期行为，便于 controller 级测试和后续替换策略
- 播放器页 presentation 也已进一步拆开：`player_page.dart` 主要保留会话和流程编排，控制叠层、启动等待态、播放设置弹窗与平台会话子树分别沉到 `presentation/widgets` 与 `player_page_*.part.dart`

设置分类当前按能力拆分：

- 设置首页按内容来源、元数据、播放、界面、性能后台、网络和数据维护分类；不再保留 `PerformanceSettingsPage` 中转目录
- `InterfaceSettingsPage` 和 `TaskSchedulingSettingsPage` 分别由“界面效果 / 任务调度”直接打开；自动匹配本地资源归入元数据匹配页，首页单击清理归入界面效果页
- 播放分类下现在是「播放 / 字幕 / MPV」三个同级一级入口，不再保留“播放器与字幕”混合页和“MPV 调优”独立页
- `MediaSourceSettingsPage`、`SearchServiceSettingsPage` 和 `NetworkStorageSettingsPage` 同属内容来源；媒体源页先展示读取来源列表，再展示详情匹配范围。`NetworkStorageSettingsPage` 的用户入口名为“网盘与转存”，按“网盘账号 / 转存后处理”分组，通过原有 section 打开夸克、115、SmartStrm、转存后刷新媒体库四个三级入口；配置字段与保存、同步删除、索引刷新工作流不变。每个网盘页保留自己的任务名、测试、名称修正和同步删除，公共 SmartStrm 页只承载 Webhook 与触发等待时间。
- `playback_settings_page.dart`、`subtitle_settings_page.dart` 与 `mpv_settings_page.dart` 三个同级页面分别承载播放器主偏好、字幕表单和全部 MPV 设置；日志预览组件、元数据测试卡片也分别下沉到 `logging_settings_widgets.part.dart` 与 `metadata_match_settings_widgets.part.dart`
- 媒体源编辑器把 `Emby / 飞牛影视 / WebDAV / Quark` 连接表单下沉到 `media_source_editor_forms.part.dart`，WebDAV 路径统一复用 `WebDavDirectoryPickerPage`，不再维护第二套私有目录浏览器
- 透明磨砂与简化装饰、减少动画与静态导航、静态 Hero 与精简 Hero 分别合并为三个原子更新的界面开关；菜单栏自动隐藏和 Hero 背景继续独立保存
- 非 TV 使用标准详情 Hero 与标准播放界面，可单独设置激进 MPV 调优
- `TV` 固定使用轻量焦点描边、精简详情 Hero 与精简播放界面，并固定关闭自动更新卡片信息；轻量描边通过前景绘制隔离内容重绘，组件显式传入的 focusScale 仍生效，部分 chip 仍有自身阴影。固定项不在 TV 设置页展示开关
- 路由、导航壳和播放器直接消费对应独立设置；不再根据启用项数量推导隐藏的统一性能档位
- 内置 `MPV` 会在启动前按片源、平台与模式做额外调优：
  - 动态选择前向缓冲与回看缓冲
  - 默认开启 `demuxer thread`，并关闭 `interpolation / deband / audio-display`
  - 对远程流按 buffered remote 与 low-latency remote 两类配置不同的 `network-timeout / cache / cache-secs / demuxer` 参数
  - 质量预设保持用户选择，不再按窗口状态、远程流或重片源自动降档
  - 可单独启用 `fast profile`；重片源或高压力场景仍按运行时策略调节
  - `TV` 固定使用精简字幕与控制叠层，降低叠加压力
  - 软解优先且片源较重时，适度降低解码侧开销，优先换取稳定性
- Android（含 TV）与 iOS 的 `media_kit` 平台依赖通过 `packages/media_kit_libs_*_video_full` 本地覆盖切换到上游 full 构建；播放业务层不维护 TrueHD 特判，由完整 FFmpeg 的 `MLP / TrueHD` 解码器统一处理，ExoPlayer 与系统播放器依赖不受影响

播放性能模式的运行期保护目前还包括：

- 播放会话打开后，会直接通过统一的 `backgroundWorkSuspendedProvider` 把“非播放优先级”的页面工作切到暂停态，不依赖任何手动性能开关
- 播放页会更早把播放性能模式切到 active，尽量在首帧前就压住底层壳层动画与后台工作
- `StatefulShellRoute.indexedStack` 下的隐藏分支会关闭 `HeroMode`、`TickerMode`，并忽略命中测试，减少播放器上层的 Flutter 合成干扰
- 播放页切到后台后，内置 `MPV` 仍保存播放进度并同步系统播放会话，但不再刷新 TV 播放视觉状态；回到前台时会用播放器当前状态补齐一次
- 首页 `Hero` 后台补数在暂停态下不会继续触发
- 详情页在暂停态下优先只读本地详情缓存，不再继续启动自动元数据补全和本地资源匹配
- 隐藏页面中的网络图片组件会停止继续发起解析和加载请求，避免播放期间还在后台拉图

自动续播与自动跳过规则走本地播放记忆链路：

- 电影按条目记录播放进度
- 电视剧按“剧 -> 集”记录最近一次续播位置
- 最近播放只保留最近 `20` 条
- 最近播放模块可直接消费这份记录
- 首页消费最近播放记录时，会把“记录到某一集”的续播信息映射成“剧集总名 + 单集副标题”的展示形式
- `PlaybackMemoryRepository` 现在会保证每次保存都生成单调递增的 `updatedAt`，避免同毫秒写入时最近播放顺序抖动
- 片头 / 片尾跳过规则按剧绑定，不扩散到其他剧

平台差异：

- Android 原生页按组合方式拆分，不使用 Activity 继承链或依赖整个 Activity 的扩展函数：`NativePlaybackActivity` 保留 Android 生命周期转发及公开 Intent/Result 常量，`NativePlaybackCoordinator` 负责组件装配、生命周期顺序、启动参数与 Player 事件路由。每个有状态组件通过自己的 `Host` 接口声明所需依赖，不持有协调器具体类型；纯策略与数据仓库不依赖 Activity。
- `NativePlaybackSession` 独占 Exo/带宽实例的创建、释放与原地重建入口，复用既有 renderers、load error、audio 和 buffer policy；`NativePlaybackLaunchController` 管理启动回执、连续 30 秒无进展期限、60 秒硬期限与失败弹窗，启动期间每秒检查并按最近期限缩短最后一次调度；`NativePlaybackRecoveryController` 管理 HLS/转码回退与软/硬恢复副作用。启动等待在 `prepare` 前建立，已耗尽预算则直接失败，不给新实例重新 prepare 的机会；失败释放或同步替换实例后不再继续绑定旧播放器。各入口保留进度与 playWhenReady 的原有语义。
- `NativePlaybackEpisodeController` 管理选集、切换和下一集预解析，`NativeEpisodeTransition` 统一管理 IDLE/RESOLVING/SWITCHING/WAITING_FOR_FIRST_FRAME/FAILED 状态与请求序号；`NativeEpisodePreparationKey` 绑定完整队列、目标索引、当前播放目标、resolver 会话、当前 URL/请求头/MIME，替代旧 `NativeEpisodeResolutionRequest`。结果未被消费前不更新队列或释放旧播放器，新 Intent/销毁使请求和缓存失效；自动片尾与 ENDED 去重，手动选集优先，切换到首帧之间拒绝重复切换。
- `NativePlaybackStartPolicy` 在 `prepare` 前决定 `setMediaItem` 的起点：显式运行期 override（包括 0）优先，自动下一集忽略旧历史并应用片头，非自动入口按 allowResume 读取历史，无历史时才用片头；allowResume=false 的显式从头播放从 0 开始。真实 timeline 时长可用后检查片头越界并回到 0，READY 不再重复执行启动片头 seek；纯音频 READY 可完成切集等待，视频等待首帧。启动进展来自 `totalBufferedDuration` 按共享 1 秒阈值累计增长，或 `NativePlaybackTransferProgress` 记录的最新实际网络字节接收时间；不把 `bufferedPosition` 中的片头/续播偏移、`isLoading`、连接开始/结束、HTTP 重试及历史带宽估计算作进展。每个 Exo 实例的 HTTP 工厂单独绑定 TransferListener，后台加载线程只写入线程安全的单调时间戳，不向主线程逐字节投递消息，旧实例迟到回调不影响下一实例。
- `NativePlaybackRuntimeController` 在片尾边界直接请求切集，成功解析后、释放旧播放器前显式保存旧集 completed=true，仍保留真实 position/progress；最后一集不 seek 文件尾，保存完成后暂停。完成标记在本集后续保存中保持，手动 seek 或切换新媒体时清除。手动拖回片头不会重触发片头跳过，拖入片尾可观看片尾；修改跳过设置会重新评估规则。运行循环使用 generation 防止循环内切集重建后又重复排入旧循环。
- 预解析复用原运行循环：只在正常播放的结束边界前 30 秒内准备紧邻的一集，每个准备键最多一次后台尝试；缓存 TTL 为 60 秒，后台与直接前台解析各为 30 秒。已有未过期后台请求首次提升为前台切集时，从接管时刻给予一次 30 秒窗口，不重新发请求；`NativeEpisodeTransition` 统一保存请求截止时间，tick 与结果回调共用 `isExpired`，重复 ENDED、暂停/恢复不会再次续期。后台失败不弹窗，前台失败不被后续 ENDED/片尾轮询反复触发；暂停、字幕搜索或拖离片尾后迟到结果只缓存，不自动切集。预解析地址在首帧前遇到 401/403/404/410 时，用原未解析目标刷新一次，失败走播放失败交互。`playback.performance` 记录切集请求到首帧/音频就绪的耗时；解析失败记录耗时与 timedOut，启动超时记录加载状态、缓冲、尝试次数和失败原因，不记录 URL/请求头；缓冲预算和单播放器释放顺序不变。
- Exo 多阶段启动共用预算：HTTP 加载级重试、HLS/转码回退、预解析地址刷新及播放器重建不重置 60 秒硬期限或无进展基线；释放前采样最后进展，首次启动后的地址刷新保持计时器运行，超时通知 `episodes.onPlaybackFailed()` 使在途解析失效。初次地址解析在开流前独立限时；首帧就绪结束本轮启动，手动重试或切换新媒体重置预算。配置由 `config/playback_policy.json` 的 `exoStartupHardLimitMs / exoStartupNoProgressTimeoutMs` 生成，MPV 的 `startupHardLimitMs=120000` 不变。
- `NativePlaybackRemoteController` 处理按键与退出确认，`NativePlayerTvSeekPolicy` 管理方向键长按计时/重复次数；`NativePlaybackControllerView` 管理标题、焦点、控制栏显隐和 Surface 遮盖；`NativePlaybackSettingsController` 管理设置与临时选项弹窗。onStop 时各弹窗由所属组件清理，原有焦点恢复顺序不变。
- TV 左右键由 `NativePlaybackRemoteController` 按 `deviceId / keyCode / downTime / Player` 持有一次按压，首按即时定位；长按沿用加速档位，使用单调时钟在 `250ms` 窗口内累计并裁剪绝对目标，只保留一个回调，通过 `NativePlaybackSession.seekTo` 提交。松手立即提交尾部目标，取消抬起丢弃；换向以待提交目标为基准重新从 `10s` 档开始。失焦、生命周期暂停、释放播放器或其他按键取消待执行任务；回调复查 Player 身份、窗口、挂载与弹窗状态，未持有按压的迟到重复事件不启动新跳转。
- `NativePlaybackTrackController / NativePlaybackTrackChoices / NativePlaybackTrackModels` 分别负责选轨交互、候选构建/双字幕匹配及轨道模型；`NativePlaybackSubtitleStyleController` 管理全局主/副字幕样式；`NativePlaybackExternalSubtitleController` 管理文件选择、在线搜索返回与挂载，`NativePlaybackSubtitleFiles / NativeSubtitleTiming` 分离 Android 文件访问和纯文本 SRT/VTT/ASS 时间偏移。实际双字幕渲染仍由既有 `NativeDualSubtitleController` 承担。
- `NativePlaybackRuntimeController` 管理运行循环、watchdog 调度、自动跳过和进度采样；`NativePlaybackDiagnostics` 管理会话性能、带宽与运行日志；`NativePlaybackSystemController` 管理系统会话与画中画。`NativePlaybackMemoryStore` 独立管理 SharedPreferences 快照读写、20 条历史裁剪和剧集字幕/跳过偏好，以显式 key 接收请求并保留强制 commit/普通 apply；`NativePlaybackTarget / NativePlaybackMarkers / NativePlaybackSource / NativePlaybackFormatting` 分别提供目标信息、章节标记、源地址处理和显示格式。
- Android 原生播放器容器页当前使用原生 `Activity + Media3/ExoPlayer` 承载播放，在 UI 中命名为 `ExoPlayer（原生）`；它会跟随设置选择 `自动 / 硬解优先 / 软解优先` 和独立的音频输出模式
- Android 原生播放器按实际 `Format.sampleMimeType` 决定音频输出策略，始终注册 FFmpeg 备选；TV 自动 E-AC-3/JOC、PCM 兼容及故障回退禁用对应压缩直通，FFmpeg 支持时将该音频路由到扩展 renderer。`NativePlaybackAudioSink` 包装 context-aware 默认 sink，保留设备能力监测和 PCM 能力查询。系统解码器的软/硬解优先使用稳定排序，不删除其他候选。
- `NativePlaybackRecoveryController` 将非 DRM 音频恢复分为独立预算：解码初始化/解码失败最多一次 FFmpeg 回退，要求原 renderer 非 FFmpeg 且库支持该 MIME；AudioTrack 初始化/写入失败只对实际高精度或压缩直通输出尝试一次 PCM16，不改变解码器选择策略、不消耗解码预算。网络、视频和 DRM 不进入这两条恢复。`NativePlaybackSession` 保存位置、暂停、倍速、音量和音轨 Format，在新轨道中按身份匹配并创建新的 override；新媒体清空回退预算，不复用旧 TrackGroup。`NativePlaybackAudioTracks` 同时负责飞牛首次 GUID 匹配，语言别名归一化，序号兜底保留不支持轨且要求两端轨道数量一致，已有用户 override 优先。
- Android 音频轨变化日志按内容去重，保留 MIME、声道、采样率、支持/选中状态；初始化区分 `ffmpegConfigured / ffmpegAvailable / audioFallbackMime`，真实 decoder 回调及 AudioTrack 初始化记录 decoder 名称、输出 encoding、采样率、声道掩码、offload/tunneling。MPV 在会话结束的有界属性查询中增加音频 codec、输出后端、输入格式、输出声道/采样率和 A/V sync，不新增高频轮询。
- Android 原生播放器的字幕菜单不使用 Media3 泛化轨道名称，而由 `NativeSubtitleTrackLabelPolicy` 按内置 MPV 的“标题 · 语言 · 默认/强制”顺序生成；`und / zxx` 不显示为语言，外挂字幕优先显示文件名
- Android 双字幕由 `NativeDualSubtitleController` 管理主/副文本 renderer，按选定轨道的 `NativeSubtitleFormatKey` 路由，不再把副轨写死为英文。样式从 Flutter 全局设置传入，播放内修改经窄保存回调持久化；普通模式只启用主字幕，PGS/VobSub/DVB 不进入双字幕候选
- Android 原生播放器的跨集字幕恢复由 `NativeSubtitleSessionPreferencePolicy` 匹配新的 `TrackSelectionOverride`；双字幕恢复成功后再重新配置 `NativeDualSubtitleController` 的主/副路由，不保存上一集的 Media3 group 或 override 实例
- 非 Web 内置 MPV 使用原生 `sid / secondary-sid` 选择两条分离的内封文本轨，同时向 libmpv 写入 `sub-pos / secondary-sub-pos / secondary-sub-scale`；由于当前 `libass=false`，画面上的主/副字幕由 Starflow 自定义 Flutter 叠层分别渲染，保证窗口态与全屏态都使用独立位置和字号。跨集时由 `PlaybackSubtitleSessionPreference` 分别匹配新的 `sid / secondary-sid`。图片字幕和临时外挂字幕不进入特殊模式。播放设置一级通过“更多”打开二级页，二级页同时提供字幕布局、后台播放、手势、卡顿恢复和性能调优开关
- 非 Web MPV 控制层左上角以返回按钮作为第一个控件，不保留人为前置间距；其右侧网速标签每秒读取 libmpv `cache-speed`。`MpvNetworkSpeedLabel` 与直播 `LiveNetworkSpeedLabel` 适配到共享 `PlaybackNetworkSpeedLabel`，按播放器／来源与播放 generation 隔离迟到结果，2 秒读取超时后显示未知并允许下一轮重试。隐藏或销毁停止轮询，重新显示清空旧样本。启动／缓冲叠层接入当前播放器标签后不重复显示格式行。标签无独立背景，固定 160×36 逻辑像素，两行水平居中、等宽数字，各行超出时独立缩小以保持边界；桌面 / 手机 Adaptive 控制层和 TV chrome 共用组件。
- 第一行为 `网速 · 缓存大小 · 缓存时长`，无 `Cache / Buf` 标签：MPV 读取 `demuxer-cache-state/fw-bytes` 和 `demuxer-cache-duration`；Exo 每会话保留 LoadControl 的 `DefaultAllocator` 并读取 `totalBytesAllocated`，时长取已缓冲位置减播放位置且不小于零，释放／换集清空引用。两种内核提供的都是近似媒体缓存量，Exo 包含分块余量，不等同精确下载大小或磁盘离线缓存。各指标独立处理失败／超时，缓存值不平滑，未知显示 `--`。第二行仅为当前媒体的分辨率、视频编码、音频编码；MPV 的 `mpv_playback_format.dart` 读取 `video-params/w / h`、`video-format`、`audio-codec-name`，Exo 读取当前 `videoFormat / audioFormat` 而非任意候选轨道。缺项省略，全未知显示“识别中”，不显示引擎名、容器或码率；未创建播放器的启动格式可使用目标元数据。不更改缓存策略、网络传输或解码流程。
- `PlaybackNetworkSpeedWindow`（Dart / Kotlin）仅用于显示：最近 3 个正值取平均，零值／未知立即清空窗口。按 1024 进位，B/s 整数，KB/s、MB/s、GB/s 一位小数，舍入抵达边界时升单位。非法、未采样、超时显示 `--`；两端通过 `test/fixtures/playback_network_speed.json` 校验相同格式及平滑规则，不改变性能统计、启动进展或带宽不足判断。
- 非 TV MPV 的 Material / MaterialDesktop Adaptive 控制层共用 `player_controls_layout.dart`：`PlayerEmbeddedSurface` 在普通模式横竖屏均铺满可用区域，视频继续由 `Video.fit` / `aspectRatio` 处理画面适配；TV 保留居中的比例容器。`PlayerAdaptiveControlsLayout` 在控制层当前位置监听 `MediaQuery.viewPadding`，计算 `viewPadding + EdgeInsets.symmetric(horizontal: 12, vertical: 6)` 并交给两套主题 builder，不在整个控件外加 Padding。主题 `padding` 保持 `0`；上栏 margin 只使用顶部和左右留白，下栏 margin 只使用底部和左右留白，栏高保持 `56`。手机进度条自身使用底部及左右留白再加 `playbackSeekBarMargin` 的底部 `6`，让正常进度条和隐藏控制栏后的临时快进进度条位置一致；桌面进度条在下栏上方，只加左右留白和自身底部 `6`，底部安全区由下栏占位承担。手机中央按钮行单独加左右留白。普通/全屏及播放状态不参与边距计算，视频、自定义字幕、遮罩和手势根层仍使用完整播放器区域，按钮内部点击区域及 TV chrome 不变。
- `media_kit_video 2.0.1` 的 Material / MaterialDesktop 主题 `updateShouldNotify` 使用了反向的身份比较，Adaptive 返回的 `VideoControlsThemeDataInjector` 会导致新主题不通知内部控件。`PlayerAdaptiveControlsLayout` 将这个内部依赖限制在单一兼容适配点：取出 injector 的原始 child，由应用直接提供两套主题，通过私有 `_PlayerControlsThemeRefresh` ThemeExtension 使现有控件的 `Theme.of` 依赖刷新；不修改 pub-cache，不通过旋转 key 重新挂载控制层，不重置显隐、计时器或手势状态，原有系统音量/亮度同步 revision key 仍保留。升级 media_kit 时应复查并移除已不需要的兼容处理。`test/player_adaptive_controls_layout_test.dart` 使用真实 Video / Adaptive 控件及假的播放器后端覆盖横竖屏、单侧安全区、仅 insets 更新、全屏往返、隐藏状态、正常及临时进度条、四角像素和边缘手势。
- Android / iOS 非 TV MPV 的 `MaterialVideoControlsThemeData.backdropColor` 显式设为 `Color(0x33000000)`，即黑色 `20%` 不透明度（`80%` 透明），普通和全屏共用该主题。遮罩铺满播放器并沿用控件库的显隐动画，不跟随按钮栏留白缩小；手势层保留库内 `16` 逻辑像素系统边缘保护及底栏避让，不再额外缩小。MaterialDesktop 渐变铺满播放器，颜色与强度不变；TV 和启动/错误临时顶栏的背景不变。
- 视频控制层创建后，非 TV MPV 的 `PlayerStartupOverlay` 通过 `showSpinner: false` 保留启动/缓冲指标但不重复绘制圆圈，缓冲圆圈由 Adaptive 控制层负责；播放器创建前及 TV 保留应用叠层圆圈。
- MPV 缓冲预算由 `resolveMpvBufferBudget` 统一计算，并通过 Android `starflow/platform -> getMemoryClassMb` 读取 TV 应用内存等级；低内存 TV 将夸克/激进前向缓冲封顶 `96 MB`、回看封顶 `16 MB`，中高内存和非 TV 继续使用原预算。`resolveMpvRemotePlaybackTuningProfile` 还会比较启动速度与片源码率，达到 `2.5x` 且非高风险容器时进入 `fast-start`，否则保留 standard/high-risk 档
- MPV 打开重试先由 `classifyMpvOpenFailure` 分类，只有临时网络错误才在统一总超时内最多尝试 `3` 次（包含首次）；永久资源/权限/格式错误与未知错误不再无条件重复创建播放器。进程内 `PlaybackHostBandwidthCache` 按主机缓存实际播放速度 `10` 分钟，首次播放与切集都只读缓存，不额外发起 Range 预检或测速
- 启动编排通过 `_startupGeneration` 在退出或替换会话后使旧异步任务失效，并在解析、打开和重试边界校验；打开失败只清理仍由当前打开链持有的播放器，已 detach 的实例交给退出/替换路径释放。单次打开从开流到首帧、稳定播放共用启动错误信号，不在中间重置；TCP `ffurl_read` 读取失败纳入有限临时网络重试。
- MPV 的 `_initialize` 在地址解析和本地准备后直接进入 `_openEmbeddedPlayback / _openWithRetry`，移除 `_prepareStartupDiagnostics`、预检拦截、预检 Range 风险状态和预检测速统计。`resolveMpvRemotePlaybackTuningProfile` 的可选 `estimatedMegabitsPerSecond` 来自同主机缓存；缺失时按片源元数据选标准/高风险档，后续经本地 `cache-speed` 更新缓存。`PlaybackRemotePreflight` 仅继续供原生 ExoPlayer 的 SmartStrm 格式探测使用。`playback.startup / playback.mpv` 记录直接打开、启动异常与重试决定；旧 trace helper 已删除
- 当平滑后的同主机速度低于片源码率 `0.9x` 时，MPV 运行期 hard stall 与 Exo watchdog 保留当前连接继续缓冲并提示；MPV 已失败并释放的开流不受该历史速度门槛限制，仍按错误分类有限重试。
- `MpvStartupScope` 统一启动等待的取消信号和截止时间，覆盖调参、开流、首帧、稳定播放、偏好应用及退避；首帧元数据订阅在取消/错误/超时后释放。取消等待不取消底层原生操作，释放仍串行。启动阶段的 error 事件只交给启动流程，ISO 换候选重置错误信号及 HTTP/缓冲证据。单次打开最多保留 12 条原生错误白名单摘要，失败写结构化本地日志；成功后原生 log 订阅随 `_OpenedPlayback` 移交给页面以继续识别运行期 HTTP 错误，与 error 订阅一并在失败/退出/替换时释放。`buildMpvRecoveryTarget` 保留当前集身份并启用续播，恢复成功需要实际进度前进。
- `MpvStartupErrorGate` 处理 media_kit 从原生日志转发的启动错误：非 Web 远程临时错误每 `250ms` 查询本地 `idle-active`，连续两次为真或错误后连续 `15s` 无播放/缓冲进展时完成 `MpvOpenFailure` 信号。每次属性查询最多 `250ms`，连续六次不可用则失败；持续进展仍受共享启动截止时间限制。永久/未知及本地/Web 错误即时处理。成功、失败、退出和 ISO 换候选均清理 gate；日志保留白名单摘要、延后错误数和确认方式。
- `mpv_tuning_policy.dart` 提供 HTTP 重连参数、状态解析和 typed `MpvOpenFailure` 分类。HTTP/HTTPS 的 `stream-lavf-o` 与 `demuxer-lavf-o` 均设置连接失败及 `408/425/429/5xx` 的有限重连，通过 `demuxer-lavf-propagate-opts=yes` 传入 HLS 子请求；状态列表采用 mpv `%15%` 长度引用，不能用反斜杠转义逗号。FFmpeg 6 的 `reconnect_delay_max=7` 对连续连接失败形成 `0/1/3/7s` 退避，正常 EOF 和不可 seek 响应重放均关闭；应用层仍最多三次创建及原总超时。
- `MpvHttpFailureEvidence` 只在内存中短暂关联 FFmpeg/stream/lavf 的真实 HTTP 状态和通用网络错误，证据最多有效 `1s`，已知不同 URL 不关联，进展及换候选后清除；不写出 URL/鉴权信息。HTTP 状态优先参与启动与运行期永久/临时分类，下一集预解析地址只在 `401/403/404/410` 时刷新一次。
- `MpvBufferProgress` 以缓冲位置累计增加 `1s` 或百分比增加 `1` 个百分点记录高水位，避免往复抖动无限保活；`MpvStallWatchdog` 同时观察实际播放与缓冲进展，后退 seek 清理高水位，细小播放步进累计判定。启用 HTTP 重连的片源采用 `15s / 30s` 软/硬停滞阈值，给底层有限退避留出时间。远程运行期自恢复窗口为 `15s`，合并期间的临时错误并暂停另一条 watchdog 恢复链；窗口结束仍有近期缓冲进展且 watchdog 启用时交回监测，不记为恢复成功、不消耗主动恢复次数；永久错误可立即中止等待。
- Exo 卡顿检测和恢复决策由纯 Kotlin `NativePlaybackWatchdogPolicy` 管理，包含播放/缓冲进展计时、恢复冷却、低带宽等待和软恢复次数；时钟可注入以验证边界。`NativePlaybackRuntimeController` 负责调度和前台/画中画判断，`NativePlaybackRecoveryController` 执行恢复并通过 `NativePlaybackSession` 重建；策略类不持有 Activity 或 Player。`launch.isStartupPending` 时 watchdog 只重置进展基线，不在首帧前重复 seek/prepare 或重建，纯音频 READY/视频首帧结束启动等待后恢复运行期判断。15 秒播放停滞、45 秒缓冲停滞、10 秒恢复冷却和最多两次连续软恢复的原有规则不变。
- Android 原生播放器同时记录视频轨 MIME、编码、尺寸、色彩信息与支持状态；检测到存在视频轨但当前设备全部不支持时，会以 `static=false` 重新请求 Emby 转码流并从原进度继续
- Android 原生播放器额外包含与 Media3 同版本的 `media3-exoplayer-hls`；`/smartstrm_fid/` 只在目标为 MP4/未知格式时执行最多 `64` 字节、约 `1.5s` 的轻量预检，以 MP4 `ftyp` 或 HLS `#EXTM3U` 文件头优先选择 MediaSource。已知 MKV 等其他容器不再产生额外 Range 探测；其他含 `#/%23` 的 SmartStrm 地址仍保留探测。预检失败或文件头不明确时继续按原格式启动；标准 `/smartstrm/` 与 `/smartstrm_*/` 路径在首次解析错误 `3003` 后仍由 `NativePlaybackHlsFallbackPolicy` 保留进度并强制切换 HLS 一次
- `NativePlaybackSource.buildRequestHeaders` 只负责构造原生播放请求头：保留目标已有 `User-Agent`，缺失时才补 `Starflow`；`NativePlaybackSession` 不再调用 `DefaultHttpDataSource.Factory.setUserAgent`，避免后写覆盖飞牛 115 直链要求的浏览器 UA。
- Android 原生 progressive TS 使用 `NativePlaybackExtractorsFactory` 替换默认 `TsExtractor` 的 payload reader。Session 将当前目标 `audioCodec` 传入 factory；`NativeTsPayloadReaderFactory` 仅对 `0x80` 且编码精确匹配 `pcm_bluray`（忽略大小写及首尾空白）或 ES 注册描述符（tag `0x05`）标识 `HDMV` 的流启用 `PcmBluRayReader`。描述符按 TLV 边界解析，截断、过短注册描述符及非 HDMV/冲突注册信息均保留默认 reader，即使目标编码为 `pcm_bluray`。未使用 PMT program-level 描述符或读取媒体包猜测；无证据的 NAS/STRM `0x80` 仍走默认 `DC2/H.262`。reader 解析 HDMV 布局 1/3/9/11（单声道、双声道、5.1、7.1）的 48/96/192 kHz、16/20/24-bit 数据，保留位深输出 PCM16/PCM24，其他布局明确抛出不支持错误。默认 reader factory 额外启用 `FLAG_ALLOW_NON_IDR_KEYFRAMES`，由 Media3 识别 H.264 非 IDR I slice，避免开放 GOP 在 seek 后无关键帧可读；不启用其他 TS flags，不影响 HLS extractor 或内置 MPV。
- `0x90` Blu-ray PGS 流由 `PgsReader` 按 segment header 跨 PES 聚合 `PCS / PDS / WDS / ODS / END`，完整显示集以 `application/pgs` / `S_HDMV/PGS` 提交给 `NativeSubtitleParserFactory` 的 `BoundedPgsParser`。显示时间锁定为 PCS 开始处的 PES PTS，即使 segment header 跨包也不被后续 PTS 覆盖；缺少 PCS 时 reader 保留首段时间，parser 不推测缺失的组合对象。新 PCS 会抛弃缺失 END 的旧显示集，单个显示集最多缓存 `4 MiB`，超限后忽略至 END 或新 PCS；seek 清空组装状态。PGS parser 按 ID 管理对象/调色板，支持多对象、裁剪、窗口和正常组合复用；epoch/acquisition 清缓存。对象编码缓存上限 `8 MiB`，sample/解压上限 `4 MiB`，组合像素上限 `3840 × 2160`。`BoundedVobsubParser` 基于 Media3 1.10.1，增加循环前进与分配边界；DVB 保留上游解码但预检资源并修正 offset。progressive extractor 按自身作用域记录 parser，seek/release 显式 reset，TS PGS/DVB 连续性中断按 format ID reset。MediaSource 字幕入口使用同一工厂，Blu-ray `0x90` 自定义识别不扩展到 HLS。详细限制见 [字幕链路](subtitles.md)。
- `NativePlaybackExtractorsFactory.TS_TIMESTAMP_SEARCH_BYTES` 将 progressive TS 的 PCR 搜索窗口设为 `6000 * 188 = 1,128,000` 字节（默认 `600 * 188`）。高码率 / 可变码率 TS 的相邻 PCR 可相隔数百 KiB，旧窗口找不到 PCR 时，Media3 `TsBinarySearchSeeker` 会退出二分定位并从估算字节位置读取；首尾搜索不到 PCR 还会让 `TsDurationReader` 无法确定时长。扩大的有界窗口同时供这两个原有组件使用，不自建 seek 算法，不改变其他容器、HLS、MPV 或加载策略。回归测试直接调用 Media3 定位器和时长读取器，用稀疏 PCR 流验证旧窗口的错误落点及新窗口的收敛；这不代替 TV 解码和字幕屏幕位置验证。
- `NativeSubtitleRenderer` 包装 Media3 `TextRenderer`，将其 cue 回调留在播放线程，再由 `NativeSubtitleOutput` 单槽队列交付 UI。PGS/VobSub/DVB 每轮最多追赶 32 次，`BitmapSubtitleSampleStream` 最多允许一条未来样本进入 resolver，保持外部原 stream 身份与 offset 语义；后续每帧仍调用 render 以推进显示/清屏。到达追赶上限时保留最后状态但暂不发 UI，下一轮继续。主、副 renderer 各自持有状态；reset/disable 清除旧更新，disable 通过公开 position reset 清理 resolver，release 关闭输出。Media3 继续负责 cue 替换和时间轴，不改 PGS PTS。`lagMs` 超过 1 秒时最多每 5 秒记录一次，其余维持 30 秒限频，它不是解码耗时；`subtitle.decode` 另记录 PGS 解码耗时/像素/编码缓存，`subtitle.decode.drop` 记录丢弃原因，`subtitle.catch-up` 记录追赶批次，均限频且不含字幕正文。
- MPV 的 `MpvSubtitleRenderBinding` 独立管理字幕可见性，订阅 track、tracks 及原生 sid，解析 auto 的实际轨道并容忍迟到元数据；串行合并属性写入、检查关闭状态、失败写结构化日志。`subtitle_render_policy.dart` 统一渲染、双字幕、偏好指纹和飞牛外挂的 codec/image 判定。绑定不修改 sid，不抢用户选轨；关闭时解除观察及订阅。
- 原生运行期日志另记录 `awaitingVideoFrameAfterSeek`：存在已选视频轨时在 seek 回调中置位，收到 `onRenderedFirstFrame` 后清除，创建新播放器时重置。与历史 `firstFrame` 分开，便于区分“本会话曾出画面”和“此次快进已恢复画面”；该标记只用于诊断，不把字幕输出或播放时钟推进视为视频出帧，也不新增自动恢复策略。
- `PcmBluRayReader.createTracks` 提前注册音轨，格式在完整音频头可用时发布；非法布局、位深、采样率、payload 长度或 PES 边界截断的音频头明确失败，不静默等待 Format。完整采样帧使用固定 24 字节 scratch，输出复用 46,080 字节缓冲和 ParsableByteArray，最多 10 ms 或 PES 完成时提交。16-bit 保留 PCM16，20/24-bit 的三字节存储完整反转为 PCM24，不在 reader 丢弃低位。位深变化也发布新 Format。`sampleData` 遵循 `(data, length, SAMPLE_DATA_PART_MAIN)`，时间戳按实际采样宽度和累计采样帧计算，缺 PTS 时延续时钟，变采样率先折算上一段时长；seek 清除时钟、包头和残片。未完成的采样帧不跨 PES 拼接。
- `NativePlaybackAudioPolicy.useHighPrecisionPcm` 决定输出：非 PCM 兼容模式、speed/pitch 均为 1 且无会话回退时启用 Media3 float output。高位深由其 `ToFloatPcmAudioProcessor` 转换；兼容路径使用上游 `ToInt16PcmAudioProcessor` 和 Sonic，不自研重采样、降位深或 dither，也不宣称兼容转换无损。非正常 speed/pitch 同时禁用压缩直通，但不因此强制 FFmpeg。`Session.setPlaybackParameters` 在提交倍速前依据实际 sink 状态决定是否重建；普通 PCM16 原地更新，高位深/float、正在直通或恢复此前因倍速关闭的直通时才切路径；尚无 sink 证据时保守处理。`stagePlaybackParameters` 让飞牛重开在创建 sink 前拿到倍速。sink 配置回调补偿随后切入高位深音轨；参数监听和输出观测按播放器实例隔离，忽略旧实例/过时回调。必要的重建会重新开流并恢复位置、音轨、音量、暂停状态。
- `NativeAudioOutputState` 每个播放器独立记录 sink 输入 Format、真实 decoder 和 AudioTrack encoding，释放时替换；Recovery 优先使用 AudioSink 异常自带格式，其次取当前 sink，不能把 AAC/DTS 等压缩 renderer 输入直接当成实际输出。高精度/直通输出失败单次回退 PCM16，不依赖 FFmpeg raw 支持；已经 PCM16 的输出失败不触发这条回退。新媒体重置，手动输出选择可清除当前格式强制项但不刷新自动重试预算。Diagnostics 分别记录输入 PCM encoding 和实际 AudioTrack encoding，并附 PCM16/PCM24/Float32 等可读标签；reader 另记录源 16/20/24-bit，避免把 PCM24 容器误写成 24 位有效输入。Android 混音器和 HDMI 最终格式不属于此日志的保证范围。
- `NativeAudioPrecisionHistory` 由 Session 按当前媒体持有，记录已观察到的高精度输出因倍速关闭时的源音轨身份；返回正常 speed/pitch 且策略允许时补偿系统解码器 PCM16 无法自行说明历史的问题。恢复重建前清记录，普通重建保留，换媒体、手动输出模式、设备/解码回退清除；不根据 codec 推测源位深。`NativeAudioDecoderPrecisionPolicy` 将 FFmpeg 恢复候选限制在当前 AAR 支持的非 AC-3 MIME，不为固定 PCM16 的 AC-3 重建。状态观测区分源 Format、sink 配置尝试与活动 AudioTrack，配置不等于新输出已建立；复用时保留输出，释放回调清理对应实例。
- `NativePlaybackAudioOutputProvider` 仅接管高精度 raw PCM 的自动缓冲区查询，把明确的 `AudioTrack.ERROR_BAD_VALUE` 转成 provider 配置异常，由真实 `DefaultAudioSink` 包装成携带输入 Format 的 `AudioSink.ConfigurationException`；其他 runtime 异常不按消息或调用栈猜测恢复。成功路径沿用 Media3 1.10.1 默认缓冲区计算，PCM16、压缩输出和显式缓冲区保留原路径，包装仍转发设备能力与声道能力。升级 Media3 或自定义缓冲区策略时须复核该适配。
- `rendererFormat` 缺失时，输出恢复只接受已知音频 renderer 的 AudioSink 格式证据；系统解码器还必须有当前源轨证据并排除 DRM，不能用已去除加密元数据的 raw sink 代替源轨。FFmpeg renderer 本身拒绝 DRM，但显式 DRM 标记仍阻止恢复。状态通过不可变快照发布，旧 track/decoder 释放不能清除新实例；Media3 回调缺少实例 ID，相同配置或名称按 FIFO 配对，不能保证识别逆序释放。源轨没有 ID 时，精度历史只接受同一 Format 对象，重建后无法确认身份则保守不恢复。
- `NativePlaybackSession` 保持其他容器的 extractor、HLS 工厂、load control 档位及启动预算不变；`1004` 本身不是 HLS 格式证据，不据此强制回退 HLS。
- Android 原生启动通过 `buildDeferredNativeEpisodeQueue` 携带当前季的完整未解析队列并保留真实 `currentIndex`，只用已解析目标替换当前条目；原生选集、上一集、下一集和播放结束自动续播统一通过 `starflow/native_playback_resolver` 回调 Flutter，按选中的单集执行 `PlaybackTargetResolver` 和必要的 SmartStrm MP4/HLS 探测。异步解析期间旧播放器不释放，成功后才更新队列条目并切换，失败或会话变化则保留当前视频
- Android TV 原生播放器内切换远程剧集时，`releasePlayer()` 先清理旧 Exo、Surface、Analytics/带宽监听、运行循环、看门狗和系统媒体会话；新集不继承旧 URL、MediaSource 或缓冲数据。`NativePlaybackBufferPolicy` 将起播／恢复门槛与后台预读预算分开：TV 未知／均衡带宽恢复门槛为 `2s`，同主机快网（带宽／片源码率至少 `2.5x`）为 `1.5s`，慢网（低于 `1.25x`）为 `3s`，不随内存档或切集增加。切集起播与首次打开同档，基础为 `1.5 / 2 / 2.5s`，快网降至 `1.2s`、慢网增加 `0.5s`；不再强制切集 `6s / 12s`。低内存普通片源首次打开基础为 `minBuffer=20s / target=32 MiB`，内部切集为 `30s / 48 MiB`，运行期字节目标在下文动态预读规则的上限内调整；达到短门槛后可播放并继续预读，不必填满缓存。这些是缓冲媒体时长而非墙钟等待时间；网速持续低于码率仍可能再次卡顿。手机 Exo 和直播策略不变，MPV 的独立策略见下文。`native.queue.old-player-released` 与 `native.buffer-policy episodeSwitchWarmup=true` 继续标记释放和切集预读档，后者不再表示较长起播／恢复门槛。
- 内置 MPV 的 TV、Material 和 Material Desktop 控制层都直接消费 `PlaybackEpisodeQueue`，不使用 media_kit 内部单媒体 playlist 的上一项/下一项按钮；三端统一显示边界可用状态和右侧选集面板。手动选集、相邻集及自动续播最终收口到 `_switchPlaybackQueueIndex`：先取用命中的预解析地址，否则用 `PlaybackTargetResolver` 解析目标单集并校验可播地址，成功后才保存旧集进度、关闭旧播放器并初始化新集，解析失败时队列索引和当前播放器保持不变
- MPV 的 TV 下键由独立 `_OpenTvEpisodePickerIntent` 处理：有可浏览队列时直接打开选集，没有队列时打开播放设置；选集不主动收起或显示控制栏，控制栏是否可见保持进入前的状态
- Flutter `player_episode_picker_dialog.dart` 在非 TV 模式的标题栏最左侧提供返回箭头，复用现有工具按钮的 44dp 点击区域及语义标签；关闭返回空选择，不提交剧集或候选队列，切季加载时仍可使用。TV 不增加返回按钮，保留返回键关闭；剧集末尾继续按下保持当前焦点和滚动位置。
- Flutter 选集初始定位、模式/分段切换与方向键移动共用整行对齐偏移：取最接近居中位置的 72dp 行边界。滚动内容底部仅在需要时补不足一行的余量，使末尾最大偏移也对齐行边界且最后一行完整可见；不改变条目高度，不干预手动滑动，也不使用首帧后的补滚动。Android 原生选集定位策略不受此变更影响。
- `PlaybackEpisodeBrowser` 负责选集会话内的季列表、单季元数据及 in-flight 缓存，失败清除对应缓存后可重试；`PlaybackEpisodeQueueResolver.loadSeasons/loadSeason` 复用媒体服务子列表和 NAS 本地索引，不解析播放地址。浏览其他季的队列使用 `currentIndex=-1`，通过 `PlaybackEpisodeSelection` 将候选队列与选择索引交给播放层，MPV 在地址解析成功且原队列仍有效后才提交。Android 经 `browseNativePlaybackEpisodes` 回调同一服务，`NativePlaybackEpisodePicker` 只负责面板；`NativePlaybackEpisodeController.selectedSeasonQueue` 暂存跨季候选，失败清除，成功才提交为播放队列。
- 两端选集面板采用列表/四列网格，TV 宽度为可用宽度的 `30%` 并夹紧在 `320–600dp`，窄屏继续占满可用宽度；每段最多挂载 30 个轻量条目，按真实集号显示分段边界，遥控器移动可跨段。当前播放依据资源 key 标识而不是焦点位置；本地历史仅作显示，不修改历史保留策略。Flutter 选集及季/范围弹窗使用 `AnimationStyle.noAnimation`；Android 对应窗口在显示前设置 `windowAnimations=0`，主面板的尺寸与位置也在显示前确定，避免默认窗口缩放和显示后扩张。Flutter 关闭后恢复原 FocusNode，Android 优先恢复仍挂载的入口 View。单季加载带请求代次校验和 30 秒超时，关闭面板或切换请求后忽略迟到结果；不加载剧照、不预解析整季。
- MPV 的跳过与连续播放规则由 `playback_auto_skip_policy.dart` 提供，与 Kotlin `NativePlaybackStartPolicy` / `NativePlaybackSkipPolicy` 对应：`resolvePlaybackStartPosition` 在创建播放器之前决定开流起点（自动下一集忽略旧续播并应用片头，非自动入口按 allowResume 用续播点，无续播点才用片头），`resolvePlaybackEndBoundary` 给出结束边界，`shouldPrepareNextEpisode` 给出边界前 `30s` 的预解析窗口。
- MPV 起点通过 media_kit `Media(start:)` 交给 mpv 的 `on_load` 钩子（`on_unload` 会自动复位）。`PlaybackIntroStartGuard` 在开流前订阅 duration，在首帧 / 稳定播放等待期间发现越界便同步将有效起点改为零并执行自动 seek；纠正期间不确认就绪，结束后重新建立位置基线、确认窗口与 watchdog，迟到 position 回退也重置基线。订阅在成功、失败和取消时释放；`_OpenedPlayback.effectiveStartPosition` 传递最终起点，ISO 后续尝试及 finalize 不恢复无效片头。有效起点仍仅在后端偏差超过 `10s` 时兜底 seek，不新增常规二次缓冲。
- MPV 的剧集队列只在没有队列时解析：切集和故障恢复复用内存队列并替换当前条目；冷启动的内嵌路线在开流后台解析队列，`launchSystemPlayer / launchNativeContainer` 两条路线仍在 executor 前同步解析
- MPV 到达结束边界时经 `_advanceAtPlaybackEndBoundary` 直接切下一集，不再 seek 到文件尾。`PlaybackCompletionState` 独立记录因跳过而完成，仓库 `saveProgress(completedByAutoSkip:)` 将其与原完成策略取 OR，但保存真实 position / progress，不增加 JSON 字段、不在仓库继承旧完成状态；同媒体恢复保留，手动 seek 和新播放清除。最后一集先设置完成并暂停，再强制保存，暂停 / 退出采样继续传递标记。
- `PlaybackEpisodeAdvanceGuard` 管请求所有权、自动失败去重及提交阶段；每次 await 后校验令牌、播放器、队列和上下文，自动请求另复查当前边界 / 播放意图。显式暂停、手动 seek、改规则和字幕搜索使尚未提交的自动请求失效，手动选集可取代它；自然 EOF 的 playing=false 不被误认成用户暂停。提交前无 await 地锁定请求并 detach 旧播放器，随后保存 / 释放；旧 finally 不清除新请求。
- `PlaybackInteractionPlayer` 截获所有通过 Player API 的手动 seek / 播放意图，在后端位置事件之前设置保护，覆盖 Adaptive 进度条 / 滑动 / 双击 / 桌面键盘及 TV / 系统媒体命令；应用启动、片头纠正和恢复通过显式 automatic 方法绕过。自动 seek 不撤销已完成状态。
- `PlaybackEpisodePreparation` 只缓存地址与请求头，绑定播放代次、当前队列 / 目标和设置快照；背景每键一次，TTL `60s`，后台 / 直接前台解析 `30s`，在途请求首次转前台只延长一次 `30s`，后续调用不续期。自动意图取消不清缓存；上下文变化 / detach / 销毁取消计时器并拒绝旧结果，显式手动重试可重新解析失败。切集和预解析共用键，已解析目标通过 `targetAlreadyResolved: true` 进入启动，飞牛不重复解析；预解析地址的可刷新永久错误仍仅用原目标刷新一次。
- Flutter、Android MediaSession 和 iOS MPRemoteCommandCenter 通过 `hasEpisodeQueue / hasPrevious / hasNext` 共享系统媒体动作语义：存在多集队列时隐藏 10 秒快退/快进并发布上一集/下一集，普通影片则继续发布快退/快进与进度拖动；系统命令不再在剧集边界回退成 seek。MPV、Android 原生和 iOS 原生的切集成功路径均不显示额外提示，只保留解析中与失败反馈
- Android 原生播放器复用每秒运行循环做续播采样，实际仍按约 `10s` 的位置差值节流落盘；内置 `MPV` 和 iOS 原生播放器使用同一量级，生命周期暂停、返回、切集和关闭路径会强制保存
- `PlaybackMemoryRepository` 在进程内缓存解码后的快照：写入时同步更新缓存，避免播放中每 `10s` 的进度保存都触发一次 `reload()` + 整份 JSON 解码。原生播放器写同一物理键，因此应用回到前台时由 `AppRuntimeRecoveryBoundary` 调用 `invalidateSnapshotCache()` 使缓存失效
- Android `NativePlaybackMemoryStore` 复用内容未变的已解析快照；每次读取仍核对 SharedPreferences 原始字符串，外部写入、清空和非法内容替换会失效。所有本地写入成功后回填缓存，失败时丢弃已变更对象，跳过偏好返回小对象副本，避免调用方污染快照；持久化键、20 条裁剪和 commit/apply 语义不变。
- 系统媒体会话发布先用位置、时长、播放/缓冲状态和队列边界这些便宜字段判断是否需要发布，命中后才构建标题、副标题和封面候选；所有会改变这些元数据的路径都会带 `force` 触发一次同步
- Android `PlaybackSystemSessionManager` 继续每次发布 PlaybackState，`PlaybackSystemSessionUpdatePolicy` 将标题/副标题/时长变化与通知按钮变化分开去重；仅位置、缓冲或速度变化不重建元数据和通知。图标每个管理器最多解码一次，将现有 `1024×1024` 资源以 `inSampleSize=4` 解码；停用/重新激活清空发布状态，通知权限不可用时不标记已发布，恢复后重发。策略与管理器分别有 JVM 回归测试，MPV 共用此 Android 系统媒体去重逻辑。
- Android / iOS 播放记忆仓库使用带 `reload()` 的 shared preferences，与原生播放器共享物理键 `flutter.starflow.playback.memory.v2`；返回前台时递增播放历史 revision 使首页和详情页重新读取
- Android 原生播放器每 `10s` 记录一次位置、时长、缓冲位置、缓冲比例、播放态、首帧状态与视频尺寸；位置不连续事件单独记录旧/新位置和 Media3 原因码
- Android 原生播放器的 `DefaultBandwidthMeter` 保留性能统计和主机调参用途；右上角显示值改由每会话 `NativePlaybackTransferProgress` 汇总实际网络字节，复用运行期约每秒任务按真实间隔采样，无读取时归零，不回退历史带宽估计。与启动进展时间戳共享既有传输回调，但独立保存计数／显示窗口，释放或重建会话即隔离旧值。手机 / TV 的 `native_network_speed` 无独立背景，固定 160×40dp 双行等宽数字，第一行网速、缓存大小与时长，第二行当前媒体分辨率及编码，两行水平居中；AppCompat 字号自适应兼容 API 23，文本未变不重复赋值。手机 / TV 控制布局分别覆盖 Media3 的底栏动画高度，使两阶段自动隐藏的第一阶段把剩余进度条下沉到实际底边
- 选集初始定位在首次绘制前完成：Flutter 在 `LayoutBuilder` 中按当前分段、行高和实际视口高度设置 `ScrollController.initialScrollOffset`，由当前集 autofocus 接收焦点，不再首帧后 jump；Android 预先构建条目，在一次性 `OnPreDrawListener` 中请求当前集焦点并 `scrollTo`，抑制初始焦点回调的平滑滚动。打开后的遥控器浏览继续沿用原有滚动行为。
- 播放器弹窗经 `showPlaybackMenuDialog` 统一挂载 `PlaybackMenuTheme`，背景唯一配置为 `playbackMenuBackground = #CC18181B`（80% 不透明），禁用 surface tint 和 elevation，避免叠加背景使透明度失真；选集及各级设置菜单不单独重复配置。退出确认通过通用 action dialog 的可选 `dialogWrapper` 接入主题，其他页面不受影响。Android 的 `NativePlaybackSettingsDialogTheme` 仅由 windowBackground 绘制 `native_settings_background = #CC18181B`，内容 colorBackground 透明，选集自绘底板复用同一颜色。前景控件及各入口原有遮罩保持不变。
- 选集结构切换（季、布局、分段）复用绘制前定位：Flutter 用布局代次更换滚动子树和初始 offset，旧控制器在卸载后释放，过时代次不请求焦点；同段方向移动直接更新焦点和滚动，不调用面板 setState。Android 仅保留一个待执行 pre-draw listener，同段焦点回调只发起一次居中，不再 post 重复滚动，关闭移除 listener。
- 列表/网格偏好使用 `episode_picker_layout`（`list`/`grid`），Flutter 经 `SharedPreferencesStore.reloading` 在打开前读取；Android 使用 `FlutterSharedPreferences` 的 `flutter.episode_picker_layout`，两种播放器共享本地模式。仍以当前播放集初始化位置，不记忆临时浏览位置。每段保留 30 集，网格左右停止在本行边界，上下跨段使用段内列号，缺列夹紧到可用项；本季第一集／网格首行上移优先连接可用选季入口，选季上移连接列表模式按钮，列表按钮下移先到选季，选季下移返回原剧集。选季不可用时跳过；本季末集／网格末行继续下移时消费按键，保留当前焦点和滚动位置，不返回标题栏。Android 邻项策略在底部返回原索引，View 不重复执行移动。右上角定位按钮及其焦点节点已移除；网格按钮下移先到可用范围入口，否则到选季或原剧集，范围入口上移回网格按钮、下移回原剧集。Flutter 的节点和 Android View 方向处理均由各自选集面板持有，不改变公共寻焦或跨段索引策略。TV 保留返回键关闭；Flutter 非 TV 和 Android 原生手机端左上角提供返回箭头，加载中仍可关闭，不提交选择。
- 切季保留旧队列、标题和条目，固定高度状态区显示加载/错误，加载中禁止确认旧集；成功提交新队列和季标题后再定位，失败保留旧内容并支持重试。Flutter 单独维护待加载季，空季按失败处理。窄网格集号保持单行，Flutter 必要时缩小，Android 超长集号省略。
- 选集样式统一为深灰面板、6dp 控件圆角、44dp 工具按钮及 22dp 图标。标题右侧仅排列列表/网格切换；36dp 副标题行合并季名与总集数，作为选择季入口，超过 30 集时右侧显示范围菜单。取消底栏、左右分段箭头与重复集数，滚动区直接延伸至面板底部内边距。列表加载/错误原位替换季信息，网格另设 28dp 焦点信息行显示标题/状态或加载/错误。布局选中态用低亮灰底，焦点使用白色描边；Flutter 用独立 ValueNotifier 局部更新信息行，Android 只更新 TextView。TV 列表使用 16/13 字号，手机为 15/12；列表与网格统一 72dp 行高，条目垂直内边距 4dp；Flutter 行距 1.2，Android 标题/状态关闭额外字体 padding，以容纳双行中文标题和状态。滚动定位与渲染共用行高。播放标记、正在播放文字和进度线跟随全局强调色，当前集底色为同色约 9% 不透明度，已看完标记保持中性弱化；网格采用角标而非格内小字，补充语义标签。Flutter 从 `AppActionColors` 取色；原生启动器将当前设置的 ARGB 值作为 `episodeAccentColor` 经 MethodChannel、Activity Intent 传入 Android 选集面板，原生不维护八色映射，缺少参数时兼容默认松石青。该参数仅影响选集状态，不改变其他原生菜单主题或白色焦点框。原生复用本地 Material 风格 vector 图标。
- Exo 手机 / TV 布局的 `exo_play_pause` 直接放在 `exo_bottom_bar` 左侧、播放时间前面，时间行预留按钮宽度及间距，使用 48dp 按钮及无描边的圆形半透明背景，并随底栏收起。TV 在 XML 和运行时均禁用该按钮焦点，保留状态显示及点击；`PRIMARY` 改为 `exo_progress`，不可聚焦时回退播放器容器。手机中央控制组仅保留快退/快进，播放/暂停仍加入底栏横向焦点链并保留焦点高亮。
- MPV 启动和错误状态的 `PlayerAdaptiveTopChrome` 共用 `playbackControlsPadding` 的系统 `viewPadding` 加上下各 `6`、左右各 `12` 逻辑像素规则（临时顶栏将底部 padding 置零），与 Material / MaterialDesktop 控制层共用 `playbackButtonBarHeight = 56`；不叠加其他边距，按钮垂直居中，显隐和点击行为不变。
- `NativePlaybackRemoteController` 在 TV 进度条持焦且无字幕搜索/设置弹窗时接管确定键：仅首次 `ACTION_DOWN` 调用 `togglePlayback`，消费重复按下和抬起事件，刷新控制栏显示但不转移进度条焦点。左右方向键仍由既有 TV seek 策略处理。
- 播放相关按键以 `deviceId + keyCode + downTime` 跟踪一次按压，统一消费已接管按键的重复和抬起事件；TV 确定键不再依赖播放按钮焦点或调用按钮点击，隐藏/显示控制栏、播放器容器和进度条上的确定键均直接调用会话播放/暂停，字幕搜索、设置和退出弹窗不接管。媒体播放/暂停、播放、暂停和空格键也仅执行首次按下；新按压不受遗漏抬起事件阻塞，暂停页面、窗口失焦和新播放请求清理按键状态。
- `NativePlaybackControllerView` 用可移除的单个回调等待控制栏完整显示，每 `50ms` 检查，单次请求最长 `1s`，重复请求替换旧目标。主动/自动隐藏取消等待和弹窗关闭后的恢复回调；暂停、停止、销毁期间禁止新焦点请求，恢复页面后重新允许，窗口失焦和播放器释放取消旧请求。回调执行前检查页面存活、视图挂载及字幕搜索/设置弹窗，避免无界投递及迟到抢焦点。
- `NativePlaybackCoordinator.onRenderedFirstFrame` 仅在当前会话首次首帧回调执行启动收栏，seek 后的重复首帧回调不收栏；`onIsPlayingChanged(false)` 仅在明确暂停且控制栏未完整显示时请求主焦点，不把缓冲当作暂停抢焦点。
- Android 原生播放器的 `NativePlaybackLoadErrorPolicy` 取代统一 `8` 次加载重试：`400/401/403/404/405/410/416` 立即停止，`408/425/429/5xx`、超时和连接类异常最多退避重试 `6` 次，间隔从 `500ms` 增长并封顶 `8s`
- `NativePlaybackHostBandwidthCache` 在当前原生 Activity 内按主机保留 `10` 分钟带宽；`NativePlaybackBufferPolicy` 用带宽/片源码率的 `2.5x / 1.25x` 阈值选择 fast/balanced/constrained 启动与二次缓冲参数，但目标缓存字节仍由内存等级和重片源档位约束

### 点播运行期流畅度策略（2026-09-25）

- TV HTTP/HTTPS Exo 使用 `NativePlaybackLoadControl` 包装 Media3 加载接口；起播／恢复判断仍委托 `DefaultLoadControl`，只调整后台预读。`NativePlaybackBufferBudget` 以基础档为下限，按码率申请约 12 秒内容，应用内存档 `<=256 / <=512 / >512 MB` 的目标上限为 `48 / 80 / 192 MiB`。最高档普通／重型片源及切集的基础目标统一为 `128 MiB`，其余档位不变；内存压力下最高档退回 `128 MiB`。这不是设备标称 RAM 或进程总内存限制，分块和在途读取可有余量，实际缓存也受最大时长约束，不要求填满才播放。手机和本地源继续使用原 LoadControl。
- `NativePlaybackReadAheadPolicy` 每秒比较缓存趋势，活动读取速率低于消耗的 `1.3x` 且连续两次缓存下降时，30 秒内按 20 秒内容预算和更高补充水位预读，仍受原 max 时长和设备目标上限约束。暂停、seek／位置不连续、变速清理趋势；主动达到上限后的停读不作为慢网证据。`NativePlaybackTransferProgress` 单独计算活动网络时段吞吐，UI 网速继续按墙钟间隔显示，二者不混用。
- Android 内存低／严重或后台压力信号使该播放器 60 秒内退回基础目标，回收 allocator 空闲块；不清除待播放数据，不 seek／prepare／重新开流。保留原有限恢复、视频解码器选择与音频输出策略，不因一次掉帧强制软解或降画质。
- `NativePlaybackFrameRateController` 只由 TV 原生“更多 → 刷新率匹配（本次播放）”显式启用，默认关闭，Android 11/API 30 以下无入口。主线程在前台 1x 实际播放时向有效 Surface 请求片源帧率，仅在当前显示分辨率存在兼容刷新率时准入；Android 12+ 明确使用 ONLY_IF_SEAMLESS，Android 11 使用两参数提示。不设置 preferredDisplayModeId，不强制黑屏切模式。启用时关闭 Media3 的重复帧率提示，关闭后恢复 Media3 默认无缝策略；暂停、变速、离开前台、释放时撤销自有提示。硬件是否接受仍由系统决定，兼容失败停止本次尝试，可关闭／重新开启。
- MPV 的 `cache-pause-wait` 与大预读窗口独立：快档 1.2 秒、普通／未知 2 秒、已知慢网 3 秒，RTSP/RTMP 0.5 秒不变。风险容器／编码仍保留较大预读窗口和原 HTTP 超时，但不单独抬高恢复门槛。TV 缓存按已知码率申请约 12 秒，在既有内存档限制内夹紧，非 TV 预算不变。性能静态属性按 Player 身份串行去重，仅成功写入后缓存；字幕、地址、鉴权和每次开流参数不去重，失败可重试。
- 2026-09-26 磁盘缓存统一到 Flutter 播放设置：`playbackDiskCacheMiB` 默认 0，可选 256／512／1024，随配置持久化；替代此前仅 TV 的 SimpleCache 会话入口。MPV、Android Exo、iOS AVPlayer 都通过 `PlaybackStreamRelayService` 传输副本接入，历史／续播／服务端会话保留原始身份。Android 切集和画质／版本重开消费独立 transport URL／headers，不把 loopback 地址写入媒体身份。外部系统播放器及独立直播页不接管。
- `PlaybackRelayDiskCache` 为各代理所有者共享容量，2 MiB 临时字节块、LRU、内存索引，随机会话路径隔离，文件名只有序号，不持久化 URL／headers；媒体字节未额外加密。仅在请求区间已完整缓存时本地回复，否则继续网络；不做整片下载／并行预读，不改变起播／恢复门槛。写入前检查 `512 MiB + 2 MiB + 本块长度` 剩余空间，空间未知或磁盘异常时停用该实例并清理；Android/iOS 使用平台空间查询，桌面通过系统空间命令查询。文件操作异步执行，缓存命中打开文件失败直接走网络，中途文件读失败按已交付偏移发 Range 并验证 Content-Range，服务器不支持正确续接时失败交回播放器处理。
- 未知扩展名通过既有有界前缀识别渐进式媒体／HLS；无敏感凭据的非支持格式在准备失败时保留原直连，安全代理原有拒绝边界不放宽。HLS 点播分片、初始化分片及 WebVTT 可落盘；清单／AES 密钥和动态清单资源保持网络读取，防止同 URL 内容变化。`file/content` 本地视频和字幕直接使用原文件。外挂在线字幕沿用既有有界下载、校验、解码及本地文件流程，不纳入视频块预算，统一清理入口同时清理其仓库；iOS 未因此新增在线字幕选择 UI。
- 清理或关闭容量选项立即停用当前缓存实例并删除临时块，容量变化在后续新播放准备时生效；退出代理按会话前缀清理，最后所有者释放整个目录。已发出的旧写入有代次／前缀撤销保护。应用私有临时目录在首次缓存使用时清理异常退出遗留；字幕临时文件仍按其原所有者回收。容量是视频块预算，不含外挂字幕、打开文件句柄及在途内存。清理设置不重建播放器，已在内存中的播放数据保留。
- Exo `playback.health` 在缓冲、掉帧、音频欠载与视频解码初始化边界限频采样，记录缓存时长／字节／动态目标、读取状态与吞吐、实际解码器、帧率和 API 29+ 可用温控级别。它是诊断信号，不自动判定网络或硬解根因。MPV 在 info 记录启用时每 5 秒检查掉帧，缓冲／掉帧触发最多每 10 秒一条本地快照，6 项属性单次各限 250ms；采样和迟到结果绑定播放器与会话，退出／切集不污染新会话，不增加网络测速。
- Flutter MPV 与 Android Exo 分别通过 `PlaybackPerformanceTracker / NativePlaybackPerformanceTracker` 汇总同一组会话指标，并统一写入 `playback.performance`：首帧、缓冲次数与累计时长、恢复次数、速度 min/avg/max、片源码率及比值、解码器/硬解、掉帧、音频欠载和缓冲预算。首帧记录一次，会话切集、失败或退出时记录一次摘要
- Flutter 启动层额外记录 `targetResolutionMs / startupToFirstFrameMs`，用来把播放地址解析时间与播放器自身首帧时间分开；这条记录不增加网络请求
- iOS 原生播放器容器页使用 `AVPlayerViewController` 全屏承载播放，复用续播与系统字幕选择记忆；在线搜索到外挂挂载的闭环尚未完成，不提供双字幕、软硬解切换或字幕偏移
- iOS 原生播放器切集前从 `currentMediaSelection` 读取当前系统字幕选择，下一集的 legible group 可用后按语言与显示名称恢复；没有匹配项时回退全局自动字幕策略
- “从头播放”不再从历史构造临时目标。Hero 根据 `hasMatchedResource` 提供无参数解析回调，点击后 `DetailStartPlaybackResolver` 只接收当前详情：影片使用自己的播放目标（尚未补全时按来源 / 分区查找匹配资源）；系列按来源季列表顺序取最前面的季，再复用 `sortEpisodesForDetailBrowser` 选择最前面的可播放剧集；无季分组时直接排序剧集。起点不受历史、当前选中季或 S01E01 编号限制，目标集使用自己的直链、版本、请求头和字幕信息，统一设置 `allowResume=false`。续播回调直接返回 `allowResume=true` 的历史目标。两个回调共用启动锁、跳转和错误处理，解析中保持按钮挂载，失败后释放锁供重试；从头入口在所有内置引擎从 0 开始，不应用片头跳过
- 有续播目标时 Hero 操作顺序固定为“继续播放 / 从头播放”，继续播放作为 Hero 的默认 TV 焦点，并在操作区上方明确展示“上次播放：第 X 季 · 第 Y 集 · mm:ss”；系列详情加载出历史剧集后只滚动到该集，不把焦点从继续播放移走。播放版本仍限定在单集详情页，系列页的剧集卡片不新增版本弹窗
- Hero 从共享 `playbackMemorySnapshotProvider` 同步派生续播入口；“从头播放”只依赖已匹配资源，历史读取只控制自动首焦点和续播信息。操作行使用稳定 key，`DetailHeroContent` 维护共用启动锁，覆盖旧会话清理和播放器路由存活期，异常或返回后解除。
- 详情页初始化在恢复缓存、版本选择及按需刷新完成前不订阅 `enrichedDetailTargetProvider`，避免首帧补全与缓存恢复并行竞争；恢复失败时仍放行补全。种子目标改变时清理详情保留态，新目标立即生效，同一种子重载继续保留已有展示；系列保留态仅在系列请求身份变化时清理。
- 系列保留态单独按 `DetailSeriesBrowserRequest` 隔离，不随元数据对象变化清空；请求身份包含源、系列和分区 ID，不包含分区显示名。初始化读取共享播放历史，预载历史季而非固定第一季，浏览器按源、季和分区保存已加载季，不受分区显示名更新影响；剧集匹配优先播放身份，再在同源内按季集编号回退。首次水平定位使远端卡片被构建并滚动可见，但不请求焦点；手动切季取消待执行的初始定位，元数据重建不再次滚动。卡片进度同步派生自共享快照，避免每卡异步查询闪动。
- 详情页播放入口统一通过 `activePlaybackLaunchInProgress` 协调，Hero 按钮和剧集卡片共享同一启动锁，禁止清理旧会话或路由期间再次发起播放。详情页从播放器返回后保留系列浏览器的季选择、滚动位置和已加载季。
- iOS 的播放会话桥接由 `ios/Runner/PlaybackSystemSessionBridge.swift` 承担，`AppDelegate` 会把它绑定到 Flutter channel，用于原生播放会话、遥控器命令和 AirPlay 入口
- Android 系统播放器优先调用原生 `ACTION_VIEW`，并显式标记 `video/*`
- 桌面端系统播放器通过临时 `.m3u` 交给系统默认视频应用
- 重型视频不会再因启发式规则自动改变播放器路径；内置 MPV 仅在当前会话内按片源调整缓冲与解码参数
- 内置 `MPV` 会跟随设置切换解码模式；系统播放器无法稳定回传进度，且解码方式由外部播放器自行决定，因此续播记忆只在内置 `MPV` 和 App 内原生播放器里生效
- 自动跳过片头片尾、结束边界前 30 秒预解析下一集和直接切集均支持非 Web 内置 MPV 与 Android Exo；iOS AVPlayer 不参与这条应用层自动跳过链路。
- 字幕偏移当前支持内置 `MPV` 与 Android 原生播放器的外挂字幕链路；iOS 原生播放器暂未提供字幕偏移

播放器默认偏好目前包括：

- 最大打开超时时间
- 解码模式
- 默认倍速
- 字幕默认状态
  - `默认开启`：打开视频时按全局“默认字幕”自动选轨
  - `默认关闭`：打开视频时默认不显示字幕
- 主字幕大小、主字幕位置、副字幕位置和副字幕大小
- 字幕默认项在设置页中以单独的“字幕”二级页承载，避免和播放内核、后台播放、默认倍速混在同一层
- 后台播放
  - 设置中提供独立开关
  - Android 手机：开启后播放中切后台时允许进入画中画继续播放；Android TV 原生播放器保持全屏，不启用画中画
  - iOS：开启后播放中切后台时启用后台音频会话；内嵌 `MPV` 与原生 `AVPlayer` 都会保存当前视频轨并切到纯音频，回到前台再串行恢复原轨，切轨失败不会打断正在播放的音频；关闭开关时原生播放器也会随 App 进后台暂停
  - 关闭开关时两条 iOS 播放链路进入后台都会暂停、释放音频会话、清除 Now Playing 并撤销锁屏遥控入口；回前台重新发布暂停状态，避免锁屏绕过开关恢复播放。前台系统媒体会话不受后台续播开关影响
  - iOS 原生播放器关闭 `AVPlayerViewController` 的自动 Now Playing 发布，统一由 Starflow 同步播放状态和鉴权海报；开启后台播放时生命周期通知只保存进度和管理视频轨，关闭时进入后台会撤销 Now Playing、回前台恢复
  - iOS 两条播放链路都会记录中断前播放状态，只有系统允许恢复且中断前正在播放时才自动继续；暂停和耳机断开会释放对应的共享音频会话持有者。锁屏停止命令被禁用，原生播放器按真实倍速发布进度
  - 内嵌 `MPV` 的 Now Playing 位置在后台按 `10` 秒节流，非位置状态仍立即同步；封面加载器拒绝超过 `8 MB` 的响应，并用 ImageIO 在后台线程将图片降采样到最长边 `1200 px` 后再创建 `MPMediaItemArtwork`
  - Now Playing 封面接收有序候选，按海报、背景图回退并保留各自鉴权头；Emby 与 NAS / WebDAV STRM 的播放地址解析使用原目标 `copyWith`，避免解析后丢失图片、标题标识和其他展示字段
  - 用户主动关闭播放器时始终停止播放；后台保活只对应按 Home 或切换 App，关闭开关或切新片源也会清理当前 `MPV` 会话
- 播放器内核

## 11. 设置与配置管理

`SettingsController` 负责读取和持久化 `AppSettings`。

### WebDAV 配置与收藏同步

- `WebDavSyncSettingsPage` 提供独立网络同步入口，复用 TV 输入、按钮和设置页面骨架。连接及开关复用 `SettingsAutoSaveCoordinator` 自动本地保存，以 JSON 指纹去重，250ms 合并连续输入，返回／销毁前冲刷；网络操作等待保存队列完成，保存失败则停止。载入与下载后的表单回填不反向保存旧草稿。移除独立保存按钮，上传 / 下载前仍确认覆盖范围，操作期间禁止重复提交和返回。自动保存不触发 WebDAV 请求。
- `WebDavSyncConfig` 位于 domain 层，作为可选 `AppSettings.webDavSync` 子对象持久化到统一配置；地址、目录、Basic 账号、范围和自动开关随 JSON 导出及导入恢复。`WebDavSyncPreferences` 的应用内实例委托 `SettingsController` 读写并发布连接变更事件，不单独写额外键。导入按当前配置直接替换。密码以明文随备份导出，不是系统钥匙串；收藏文档仍不包含配置。
- `WebDavSyncService` 只负责 WebDAV 协议及快照编解码，复用统一 HTTP 客户端。版本 1 的 `starflow-sync.json` 包含可选的配置和收藏；配置继续校验当前 schema，收藏最多 200 条。
- 连接测试返回 `WebDavConnectionTestResult`，区分同步目录可访问与子目录待创建。仅当子目录 PROPFIND 返回 404 时再探测基础地址；基础地址 404 提示 WebDAV 接口地址无效，认证／重定向／服务端错误继续失败，不降级为“待创建”。测试不 MKCOL、不上传文件，也不承诺写权限。实际上传或收藏首次写入复用 `ensureDirectory`：每级 MKCOL 后以只读 PROPFIND 验证同源、匹配路径的成功 DAV collection 属性，创建成功状态及 405 均需验证，未确认目录则停止后续文件操作；不创建配置基础地址之外的父目录。协议层记录不含凭据和正文的 `sync.webdav` 响应日志，并在失败提示中区分目录创建、验证及文件读写阶段。
- 下载先完整解析、校验所选数据，再经 `SettingsController.replaceAllSettings` 应用配置及其缓存清理逻辑，经 `SearchPreferencesRepository` 保存收藏。两个存储写入不是跨仓库事务，设备写入失败可能部分完成；错误会显示，用户可重新下载。搜索及收藏页重新激活时读取最新收藏。
- 手动上传先读取远端，保留未勾选部分；ETag 可用时使用 `If-Match`，新文件使用 `If-None-Match: *`。手动模式服务器未提供 ETag 时无法保证多设备并发覆盖检测。配置仍只手动定向覆盖。
- `FavoriteSyncDocument` 定义独立版本 2 收藏文档，各设备固定保存为 `starflow-favorites-<设备ID>.json`。条目以既有 `searchResultFavoriteKey` 标识，成员 generation 与关键元数据 revision 分离；合并先比较成员版本、相同版本删除优先，再比较元数据逻辑版本和随机 operation ID，最终相等时仅比较精简字段。显式重新收藏递增成员版本；海报和其他展示缓存补全保留 generation、revision、operation 与排序位置，只更新本机数据。`mergeAll` 对全部设备及本机记录合并后才验证总容量，避免中间结果尚未应用删除记录就误报超限。删除记录保留且暂不回收，活跃条目超 200 或总记录超 20000 则拒绝写入，不静默截断。
- `favorite_sync_payload.dart` 以白名单定义同步结果：标题、链接／提取码、收藏文件夹、来源与媒体 ID，以及精简的 `MediaDetailTarget / PlaybackTarget` 导航标识、路径、季集、播放地址和实际播放鉴权头；容器、音视频编码、尺寸、码率及文件大小参与播放选择、缓冲预算或字幕匹配，因此保留。海报／背景／Logo／图片列表及图片鉴权、简介、评分、演职员和本机字幕路径等不在云端载荷中。空字段省略，字符串映射按键排序但保留显式空 header 值；无链接且无详情入口的收藏不保存简介。`encodeForSync` 用于上传、差异比较和读回验证；默认 `encode` 继续保存完整本地文档，不更改手动 `starflow-sync.json` 备份格式。搜索／收藏条目隐藏空简介与空标签，精简条目无需伪造展示数据。
- `SearchPreferencesRepository` 使用上述文档；列表和删除记录用同一个偏好键原子保存。写入队列串行处理单条增删、海报更新和远端合并；同步提交时再次读取最新本地记录，避免请求期间的修改丢失。合并后用 `withLocalPresentation` 为仍存活的条目保留本机展示缓存，关键字段仍采用获胜记录（含显式清空）；嵌套详情身份不匹配或播放地址变化时不复用不匹配缓存，删除条目不会恢复。新设备缺图复用既有 `SearchFavoriteMetadataService`，不为同步增加元数据请求。清空收藏也记录删除。格式损坏不回退空列表后上传，读取失败会阻止同步。
- 同一仓库通过 `loadFavoriteSyncDeviceId` 在写入队列中加载／生成 128 位随机设备 ID，以 `search.favoriteSyncDeviceId` 单独持久化；仅实际同步时使用，保存失败会停止同步。该 ID 不属于应用配置或收藏正文，导出／导入配置不复制设备身份，清空收藏也不重置；卸载／清除应用数据可能产生新 ID。此为安装身份，不是硬件识别或多进程锁，整份应用数据克隆及同一存储的并行客户端不具备独立写入身份。
- `FavoriteAutoSync` 只依赖收藏仓库、同步连接偏好与 WebDAV 服务，绝不调用 `SettingsController`。由 `StarflowApp` 保持运行，启动只加载连接偏好和订阅事件，不发起同步。收藏页导航进入调用 `onFavoritesPageEntered`，服务内的运行期标记在首次进入时、异步等待之前置位，之后重进／页面重建／配置重载均不重置；首次未开启或失败也算已进入。新一次 App 运行才重新获得首次进入机会。仓库成功增删的 `favoriteMembershipChanges` 仍触发自动同步。`favoriteChanges` 仅供列表刷新，海报／元数据写入和远端合并不触发同步。没有计时器、延迟防抖、轮询或失败自动重试，连接设置保存只重载配置，恢复前台不触发同步。
- 同步采用单飞任务，进入页面或手动重复调用复用在途任务；同步期间新发生的增删最多合并为一次立即后续同步。配置变更或离开前台后旧请求结果不再应用，已发出的请求可能完成。失败保留本地修改并等待新的有效事件或手动点击，不安排定时重试。
- 自动同步开关默认为关且独立于手动收藏范围；启用需确认并保存。自动模式下 UI 禁止手动覆盖收藏，以免旧快照影响合并。同步只读取当前设备文件格式，不隐式导入 `starflow-sync.json` 手动备份。更换服务器／目录会将当前本机文档（含删除记录）与新位置合并，不重置本机收藏或设备 ID。
- 收藏按设备单写者同步：`readFavorites` 只列举和读取当前设备文件格式，返回各设备文档与本设备远端文档。调用方将所有文档与本机合并，只有非空记录的关键编码不同才上传；已同步文件不因本地海报变化反复写入。设备文件缺失时先 `ensureDirectory`，随后只 PUT 本设备路径，不使用 ETag 或条件头。每次 PUT 后通过 `verifyFavoritesWrite` 重新 GET，按同步编码检查读回文档能涵盖本次上传记录，不要求云端包含本机展示缓存，通过后才合并本机并记录成功。缺失文件、无效内容或丢失变更均失败并保留本地数据。成功同步后的仓库事件实时刷新活跃搜索／收藏页，后台页面激活时重载；状态及本次运行上次成功时间供设置页显示。收藏页右上角使用固定尺寸 `StarflowIconButton` 显示手动同步（含 tooltip、TV focusId、忙碌禁用与完成消息）；自动开关关闭时也可手动合并，不改变开关值。页面导航可见性与 App 生命周期分开判断，避免恢复前台冒充进入收藏页。
- 设备发现使用同步目录 `PROPFIND Depth: 1`，只接受同源、直接子路径、严格设备文件名及成功 DAV 属性；目录本身也须确认为 collection。目录 404 可等待首次写入创建；列出的设备文件 GET 404、认证失败、无效正文／属性则停止，不将失败当空收藏。即使目录缓存遗漏，仍直接 GET 本设备文件；最多列出 100 份设备文件，本次读取正文合计上限 16 MB。不会使用 DELETE、ETag 探测或新增定时重试；每次同步读取并合并已有设备文件，只更新本机那一份，其他设备与删除记录暂不自动清理。分离路径避免不同安装同时覆盖，服务器保存可靠性及目录／正文的最终可见性仍是必要前提；其他设备新变更等下一次触发再收敛，不承诺实时一致。
- `FavoriteSyncTrigger` 区分 `firstEntry / membershipChange / manual / requested`，只记录既有调用来源，不添加新触发。`sync.favorites` 记录开始、成功、失败阶段（含 `device / verify`）、读取的设备数量或过期结果丢弃；`sync.webdav` 为设备文件 PUT 记录 `writeMode: device`，验证失败记录 `readbackMismatch`，不记录收藏正文、账号密码或任意异常正文。
- 收藏同步图标显式开启 `StarflowIconButton.focusableWhenDisabled`，通过描边控件传给 `TvFocusableAction`：TV 忙碌期间保持原焦点节点可聚焦，但 `onPressed` 仍为 null，不响应重复确认；方向导航继续生效，完成不主动 requestFocus。该选项默认 false，其他按钮及非 TV 触摸禁用行为不变。

当前设置范围包括：

- 媒体源
  - `WebDAV / Quark` 的目录结构推断、本地 sidecar 刮削、顶层推断目录与“剧集只按剧名层级搜刮”
- 搜索服务
- 搜索来源
- 豆瓣账号
- 首页模块
- Hero 来源、展示方式、Logo 标题与背景图
- 网盘与转存
  - 夸克、115 各自的登录凭据与保存目录
  - 各网盘独立的同步删除开关与 `WebDAV` 监听目录
  - 当前夸克保存目录管理与删除
  - 公共 `SmartStrm` Webhook 与 `STRM` 触发等待时间，各网盘页独立的任务名与测试
  - 自动增量刷新索引的媒体源选择与“索引刷新等待时间”
- 网络代理
  - HTTP 代理服务器与端口
  - 可选 Basic 用户名和密码
  - localhost、私有 IP 与 `.local` 地址直连
  - 真实 HTTPS 连接测试
- 元数据匹配
- 媒体源管理内的详情页匹配来源
- 播放超时
- 解码模式
- 后台播放
- 字幕默认状态与默认字幕
- 默认倍速
- 主字幕大小、主字幕位置、副字幕位置、副字幕大小
- 在线字幕来源
- 各在线字幕来源的专属配置（`ASSRT Token / OpenSubtitles 账号密码 / SubDL API Key`）
- 在线字幕优先语言（`简体中文 / 繁体中文 / 英语 / 日语`，可多选；不选时按字幕结果和系统语言自动处理）与单次最多结果数（保留旧存储键，不进行搜索期验证）
- 播放器内核
- 简化界面特效（关闭透明磨砂并减少装饰）
- 减少界面动画（减少动画并使用静态导航切换）
- 简化首页 Hero（静态与精简效果同步）
- 精简详情 Hero 与精简播放界面（仅 TV 固定启用，不保存用户开关）
- 激进 MPV 调优
- 自动隐藏菜单栏
- Hero 全屏背景图
- 自动更新卡片信息（非 TV）
- 启动时自动刷新首页，以及是否同时刷新 Emby 媒体源
- 首页、元数据、Emby 与 NAS / WebDAV 共用的最大并发任务数
- 首批元数据预取数量、元数据后台批次间隔与交互结束后恢复时间
- 首页首批优先模块数与后台批次间隔
- 本地日志开关、容量、记录级别与预览级别

播放设置在页面结构上额外做了分组：

- 播放页放播放器内核、解码模式、ExoPlayer 音频输出、打开超时、后台播放、默认倍速
- 字幕收拢到独立的“字幕”一级页：字幕默认状态、默认字幕、主字幕大小、主/副字幕位置、副字幕大小、在线字幕来源与凭据、在线字幕优先语言、单次最多结果数
- 主字幕大小、主字幕位置、副字幕位置和副字幕大小属于全局字段；设置页的步进项每次点击立即入有序保存队列，MPV 播放内修改走 `savePlaybackRuntimePreferences(...)`，Android 原生播放内修改经 Flutter 回调走 `savePlaybackSubtitleStylePreferences(...)`，三条路径最终写同一组 `AppSettings` 字段
- 主/副字幕位置统一使用 `50%–100%` 范围；设置页使用 `1%` 步进，MPV 播放内“更多”使用 `5%` 步进。Exo 的 `NativePlaybackNumberPicker` 使用加减按钮与原生 `SeekBar`，并支持整数或小数步长：主字号 `20–78`、主/副位置 `50–100`、副字幕大小 `50–120` 均以 `1` 为步长，倍速 `0.75–2.0` 以 `0.05` 为步长，外挂字幕偏移 `-30s–+30s` 以 `100ms` 为步长。遥控器左右键及按键重复由 SeekBar 处理；打开时不写入设置，每次实际变化由对应控制器立即应用并走既有保存回调，完成/返回不回滚。字幕偏移连续输入按 `250ms` 合并后重建字幕，避免滑杆拖动时反复创建媒体项。弹窗在 `show()` 前设置顶部 gravity 并清除背景变暗，显示后的回调只申请滑杆焦点，因此首帧就位于顶部且不会从中央跳动；关闭仍走 `showTransientDialog` 恢复焦点。设置页和 MPV 的副字幕大小仍为 `5%` 步进
- Exo 的 `NativePlaybackSubtitleStyleController` 保存现有 `SubtitleView` 的原视频比例父容器；文本字幕挂入 `PlayerView.overlayFrameLayout`，覆盖整个窗口及黑边，PGS 等位图 cue 则挂回原视频比例区域，保留视频平面的原始坐标和尺寸。`NativePlaybackCoordinator.onCues` 按非空 cue 是否含位图更新父容器，空 cue 只清屏、不在字幕间隙和 seek 时来回迁移；重复样式应用保持当前坐标区域，切回文本恢复全窗口定位。继续使用同一个 SubtitleView 和 Media3 的 cue 更新，不增加第二个字幕 renderer。`NativeSubtitlePositionPolicy` 将文本位置完整映射到 `0.5–1.0`，普通文本 cue 清除内嵌垂直 line 后使用 `0–0.5` 底部留白，保留其余样式和位图 cue；双字幕使用 `ANCHOR_TYPE_END` 使主/副字幕块底边分别对齐所选百分比。`100%` 不再被截到 `95%` 或强制保留 `5%` 底部安全区；字体自身的字面留白仍由 Media3 排版决定
- 内置 MPV 的触屏交互、卡顿自动恢复和激进性能调优保留在全局设置的独立“MPV”一级页；播放器内的播放设置一级只提供“更多”入口，二级页复用同一组持久化字段，并额外集中提供后台播放与主/副字幕布局
- 三个页面都不再维护需要手动提交的页面草稿：选择、开关和步进项修改后立即排入持久化队列，文本输入使用 `250ms` 合并窗口；返回时会先把最后草稿加入有序写入队列，再立即关闭页面，不再显示保存确认框或工具栏提交按钮
- 三个全局设置页各自只写自己那段字段：播放页走 `savePlaybackPreferences(...)`、字幕页走 `savePlaybackSubtitlePreferences(...)`、MPV 页走 `savePlaybackMpvPreferences(...)`；播放器内二级“更多”使用 `savePlaybackRuntimePreferences(...)` 原子保存其当前完整快照，避免连续操作互相覆盖
- 媒体源、搜索服务、豆瓣账号、网盘与转存和网络代理编辑页复用 `SettingsAutoSaveCoordinator`：以当前配置 JSON 作为指纹去重，连续修改使用 `250ms` 防抖并按队列顺序持久化，返回时立即冲刷最后草稿，删除前取消尚未开始的保存，避免删除后被旧任务重新创建
- 媒体源资源身份由类型、endpoint / 根目录及服务端资源身份字段组成；删除来源或改变资源身份时先持久化新设置，再提升来源失效版本、等待旧扫描结束并清理来源级缓存，防止旧任务在清理后反写
- 本地、文件和局域网导入在落盘前统一调用媒体源引用协调：移除不存在来源的首页模块、匹配/搜索来源、同步目录和刷新目标；可确认相对目录的新地址会保存到当前媒体源根，无法确认的旧引用不会继续使用
- 整页编辑不再保留保存按钮或未保存确认；单个文本输入弹窗里的“保存”仍只负责把该输入提交回当前草稿。新建媒体源/搜索服务在草稿没有实际内容时不会生成空记录
- 详情页资源信息区对播放器内核的切换会直接复用同一个 `setPlaybackEngine(...)` 写回入口，因此不会出现“详情页一种默认、设置页另一种默认”的分叉
- `AppSettingsPerformanceX` 只负责平台固定规则和少量有效值派生；独立子项不会因其它开关数量变化而自动联动
- 设置反序列化只读取当前独立性能参数；旧高性能标记、旧 Hero 开关/模块别名和旧 IMDb 自动匹配字段不再转换
- 搜索源只保存搜索服务字段；旧搜索源里的夸克、保存目录和 SmartStrm 字段不再读取，相关配置只以 `networkStorage` 当前结构为准
- 本地、文件和局域网导入都要求设置 JSON 明确包含 `schemaVersion: 3` 和完整当前字段；本地键为 `starflow.settings.v3`，不匹配时直接拒绝导入或回到默认设置，不执行跨格式迁移
- “自动更新卡片信息”默认可在普通端按需开关；`TV` 端固定关闭，设置页不显示重复开关

设置编辑页在 TV 下还额外做了输入方式分流：

- 文本项优先显示为可聚焦设置条目
- 需要编辑时再进入独立弹窗输入
- 避免页面级 `TextField` 长时间占据焦点并把遥控器操作锁在系统键盘里
- 媒体源、搜索服务、豆瓣账号、网盘与转存、播放、配置管理等主要设置页，当前尽量共用同一套页面骨架和按钮分类，减少页面间的操作分叉
- 搜索来源、匹配来源等多选项当前统一复用同一套复选弹窗；`TV / 触屏` 共享一套选择流程与焦点逻辑
- `WebDAV` 路径选择页会缓存目录 Future，避免同一目录在页面重建或来回切换时重复列目录
- 三组界面简化开关、自动隐藏菜单栏、Hero 背景图和运行时局部更新分别保存，不再由统一性能档位批量套用或恢复
- `TV` 端把“自动更新卡片信息”固定为关闭且不展示开关，避免焦点浏览和滚动过程中被后台缓存更新继续唤醒局部 provider 链路
- 首页、搜索、设置页以及部分壳层组件已经开始改成 slice provider 订阅；高频页面会优先只读取需要的设置片段，而不是整份 `AppSettings`

播放器运行期状态还会额外保存：

- 最近播放
- 电影续播进度
- 电视剧当前集与集内进度
- 按剧绑定的片头 / 片尾跳过规则

设置页还提供：

- 本地缓存查看与清理
- 当前会按“媒体资料 / 使用记录”分组展示
- 当前清理项包括 `WebDAV` 索引、详情缓存、字幕缓存、播放记忆、`TV` 搜索历史与来源记忆、图片缓存
- “媒体库索引”清理同时取消索引任务并失效 Sembast、持久化 WebDAV 目录快照、WebDAV 客户端内存缓存与 `NasMediaIndexer` 聚合缓存
- 在支持文件访问的平台上导出配置到 JSON
- 在支持文件访问的平台上从 JSON 导入并覆盖当前设置
- 所有设置导入入口只接受当前 `schemaVersion: 3` 和完整当前字段，旧格式不会做字段映射或补迁移
- Web 端会直接触发浏览器下载 JSON，并支持选择本地 JSON 立即导入覆盖
- iOS / iPadOS 导出当前改走系统文件导出器，会直接弹出原生保存面板，可保存到“文件 / iCloud / 本机其他位置”
- iOS / iPadOS 导入继续走系统文件选择器
- `TV` 模式下改为应用内局域网配置传输
- 会启动一个临时本地 HTTP 服务，并在电视上展示访问码、端口与局域网地址
- 手机与电视连接同一网络后，可直接下载当前配置或上传 JSON 覆盖本机设置
- 关闭传输弹窗后会立刻停止该临时传输服务，不保留后台进程
- 独立的日志二级页：固定区域预览、按级别筛选、刷新、清理和导出
- TV 日志导出与配置传输共用局域网地址卡片和二维码交互；手机扫码即可打开当前会话页面

Android TV 下的设置页还额外做了遥控器适配：

- 设置首页主要入口卡片支持焦点选中
- 多个二级设置页的主要按钮支持焦点可达；整页设置采用自动保存，不再提供单独的保存焦点目标
- iOS 的设置路由保留平台原生转场和边缘返回手势；TV 与其他平台继续使用零时长设置转场。WebDAV 目录选择页的返回只取消本次选择，“选这里”才返回新目录
- 二级、三级设置页面的页头统一只渲染标题；页级说明文字已移除，条目级 subtitle 与必要的操作提示继续由具体组件承载
- 长列表沿用默认方向寻焦与可见性滚动，不强制每次居中；首页及选集等需要居中的路径由各自组件显式处理
- 媒体源、搜索服务、豆瓣账号、网盘与转存等编辑页里的文本项会先显示成可聚焦条目，再进入独立编辑弹窗
- 播放、界面与性能后台页面从一级分类直接进入，每页首个条目具有明确 TV 初始焦点
- 多数设置编辑页统一标题栏、自动保存、危险操作和选择条目样式；整页不保留手动提交按钮，输入弹窗的“保存”只提交该字段
- 公共按键去重、文本编辑及二级页缺焦恢复的核对范围与真实遥控器／输入法复测项见 [TV 焦点清单](tv-focus.md)

## 12. 本地持久化

### SharedPreferences

配置加载的解析失败与存储 IO 失败分开处理：损坏 payload 仅在内存降级，原始记录与本地凭据保留；Cookie 读取或来源引用协调保存异常向上传递，不通过保存默认配置覆盖有效数据。多个偏好键的保存不是跨键事务，这项修复不声称设备断电期间具备原子提交能力。

用于保存：

- 应用设置
- 当前设置 payload 使用 `starflow.settings.v3`，并要求 `schemaVersion: 3`
- 代理配置作为 `networkProxy` 子对象保存在同一 payload 中；缺少该对象时设置无效
- Emby 本地库缓存的 `v2` manifest、来源 summary / fallback shard 与 section shards
- 详情缓存
- 详情缓存里的完整本地资源候选列表与当前选中候选；UI 会由它恢复来源选择及当前来源内的播放版本
- 详情缓存里已经刮削、手动更新或手动关联后的标题；首页、媒体库和详情页会优先读取它作为展示名
- 对存在多个来源或播放版本的详情页，会保留当前选中的来源/版本组合，包括影片和单集等叶子项
- 对剧集详情页，恢复已缓存的本地资源状态时还会一起保留剧集结构上下文，避免再次进入后丢掉季/集浏览
- 播放历史
- 续播进度
- 按剧绑定的片头 / 片尾跳过规则
- `TV` 搜索历史与搜索来源记忆

详情缓存当前不是按整个来源粗粒度失效：

- 删除单个 `WebDAV` 资源时，只移除该资源对应的详情关联键和匹配关系
- 删除目录时，按目录作用域移除相关详情关联
- 其他来源或其他资源的详情缓存不会被一起清掉

### 应用支持目录

用于保存：

- 当前不再为在线字幕保留长期副本
- `logs/starflow.log`：当前结构化应用日志
- `logs/starflow.previous.log`：上一份轮转应用日志
- `logs/starflow-native.log`：Android 原生生命周期与上次异常退出日志
- `starflow-native-logging.json`：供 Android 原生日志读取的开关、容量和级别配置

### 临时目录

用于保存：

- 点选下载并验证后的在线字幕 `starflow/online_subtitles/download-*`；每次下载生成新目录，不复用旧链接
- 字幕缓存统计、清理和保留期只覆盖当前 `starflow/online_subtitles/download-*`，旧式验证缓存不属于当前缓存

### Sembast

用于保存 `WebDAV` 元数据索引。指定分区的读请求会在 Finder 层组合 `sourceId + sectionId` 条件，只把目标分区记录交给 Dart。

### 持久化图片缓存

通过 `persistent_image_cache` 抽象统一访问，不同平台走各自实现或 stub。

当前图片缓存策略已经补齐这些约束：

- identity 按 `URL + 归一化 headers` 区分，避免不同鉴权请求误命中同一份缓存
- 磁盘层会保存 metadata，并按 `30` 天 TTL 做过期判断
- 远端失败但本地还保留旧字节时，会优先回退到 stale bytes，减少短期网络抖动导致的图片缺失
- 单次网络读取最多等待 `15s`；组件在全部候选失败后按 `1s / 4s / 12s` 重试，失败与恢复分别写入 `image.load` 日志
- IO 平台的图片网络读取遵循运行期代理配置；Web 端仍由浏览器网络栈和 `STARFLOW_WEB_PROXY_BASE` 开发转发入口决定
- raster 解码失败会同步从 Flutter image cache 与持久化缓存中淘汰对应条目，下一次重试重新请求原图
- 内存层按条目数和字节预算双阈值淘汰，尽量减少重复 decode
- 详情 Hero 可选择 gapless playback：替换图片源时保留上一张已解码 raster 到新图就绪，避免元数据或缓存回写造成背景闪空

## 13. 平台分支

项目有一层明确的平台适配：

- `StarflowApp` 在 `MaterialApp.router.builder` 内挂载 `MobileTextInputDismissal`，仅 Android / iOS 非 TV 覆盖 `EditableTextTapOutsideIntent`，取消对应输入框焦点以收起键盘。复用 Flutter 的输入区域判定，不拦截按钮手势；提交、下一项、多行换行仍由 `EditableText` 默认处理。覆盖路由和弹窗，不接管原生播放器 UI 或 TV 的编辑／返回焦点规则。
- Android 会识别 `TV` 设备
- TV 模式切换为左侧窄栏磨砂菜单和焦点式交互
- 左侧菜单是否自动隐藏由设置控制；开启后启动进入页面和切换分支都会先把菜单隐藏，页面 autofocus 成功后焦点自然落到内容区。焦点离开菜单时同样由菜单焦点范围直接同步显隐，而不是监听全局焦点后延迟推断；隐藏中的菜单会被排除出寻焦树，已聚焦菜单则不会压缩成零宽布局
- 设置首页及部分设置子页会优先使用更适合遥控器操作的可聚焦按钮与入口
- Android 主清单显式声明了 `INTERNET`、`ACCESS_NETWORK_STATE` 和明文流量支持，保证 TV 端能访问局域网与在线元数据资源
- Android 最低兼容目标固定为 `API 23 / Android 6.0`；发布锁定 Flutter SDK 并检查原生库构建标记/强符号，不能单凭 manifest 声明证明实际兼容，仍需 API 23 真机验收。
- Release APK 当前启用了 `v1 + v2` 签名，兼容老一些的电视安装器
- Release 必须显式恢复既有签名并通过固定指纹检查；设备已有不同签名的 `com.example.starflow` 时不能覆盖安装。历史安装身份为 Android Debug 证书，不能随意换 key 后声称可升级；卸载前先分别备份应用配置和直播数据。
- `TvMenuButtonScope` 用来把菜单键语义统一上抛到页面壳
- `TvDirectionalFocusBoundary` 处理方向越界，页头／Hero 路径由页面显式动作负责；不存在单独的 `TvReturnToTopScope`，普通候选仍由 Flutter 默认策略决定
- 首页、搜索、媒体库、详情与设置页不再挂载空的焦点记忆作用域，也不做坐标校验或反向候选拦截
- 首页 Hero 的翻页焦点只会请求已挂载且可用的按钮；单项 Hero 按左直接回到主菜单。媒体库首页则只让顶部筛选项申请初始焦点，异步加载的合集与网格不再竞争首焦点
- `TvFocusableAction` 不自行调度居中滚动，普通遍历遵循 Flutter 可见性策略；首页恢复和选集等业务路径单独定位
- `TvFocusableAction` 使用自身 State 更新焦点外观，海报使用局部 ValueNotifier；TV 轻量描边不否定控件显式缩放和 chip 自有阴影
- `SettingsTextInputField` 会在 TV 模式下把页面内文本输入改成“设置条目 + 弹窗编辑”交互；弹窗输入框局部保留上下键退出处理，减少焦点被输入法占据的情况
- 配置管理当前按平台分支：
  - Android TV 使用应用内局域网传输
  - Web 使用浏览器下载和本地文件选择器，不需要手填路径
  - iOS / iPadOS 使用原生系统文件导出器与文件选择器
  - 其他 IO 平台继续使用目录 / 文件选择器
- IO / Web 平台对本地数据库、图片缓存、配置导入导出各有分支实现

启动等待与启动界面：

- `BootstrapController` 在原有首页预热/刷新调度后调用 `waitForHomeModules`，并发等待所有已启用模块的 `homeSectionProvider.future`（包括缓存整理）；各模块失败独立处理，5 秒超时由启动阶段降级逻辑放行。此等待仅用于启动，不改变首页手动刷新行为，也不等待海报解码或全库扫描
- `BootstrapController.start()` 使用单个 `10s` 总截止计时器覆盖所有启动阶段，正常完成时提前取消，provider 销毁时取消并释放等待；配置读取 `3s`、首页模块 `5s` 阶段上限保持不变。总超时标记启动完成并记录 `app.bootstrap` 本地警告（阶段、超时毫秒数），不取消底层已发出的异步操作；各异步边界检查 provider 存活与启动完成状态，迟到成功/失败不覆盖完成状态、不继续触发后续阶段或重复首页刷新。此上限从 Flutter 启动编排开始计算，不覆盖原生初始化或主线程同步阻塞

- 各平台应用显示名称、Web 安装名称及桌面窗口标题统一为 `Starflow`；平台包标识保持不变，macOS 产品名称与 Xcode scheme、测试宿主路径同步为 `Starflow.app`

- 原生启动背景由 Android `launch_background.xml`、Android 12+ `LaunchTheme.windowSplashScreenBackground` 和 iOS `LaunchScreen.storyboard` 管理，均与 Flutter `BootstrapPage` 保持 `#121212` 一致；Flutter 启动字标使用白色与浅灰色，不再使用蓝色渐变背景
- 原生启动页只保留背景：Android 的 layer-list 不加载位图，Android 12+ 显式使用 `transparent_splash_icon`，iOS storyboard 移除 LaunchImage 视图及其约束。Flutter 初始化流程保持不变；导出链保留的原生启动图片当前不参与展示
- Flutter `BootstrapPage` 的 Logo 和字标始终静态显示，固定大小、位置与不透明度，不执行淡入、缩放、位移或循环动画；不订阅启动进度或减少动画设置来驱动视觉变化。启动完成由独立的状态监听注册帧后首页跳转，并调用 `ensureVisualUpdate()` 主动请求帧，避免静态页面在 release 模式空闲时一直等待回调；跳转前仍检查 `mounted`

平台外部图标资源统一走同一条导出链路：

- Android、iOS、macOS、Web、Windows 的外部 App Icon 都由 `tool/generate_brand_assets.py` 生成
- Android TV Banner 也由同一脚本生成
- 启动页首帧图标、Android 启动页主图与 iOS 原生 LaunchImage 也由同一脚本同步生成，保留原图完整构图
- Android 启动器小图标与 TV 横幅里的 Logo 复用同一份 `assets/branding/starflow_logo_source.png`
- 小尺寸外部图标采用 Lanczos 缩放，不额外锐化；iOS 默认与深色模式 App Icon 都使用无透明通道的 RGB，深色外观由 `assets/branding/starflow_ios_dark_icon_source.png` 生成并在 Asset Catalog 中绑定
- 旧版品牌归档说明位于 `backups/branding/README.md`；历史 ZIP 是被忽略的本机产物，干净克隆可能不含该文件，不参与运行时打包
- 当前约定以 `build/brand_assets/starflow_app_icon_master.png` 作为统一母版，再缩放到各平台资源，避免手工替换时出现偏移或不对称

## 14. 测试覆盖

测试入口与各次执行快照见 [主机验证](performance.md)，真实显示、音频、网络和生命周期验收见 [设备性能](performance-device.md)。2026-09-20 早段 Flutter 全量通过，Android JVM 有一个选集外观源码断言失败和一个可选样本测试跳过；之后工作区继续变化，未重新全量验证。不要将下列“覆盖”理解为最新工作区或所有平台验收通过。

当前 `test/` 已覆盖的重点包括：

- 当前设置模型与序列化
- 首页装配逻辑
- 首页控制器与 settings slices
- 首页 / 媒体库详情缓存批量读取
- 详情缓存
- 页面级 `RetainedAsync` 保留态控制器
- `Emby / WebDAV` 客户端
- 飞牛协议、播放解析、转码会话、进度队列与迟到结果清理
- `WebDAV` 识别与索引
- `NasMediaIndexer` 分组、增量刷新和并发预算
- 空库自动重建后台调度
- 元数据客户端
- 搜索 provider 与搜索仓库
- 夸克保存和 `SmartStrm`
- 115 保存 / 同步删除、公共目录规划与名称清理、每设备收藏同步
- 播放记忆与最近播放排序稳定性
- 播放启动准备与路由判定
- 在线字幕协议、ZIP / 编码限制、缓存、语言契约及原生 cue 生命周期
- Android 音频策略、LPCM / PGS reader、单次音频回退及状态恢复（JVM，不等于 ARM 解码）
- 统一网络错误分类、超时、幂等重试边界与按主机熔断
- 本地日志轮转、脱敏、原生日志合并、预览与导出
- 首页模块和元数据预取的共享并发值及独立首批预算

## 15. 当前架构判断

这个仓库目前最重要的三个判断是：

1. `WebDAV` 的正确方向是“索引优先”，而不是“页面实时扫目录”
2. 详情页不是唯一元数据入口，索引阶段已经承担了大量 enrichment 工作
3. 搜索不是孤立功能，而是资源入库、`SmartStrm` 触发和自动增量刷新索引的上游触发器
