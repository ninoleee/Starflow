# Starflow 性能影响面梳理

> 历史审查与处理状态，2026-09-24 归档。本文保留修复前机制证据，不继续追记现行功能；现行边界见 [架构说明](../architecture.md) 和 [开发网络](../development-network.md)，后续验证见 [主机记录](../performance.md)。

核对日期：2026-09-20。范围为当前工作区，包括已有未提交修改；不是只审查 Git HEAD，也不是设备跑分报告。第 1-7 节保留首次审查快照（当时只新增本文），后续实现状态以本节处理表为准，旧问题描述不可当成修复后现状。

## 后续处理状态

用户随后要求实施优化。已修改代码与回归测试，未运行发布预设、未递增版本或交付 APK；没有真机数据，不声称全部影响面都已消除。

| 编号 | 本轮处理 | 保留边界 |
| --- | --- | --- |
| F01 | 播放不 join 后台取消；NAS PROPFIND 全程有界 | 旧播放器清理仍串行；扫描中止不保证立刻结束所有请求 |
| F02 | 四路整请求池、15s/32 MiB、abort、隐藏/销毁取消和共享持有者保护 | UI 租期与网络预算分离；排队不计入下载期限 |
| F03 | 256 条后台队列、1s 配置缓存、半容量尾部轮转 | 崩溃/会话标记同步兜底保留；native 与 Dart 清理不是跨线程事务 |
| F04 | 真实 16ms 合并、clear 顺序、dispose flush | 详情仍整份编码，不是逐记录数据库 |
| F05 | 仅修改命中 shard，未变 payload 跳写 | 仍需逐 shard 查找目标；两分区探针由 5 次写降为 2 次 |
| F06 | 冷读合并、128 条起后台排序/分组/查找表、回填状态检查 | 全源及各分区仍重建，尚无大库设备基线 |
| F07 | 构建信息异步、移除 150ms 人工等待 | 来源身份扫描、必要初始化及全模块等待保留 |
| F08 | 豆瓣模块隔离 NAS/库 revision | 首页根节点聚合监听仍需 profile 定位 |
| F09 | 图片严格并发、同页搜索跨查询共用池 | 未把独立调度器硬并为一个全局池，避免前台饥饿 |
| F10 | 查询源排队、旧排队任务跳过、筛选缓存、去掉验链逐条 setState、128 条后台打分 | 在途搜索不强制中止；来源仍逐批显示 |
| F11 | 冷历史读合并、大 JSON 后台编解码、iOS 原文缓存 | 不删 series/偏好，仍全量持久化 |
| F12 | 元数据 512 项 LRU、图片磁盘软限维护、异步 stat、分页 autoDispose、内存压力清图片字节 | 豆瓣解码例外和其他常驻缓存不盲目清除 |
| F13 | 预览每文件 2 MiB 尾读/后台解析、导出 BytesBuilder、Dart 日志批量与背压 | 导出仍完整 bytes，不宣称恒定内存 |
| F14 | 间接减少重建、缓存驻留与主 isolate 工作，增加帧分布观测 | blur/焦点布局需真机 profile，未统一降效果 |
| F15 | 去掉无关启动等待、降低日志和历史解析成本 | buffer/seek/解码/音频策略保留，待样本真机验证 |
| F16 | 字幕过期目录扫描每小时最多一次 | 双字幕/ASS/位图效果成本需设备采样 |
| F17 | 保留已实现的防抖/去重/串行同步与后台刷新 | 不删除确认/分页/一致性检查来制造提速；未改低频业务语义 |
| F18 | p50/p95、16.667/33.333ms 超预算数与原长帧告警并存 | 不是实际视频首帧或设备通过报告 |

实现契约见 architecture/development-network，当前验证见 performance；第 7 节测试数字仅属于原审查阶段。

组件边界以 [架构说明](../architecture.md) 为准，请求与代理边界见 [开发网络](../development-network.md)，主机计时口径见 [主机性能](../performance.md)，设备采集方法见 [真机性能](../performance-device.md)。源码行号只用于本次快照定位，后续应结合函数名查找。

## 1. 结论与优先级

目前最值得优先处理的不是文件体积或统一降低画质，而是三类额外工作：**前台等待后台退出、没有完整生命周期约束的在途请求、小变化触发大范围读取/重算/写入**。图片解码、模糊合成、播放器缓冲和音视频解码也影响性能，但需要在具体设备、媒体样本上权衡。

证据分为：

- **已复现**：用受控单元探针验证了等待关系或工作次数，不等于已经测出设备耗时。
- **代码确认**：执行路径和复杂度可以直接核对，尚未量化实际卡顿或资源峰值。
- **待测量**：存在明确成本，但其是否构成瓶颈取决于设备、数据规模和使用条件。

下表的 P1/P2/P3 是本次建议处理顺序，不是已经测定的卡顿严重程度。P1 优先处理无界等待和放大效应，P2 处理随库规模/使用时间增长的问题，P3 在基线明确后调优。

| 编号 | 影响面 | 当前判断 | 优先级 |
| --- | --- | --- | --- |
| F01 | 播放前等待 NAS 刷新完全退出 | 已解析地址仍受后台任务阻塞；探针已复现 | P1 |
| F02 | 图片正文超时、取消与并发 | 15s 只约束响应头，释放 TV 许可不终止下载 | P1 |
| F03 | Android 原生日志 | 调用线程同步读配置、写文件，满容量后逐条重写尾部 | P1 |
| F04 | 详情缓存写放大 | 只合并同轮微任务，跨事件 10 次更新产生 10 次全量写 | P1 |
| F05 | Emby/飞牛分片写放大 | 一个评分人数变化仍写全部分片，探针已复现 | P1 |
| F06 | NAS 索引 CPU 与冷读 | 增量落库后全源排序、分组、物化；大库风险 | P1，需大库采样 |
| F07 | 冷启动关键路径 | 首帧前串行初始化，启动协调扫描缓存，全模块等待 | P2 |
| F08 | 首页失效与重建范围 | 本地索引 revision 可影响无关豆瓣模块，根节点监听聚合状态 | P2 |
| F09 | 多调度器与在途任务 | 同一个并发设置不等于全应用只有两条请求 | P2 |
| F10 | 搜索 | 来源同时启动，主 isolate 打分/排序，验链仍逐条 setState | P2 |
| F11 | 播放历史 | 冷读不合并，series 无最近 20 条上限，持续全量序列化 | P2 |
| F12 | 图片/数据缓存生命周期 | 原图解码、磁盘无容量淘汰、多层常驻缓存 | P2 |
| F13 | 日志预览/导出 | 取最近 300 条仍全读全解析，导出内存合并 | P2 |
| F14 | Flutter 绘制与焦点 | 大面积 blur、动画、保留页面和焦点拓扑计算 | P3，真机确认 |
| F15 | 播放缓冲、seek、音视频解码 | 启动速度/稳定性/内存/画质之间的策略取舍 | P3，真机确认 |
| F16 | 字幕 | 解压/解码/样式及位图开销，已有较多边界保护 | P3，真机确认 |
| F17 | 设置、收藏同步、转存 | 用户触发的全量保存与串行网络链，区别于常驻轮询 | P3 |
| F18 | 性能观测 | 主机 smoke 不等于首屏，250ms 告警不能发现常规掉帧 | 与 P1 同步补齐 |

## 2. 优先处理的放大效应

### F01：播放启动被后台取消收尾阻塞

入口：[PlaybackStartupCoordinator.start](../../lib/features/playback/application/playback_startup_coordinator.dart#L33)、[NasMediaIndexer.cancelAllRefreshTasks](../../lib/features/library/data/nas_media_indexer.dart#L191)、[刷新取消标记](../../lib/features/library/data/nas_media_indexer_refresh_support.dart)。

- `start()` 首先 `await cancelActiveWebDavRefreshes(includeForceFull: false)`，即使 `targetAlreadyResolved=true` 也一样。
- 索引器的取消是设置标记，再 `Future.wait` 等待所有选中的任务结束；没有由该标记直接中止底层传输。`forceFull` 任务还不在这次取消范围内。
- WebDAV 目录读取在 [sidecar 实现](../../lib/features/library/data/webdav_nas_client_sidecar.dart#L294) 使用 `Response.fromStream` 收完整正文，该入口没有额外正文总期限或字节上限。慢在途请求可能拖住取消完成。
- [播放器初始化](../../lib/features/playback/presentation/widgets/player_page_startup_mpv.part.dart#L30) 还会等待旧实例清理；[MPV 开流 deadline](../../lib/features/playback/presentation/widgets/player_page_startup_mpv_open.part.dart#L13) 到开流阶段才赋值，不覆盖此前所有等待。

**已复现**：提供一个已解析的播放目标，取消 Future 未完成时启动始终不推进；手动完成取消后才继续。40ms 是实验观察窗口，不是实际最大延迟。

建议把“请求后台停止”和“等待后台全部退出”分开，提供真正的请求取消，记录点击、后台停止、地址解析、播放器创建、开流、首帧各阶段。不能简单并行释放/创建原生播放器，旧实例串行清理关系到解码器资源和避免叠音；需要给这些阶段明确的等待与失败策略。

### F02：图片下载的期限和并发边界不完整

入口：[StarflowHttpClient.send](../../lib/core/network/starflow_http_client.dart#L47)、[图片下载](../../lib/core/storage/persistent_image_cache_impl_io.dart#L296)、[TV 图片许可](../../lib/core/widgets/app_network_image.dart#L457)。

- HTTP 包装器对 `_inner.send()` 设超时，只等到响应头；`get()` 随后收集正文的时间不在其中。图片配置 15s，共享普通 API 默认为 20s，不能解释为所有请求全程有界。
- 图片先完整收集正文再校验，没有该入口自己的总下载期限或响应体大小上限。
- TV 栅格图名额是 4。组件在 4s 后释放许可，调度器另有 8s 自愈租期；释放许可或隐藏/销毁组件不会终止已经发出的 HTTP 正文读取。实际在途下载可能超过 4。
- SVG 不经过这道栅格图门；非 TV 的栅格图也没有同一门控。失败后的 1/4/12s 重试是另一层等待，需分清网络中止和 UI 放行。

**已复现**：设置 5ms 响应头期限，立即返回响应头后将正文保持打开 40ms，`get()` 仍未超时；补齐正文后正常完成。

建议在传输层统一计数在途图片，覆盖响应头与正文的总期限、累计字节和取消，组件租期只负责 UI 不被卡死。不能仅给 Future 加 `.timeout()` 就认定底层请求已中止，也不能套同一小容量上限到视频媒体流。字幕等入口已有独立总期限，不应被本条误判。

### F03：Android 原生日志可能阻塞播放器主线程

入口：[NativeAppLogger.log / appendRecord](../../android/app/src/main/kotlin/com/example/starflow/NativeAppLogger.kt#L145)、[NativePlaybackRuntimeController](../../android/app/src/main/kotlin/com/example/starflow/NativePlaybackRuntimeController.kt#L31)。

- `log()` 是 `@Synchronized`，在调用线程读取/解析配置，然后判断启用状态与等级；即使该条最终不记录，也已经读了配置文件。
- 正常记录同步构造 JSON、创建目录、检查长度、追加写文件。原生日志达到容量后，每条追加都读取整个旧文件并重写保留尾部，原生上限最高 4 MiB。
- `takeLast(...).toByteArray()` 还会制造临时集合。`forceSync` 和播放会话标记路径执行 `fd.sync()`。
- 播放运行控制使用 main looper，诊断日志可从这一链路调用；应用启动安装原生日志及历史退出捕获也有同步工作。不是所有日志都每秒写，但慢闪存、日志接近容量、密集故障会放大成本。

建议缓存配置，使用有界后台写队列和分段轮转，避免满文件后逐条重写；保留崩溃等关键记录的最小同步兜底。验收应覆盖快满/满日志和连续错误，而不只测试空文件。

**结构化日志、Android 原生退出捕获、预览、筛选、清理和导出都处于有效实现中。旧 trace helper 静音不等于日志关闭，也不建议把关闭全部日志当作修复。**

### F04：详情缓存实际上没有 16ms 合并窗口

入口：[详情保存队列](../../lib/features/storage/data/local_storage_cache_repository.dart#L945)、`_saveDetailTargetsBatchUnlocked`、`_saveDetailPayload`。

- 入队后用 `scheduleMicrotask` 启动 flush；`_detailTargetSaveFlushTimer` 只有声明/取消，没有设置 16ms 的合并计时器。
- 每次修改先复制整个 records/lookup map，保存时编码整份 payload，再 `PreferencesStore.setString`。网络补全的不同回调分散到不同事件时，合并收益明显下降。
- 已有内存 payload 缓存、大 JSON 后台 isolate、串行 mutation tail 和编码结果一致时跳过写入。它们缓解并发和 UI 编码成本，但不能消除整份 payload 的复制、传输和落盘工作。
- 非 Web 下编码达到 16 条、解码原始字符串长度达到约 64 KiB 阈值时后台处理，不等于所有前后处理都离开 UI isolate。

**已复现**：同一同步调用段提交 10 个新详情，只写 1 次；每次之间让出一个事件轮次，写 10 次。证明的是跨事件缺乏时间窗口合并，不是设备 10 倍变慢。

建议先引入有界合并窗口及可靠 flush/dispose 语义，验证并发、清理和退出不丢数据；后续按实测规模决定是否迁移为按记录存储，不必第一步就重写整个缓存架构。

### F05：更新一个评分人数仍重写全部来源分片

入口：[updateMediaItemRatingCount](../../lib/features/storage/data/local_storage_cache_repository.dart#L670)、[_saveEmbySnapshotShards / _writeEmbyShardPayloads](../../lib/features/storage/data/local_storage_cache_repository.dart#L1545)。

评分人数更新会加载完整来源 snapshot、遍历分区，然后保存 fallback、summary、所有 section shards 和 manifest，没有逐分片相同内容跳写。这是 Emby/飞牛共用的本地缓存成本，并非评分更新本身需要扫远端库。

**已复现**：两分区来源只更新第一分区一部影片的评分人数，发生 5 次 preferences 写入，其中 3 次内容完全不变。这里统计仓库写接口调用，不声称对应 5 次物理 fsync。

读取路径已有有效优化：根列表最多 400 条 summary，指定分区只读目标 shard，全量解码最多 2 路，同一 shard/snapshot 的在途读取合并。问题在增量写路径，不是“还没有分片”。

建议只修改受影响 shard 和必要的 summary，manifest 未变化不写，并保留失败恢复和缓存一致性测试。

### F06：NAS 增量落库后仍同步全源重建内存索引

入口：[分批 patch 与缓存重建](../../lib/features/library/data/nas_media_indexer_storage_access.dart#L525)、[_buildLibraryMatchCache](../../lib/features/library/data/nas_media_indexer_storage_access.dart#L659)、[Sembast 存储](../../lib/features/library/data/nas_media_index_store.dart)。

- 数据库修改已经按 16 条分批，并在批次间让出事件循环。
- 批次完成后仍合并整个来源、排序，并同步重建全源系列分组、各分区系列分组、展示条目与多种 ID 查找表。
- 冷 `_loadSourceRecordsCached` / `_loadLibraryMatchCache` 有完成结果缓存，但没有共享在途 Future；多个冷入口可能重复加载、分组。
- Sembast 使用普通 IO 数据库工厂；异步 API 不代表所有解码、筛选、排序天然运行在独立 worker。已有 `sourceId + sectionId` finder 过滤有收益，但不应理解为已经建立 SQL 式索引。

已有 WebDAV 大 XML 解析、结构推断和子树序列化的 isolate 路径，不能笼统认定全部扫描在主线程。建议按 1千/1万/5万条来源测量落库后重建阶段，优先合并冷读，再考虑 worker 分组或仅更新受影响系列/分区。区分 CPU 时间、对象分配和远端目录耗时。

## 3. 首屏、页面和网络

### F07：启动关键路径

入口：[main](../../lib/main.dart#L17)、[BootstrapController](../../lib/features/bootstrap/application/bootstrap_controller.dart#L113)、[来源缓存协调](../../lib/features/settings/application/media_source_cache_lifecycle.dart#L74)。

- `runApp()` 之前串行读取设置、配置日志、等待构建信息（单独最多 2s）、写启动标记、初始化 MediaKit。Bootstrap 的 10s 期限从控制器开始，不包含这些前置工作，也打不断同步阻塞。
- Bootstrap 保留 40+40+30+40ms 共 150ms 的人工阶段等待。当前已删除的首页刷新 140ms、来源配置读取 120ms 不再算作现存问题。
- 启动来源协调要读取源状态、缓存来源 ID；[loadCachedSourceIds](../../lib/features/library/data/nas_media_index_store.dart#L167) 扫描 source、record、directory-cache store，详情来源 ID 收集也可能读取整个详情 payload。大库冷启动需特别测量。
- 首页等待全部启用模块完成，阶段上限 5s，而非首个可见模块可操作就放行。
- [空媒体服务器缓存](../../lib/features/library/application/app_media_query_service.dart#L342) 仍在读链路等待完整 Emby/飞牛刷新；NAS/WebDAV 空库重建已后台化，Quark 的首次空索引路径仍可能同步等待，三者不能混为一谈。

建议定义“最小可交互首页”，保留必要的来源身份隔离和启动恢复保障；把不影响这些保障的信息采集/整理放到首帧后，缓存来源清单避免常规启动全量枚举。

### F08：首页依赖范围和重建

入口：[_homeSectionSeedProvider](../../lib/features/home/application/home_controller.dart#L269)、[首页 build](../../lib/features/home/presentation/home_page.dart#L538)、[DiscoveryRepository](../../lib/features/discovery/data/discovery_repository.dart)。

- seed provider 在判断模块类型前就监听 NAS index 与 library refresh 的全局 revision，因此本地来源变化也能使豆瓣/最近播放等模块重新计算；豆瓣仓库直接委托 API，没有这一层的结果缓存。
- 页面根节点监听 `homeResolvedSectionsProvider`，单模块 loading/data/error 变化仍可重建根部并重新处理页面焦点结构。
- `homeSectionProvider` 不是 autoDispose，且首页所在 shell 保留分支，失活页面不能简单等同于 provider 已销毁。

已有 seed/详情装饰分层、section 独立订阅、Hero 局部 ValueNotifier、设置 slice、预取去重。**详情缓存 revision 本身不会重新触发所有来源抓取**，需与前述 NAS/library revision 区分。建议按来源与模块类型收窄依赖，根节点只监听布局/就绪所需的最小投影。

### F09：并发、排队和生命周期

入口：[首页调度](../../lib/features/home/application/home_feed_load_scheduler.dart)、[元数据调度](../../lib/features/metadata/application/metadata_prefetch_concurrency_limiter.dart)、[运行期恢复](../../lib/app/lifecycle/app_runtime_recovery_boundary.dart)。

| 设置/策略 | 当前默认或约束 | 性能含义 |
| --- | --- | --- |
| `taskMaxConcurrency` | 默认 2，可配 1-6 | 首页与元数据各自读取此值，不是统一全局请求池 |
| 首页首批/后续间隔 | 2 个 / 350ms | 降低突发，同时增加后续模块排队时间 |
| 首页结果应用 | 串行，间隔 20ms | 平滑 UI 更新，但不等于结果收到即可显示 |
| 元数据首批/后续间隔 | 12 项 / 300ms | 首批是准入批次，不是同时启动 12 条连接 |
| 交互后元数据安静期 | 默认 400ms | 高频焦点/滚动期间后台补全可能持续后移 |
| NAS 内部上限 | 来源 2，集合/补全项 4，均结合共享设置 | 在线补全还要经过全局元数据 limiter |
| Emby maintenance | 与 NAS 在线补全共享 limiter，优先级较高 | 可绕过交互安静期，但仍受全局暂停约束 |
| TV 栅格图片 | 4 个许可 | 非严格在途 HTTP 上限，见 F02 |
| 回前台 | 首帧后再等 400ms | 是保护窗口，不是网络本身变慢 |
| 内存压力 | 另加 2s 暂停并请求后台刷新取消 | 应用自有缓存没有因此全部释放 |

首页、元数据、图片、搜索和播放器连接可以同时占用资源。暂停通常只阻止新任务，已发送请求不一定取消；媒体源分页、重试、代理往返和服务端限流还会扩大墙钟时间。应分别记录队列等待与任务执行时间，不能通过一律提高并发或清零活动计数来“修复卡住”。

### F10：搜索扇出和结果处理

入口：[SearchPage](../../lib/features/search/presentation/search_page.dart#L547)、[来源启动循环](../../lib/features/search/presentation/search_page.dart#L889)、[本地搜索打分](../../lib/features/search/data/search_repository.dart#L82)。

- 选中的搜索来源在循环内直接 `unawaited` 发起，未由 `taskMaxConcurrency` 统一限制；分享验链有自己的共享并发门，不能当成来源请求的限流。
- 本地检索请求每源最多 2000 条，然后在调用 isolate 标准化文本、逐条打分、排序。实际返回数量还受来源 summary/索引路径限制。
- 结果已有 120ms UI 批次提交，但每次 flush 会整理/排序累积结果，验链 `finally` 又逐项 `setState(() {})`，网盘筛选时 `_displayedResults` 每次遍历/分类结果。
- 过期搜索会丢弃旧结果，但通常不取消已经发出的 HTTP。多来源、大结果集和连续换关键词组合下，CPU、重建与网络可以叠加。

已有空关键词短路、分享归一去重、验链限流与懒 `SliverList`。建议合并验证状态提交、缓存筛选投影、给来源扇出独立预算；大规模本地打分再考虑 worker 或索引化。不要误改为等所有来源结束才展示。

## 4. 长期使用、内存与磁盘

### F11：播放历史读写

入口：[PlaybackMemoryRepository](../../lib/features/playback/data/playback_memory_repository.dart#L344)、[Android memory store](../../android/app/src/main/kotlin/com/example/starflow/NativePlaybackMemoryStore.kt#L22)、[iOS history store](../../ios/Runner/AppDelegate.swift#L1835)。

- Dart 有暖快照缓存和串行修改，但冷读缺少 in-flight 合并。探针直接并发调用 12 次 `loadSnapshot()` 产生 12 次 preferences 读取，之后暖读不增加次数。共享 Riverpod snapshot provider 已合并很多 UI 调用，不能推断所有详情页面必然发生 12 次读取。
- 最近 20 条只裁剪 `items`，`series` 按剧保存且没有相同裁剪；探针写入 25 部不同剧后，`items=20`、`series=25`。跳过规则与字幕偏好也是长期保留数据，但属于用户配置，不能为了缩容擅自删除。
- 保存整个快照在 Dart 调用 isolate JSON 编码。通常约每 10s 播放进度变化触发一次，并有暂停/退出/跳转等强制保存，因此 series 增长也增加后续每次保存成本。
- Android 已缓存未变的解析结果，但强制保存使用同步 preferences `commit()`；运行控制在 main looper 上调用。
- iOS 周期观察约每 2s、保存阈值约 10s，存储路径每次重新取整个 JSON 并解析/编码，缺少 Android 同等的已解码快照复用。

建议补冷读 Future 共享，分开历史和长期偏好，定义可解释的历史保留/清理策略，再评估异步/增量存储。保留退出前最终进度可靠性以及 Dart/原生交替写入后的缓存失效。

### F12：图片与数据缓存

入口：[MediaPosterTile](../../lib/core/widgets/media_poster_tile.dart#L136)、[持久图片缓存](../../lib/core/storage/persistent_image_cache_impl_io.dart#L25)、[TMDB](../../lib/features/metadata/data/tmdb_metadata_client.dart#L26)、[WMDB](../../lib/features/metadata/data/wmdb_metadata_client.dart#L27)、[首页分页 provider](../../lib/features/home/presentation/home_module_collection_page.dart#L131)。

- 普通海报按显示高度限制解码；豆瓣图片域名整体跳过 resize，是现有设备兼容策略。高分辨率来源用于小海报时会增加解码及纹理成本，不能未验证图片格式/设备兼容性就删除例外。
- RGBA 量级可按宽×高×4 估算，例如 2000×3000 约 22.9 MiB，仅用于解释尺寸成本，不代表该应用每张图片的实测驻留大小。
- 压缩字节内存缓存上限为 256 项/72 MiB，和 Flutter 已解码图片缓存、GPU 纹理不是同一层。持久栅格图主要经 FileImage 加载，不应把所有层的容量上限相加当作实际占用。
- 磁盘图片 30 天 TTL 是访问时的 freshness 判定，不是全目录容量淘汰或周期清理；长期未再访问的旧图可持续占盘。metadata 缺失时还有 `statSync` 回退。
- TMDB/WMDB 的已解析匹配结果 map 没有容量上限；Emby shard/snapshot、详情 payload、NAS 分组也各自常驻。不要只看一种缓存指标。
- indexedStack 保留访问过的页面，非 autoDispose 的分页 family 可保留已经看过的 50 条/页数据。这提升回访速度，也增加长会话内存基线，不能直接等同于泄漏。
- 当前 memory-pressure 主要暂停任务并取消刷新；没有明确逐级回收这些应用自有缓存的策略。

建议分别采样 Dart heap、native heap、RSS/PSS、图片 decoded bytes 和磁盘目录大小，按价值做 LRU/容量淘汰与内存压力回收，避免一次清空所有缓存制造返回页面重载风暴。

### F13：日志预览和导出

入口：[FileAppLogStorage.read / export](../../lib/core/logging/app_logger_impl_io.dart#L248)、[日志容量设置](../../lib/features/settings/domain/app_settings.dart#L418)。

- 只请求最近 300 条也会读取 native/previous/active 三个文件，完整 UTF-8 解码、逐条解析、全量排序，再截尾。
- 默认总容量设置 20 MiB，最高选项 100 MiB。读取异步，但后续字符串/JSON/排序在调用 isolate 执行，可在打开预览时产生停顿和临时堆峰值。
- 导出将所有文件加入可增长的 `List<int>`，随后导出流程可能再拷贝；容量不等于单份连续字节缓冲的成本。
- 正常 Dart 日志写入已经异步串行，但每条仍有目录/文件检查、追加与轮转检查，队列没有有界批量合并。

建议从文件尾有界读取、后台解析、流式导出、日志批量写入及背压。保留等级筛选、敏感字段脱敏和关键日志可靠落盘。

## 5. 渲染、播放与字幕的必要成本

### F14：Flutter 绘制、保留页和焦点

- [首页背景](../../lib/features/home/presentation/home_page_sections.dart#L534) blur 为 sigma 54，[Hero](../../lib/features/home/presentation/home_page_hero.dart#L1249) 为 28，[导航](../../lib/app/router/app_navigation_shell.dart#L374) 为 24/26；全屏背景、透明合成、Hero 自动切换同时出现时值得检查 raster 和重绘区域。
- 减少动画、简化界面、透明磨砂、静态 Hero、简化 Hero 是独立设置，并非一个开关全部关闭。TV 固定轻量焦点、精简详情 Hero、精简播放 UI，并禁止实时卡片信息叠加。
- 焦点已有 ValueNotifier 局部更新和未布局节点保护；长列表方向寻焦、居中滚动、首页拓扑重算仍有布局/计算成本。需要区分短按、长按、边界和数据刷新时的帧时间。
- 主要媒体库为懒 sliver grid，大剧集行为懒构建；部分嵌套 shrinkWrap 网格是分页 24/50 条级别，不宜仅凭 `shrinkWrap` 就列为最高优先级。
- [indexedStack](../../lib/app/router/app_router.dart#L42) 保留状态有回访收益。TickerMode/可见性能够抑制动画和部分订阅，但不自动销毁保留对象或中断 HTTP。

用 profile 的 build/raster 时间和 repaint 证据决定优化位置。单纯拆 Dart 文件、减少行数或到处添加 RepaintBoundary 不保证性能改善。

### F15：播放缓冲、定位与解码

入口：[Exo 缓冲策略](../../android/app/src/main/kotlin/com/example/starflow/NativePlaybackBufferPolicy.kt#L17)、[MPV 缓冲策略](../../lib/features/playback/application/mpv_tuning_policy.dart#L34)、[TS extractor](../../android/app/src/main/kotlin/com/example/starflow/NativePlaybackExtractorsFactory.kt)。

| 路径 | 当前成本/策略 | 需要验证的取舍 |
| --- | --- | --- |
| Exo TV，memoryClass ≤256 MiB | 通常 32 MiB，重型 48 MiB；首次启动阈值 1.5s、再缓冲 4s，带宽档位可调整 | 原生/纹理总内存不是该 buffer 数值 |
| Exo 更高 memoryClass | ≤512 档为 64/80 MiB，以上为 96/128 MiB | 增大缓存改善抖动但可能加重整体内存压力 |
| Exo 远程切集 | 低内存档目标至少 48 MiB，启动/再缓冲阈值至少 6/12s | 这些是缓冲媒体时长阈值，不是固定等 6/12 秒墙钟时间 |
| MPV | 前向 32-256 MiB、回退 8-64 MiB；低内存 TV 前向限制 64/96 MiB、回退 16 MiB | 重型媒体和云盘策略不是越激进越快 |
| progressive TS 定位 | PCR 搜索窗 112,800 增至 1,128,000 字节，约 10 倍 | 修正稀疏 PCR 定位，但既有 Range 流量/定位耗时可能增加 |
| 软解/硬解/拷贝路径 | 分辨率、位深、HDR、滤镜、字幕和画质预设共同决定负载 | 比较实际 decoder、CPU、GPU、温度和掉帧，菜单值不够 |
| 音频 | FFmpeg 软解、LPCM 转换、声道转换、重采样与速度调整 | 直通兼容性优先，不能为降 CPU 盲目强制直通 |
| 飞牛转码 | 显式选择后由 NAS 生成 HLS；控制请求与媒体流分离 | NAS CPU/GPU、网络和客户端解码分别测量，默认原画不自动转码 |

已有保护必须保留：播放器释放串行、有限重试、启动/运行恢复分离、相邻一集地址预解析和缓存；预解析不创建第二个播放器。首次地址解析仍可能请求播放信息、STRM 和必要的大小/格式判断，不能与已取消的 MPV 独立测速预检混淆。

MPV 使用既有属性采样和约 10 分钟主机带宽缓存，不为常规网速显示发额外网络探测；可见网速约 1s、性能采样约 5s、watchdog 约 1s。Exo runtime 约 1s、watchdog 约 5s、历史约 10s。定时器本身不是逐帧网络负载，重点应检查每次回调执行的同步工作。

iOS 封面已在 utility queue 降采样，下载上限 8 MiB、最长边 1200px，不应把它列为无界原图解码。AVPlayer 的 `timeControlStatus == .playing` 只是当前埋点的播放状态信号，不是严格的视频像素上屏证据。

### F16：字幕搜索、处理和呈现

入口：[字幕仓库](../../lib/features/playback/data/online_subtitle_repository_io.dart)、[下载验证](../../lib/features/playback/data/online_subtitle_validation_pipeline.dart)、[内容处理](../../lib/features/playback/application/subtitle_content_processing.dart)、[字幕边界说明](../subtitles.md)。

- 在线搜索会并行询问启用来源，但当前不预下载全部候选，只在用户点选时下载；因此不能套用旧版本的“搜索时批量解压字幕”判断。
- 下载已有累计字节限制和约 30s 总期限，ZIP 有展开边界和校验，大部分 Dart 字幕内容处理使用 `compute`；Web 的 isolate 能力需另论。
- 下载前会执行过期字幕缓存清理，按目录逐项 stat；大量缓存时是额外选中延迟，属于低优先级，可合并/节流维护。
- 双字幕、ASS 特效、字体、描边/阴影、位图上传都是真实运行成本，复杂样本需单测。当前 PGS 显示集限制 4 MiB，cue 交付已有 latest-only/有界追赶保护，不是无界累积设计。
- 最新 LPCM 已复用缓冲并批量提交样本。应测现有代码在 ARM32/ARM64 的实际 CPU/GC，而不是继续把已修复的逐小包分配列为现存问题。

## 6. 用户操作与外部环境

### F17：设置、收藏和转存

- [设置自动保存](../../lib/features/settings/presentation/settings_auto_save_coordinator.dart) 文本有 250ms 防抖、去重和串行队列；步进/选择等即时操作仍可能保存整份设置。播放器还有整份设置监听，低频无害，连续调参数时应看重建/持久化量。
- [收藏自动同步](../../lib/features/search/application/favorite_auto_sync.dart) 是事件触发并串行处理，不是启动后的周期性轮询。多设备清单下载、合并及收藏缺图补全会产生可见等待，但已有页面激活/过期结果保护。
- 夸克/115 转存需要分页、去重、可选改名及确认；STRM 延时和索引延时是既定等待，媒体库刷新安排后在后台继续。不能通过删除完整分页或对写请求自动重试来提速，否则可能漏项/重复转存。
- schema、来源身份、扫描范围变化可能触发重建；当前 WebDAV schema 为 v14。重建与增量扫描必须分组比较，缓存清理也会把下一次读取变成冷路径。
- 设置里的本地存储检查会枚举缓存目录、统计文件和部分 payload；这是按需成本，不应在短周期自动重复执行。

同一段代码的表现还受以下因素影响：低内存 API 23 与新设备的 CPU/闪存差异、ARM32 地址空间、温控、屏幕分辨率/刷新率、服务端分页速度、库规模、网络往返/丢包、代理是否命中局域网绕过、认证失效与重试、媒体码率/编码以及日志等级。

Dart 应用 HTTP 代理不自动覆盖 Exo/AVPlayer/外部播放器媒体栈；MPV 已打开的连接不因保存代理立即重建。构建下载镜像和 Gradle 代理影响开发耗时，不等于安装后应用网络加速。测试时记录这些条件，避免把环境变化当作代码回归。

## 7. 证据、文档差异与验收

### F18：本次实际执行的验证

在 macOS 工作区执行定向 Flutter 回归，使用 `--no-pub`：

| 分组 | 文件/场景 | 结果 |
| --- | --- | --- |
| 图片、缓存、调度与启动 | `app_network_image_test`、`local_storage_cache_repository_test`、`home_feed_load_scheduler_test`、`metadata_prefetch_concurrency_limiter_test`、`bootstrap_deadline_test`、`playback_runtime_priority_binding_test`、`player_open_smoke_test` | 42 项通过 |
| 数据与存储 | `nas_media_indexer_test`、`search_repository_test`、`playback_memory_repository_test`、`file_app_log_storage_test`、`starflow_http_client_test` | 105 项通过 |
| 搜索组件 | `search_page_share_validation_test` | 11 项通过 |
| 临时机制探针 | 正文超时、详情跨事件写、冷历史读、单评分分片写、series 保留、播放前取消等待 | 6 项通过 |

合计为 **158 项定向回归 + 6 项机制探针**，不是全量测试/全平台构建。本次不重复引用其他任务的 1580 项 Flutter 或 JVM/Swift 结果作为自己的验证。

早一轮搜索组件编译曾被工作区正在变化的 TV 按键实现挡住；随后重跑已通过，不能继续报告为当前失败。临时探针使用内存 preferences、可控流和 Future，不访问真实账号或服务器；执行后删除，仅保留本文的设置与断言记录。

`adb devices -l` 无连接设备，未采集 TV 帧率、真实首帧、CPU、PSS/RSS、HDMI 或 ARM 解码数据。没有运行发布预设，也没有生成 APK。

### 当前文档与实现的差异

- README、architecture、performance 仍描述“16ms 内详情更新合并”；当前实现是微任务合并，见 F04。
- performance 中“图片 HTTP 15s 超时”若理解为整个图片读取是不准确的；当前只有响应头期限，见 F02。开发网络文档已说明共享 HTTP 的响应头/正文区别。
- `performance-device.md` 已存在，内容是设备验收方法，不是通过报告；本次检查结束时不存在“缺少设备文档”的问题。
- `tool/perf/run_perf_baselines.dart` 测量整个 `flutter test` 子进程，包括工具/编译/执行；不是 TTI、Flutter 单帧或播放器首帧。
- 历史 `perf_baselines.json` 为 2026-04-11，每场景仅 1 个样本；p50=p95 不构成尾延迟证据。本次未覆盖该文件。
- `AppFramePerformanceMonitor` 默认长帧阈值 250ms，只告警严重停顿；无法替代 60Hz 的 16.7ms、30Hz 的 33.3ms 帧预算分析。

本文不覆盖并行工作中的既有文档；实际修复 F02/F04 时，需要同步修正文档契约，避免只改表述或只改实现。

### 建议的执行顺序

1. **先控制额外工作**：F01/F02 的等待、取消与完整请求期限；F03 的原生日志线程/轮转；F04/F05 的写入合并及局部分片写。验收包括慢正文、取消、满日志、跨事件补全和中途退出。
2. **再控制规模增长**：F06 的分组 CPU 与冷读合并、F08 的依赖范围、F10 的搜索批量更新、F11/F12 的长期存储和缓存容量。使用固定 1千/1万/5万库与长会话回访场景。
3. **最后按真机调参数**：背景 blur/Hero、buffer、解码/音频/字幕。至少覆盖低内存 API 23、ARM32/ARM64、冷暖缓存、本地/远程同样本、首次/续播/切集/长距离 seek。

每轮记录点击到可操作、点击到实际画面、UI/raster 帧时间分布、慢帧数、视频掉帧、缓冲次数与时长、CPU/内存峰值、HTTP 活动数和取消耗时、实际写入次数/字节数。主机工作量验证和设备用户体验结论分开，既保留成功样本，也保留失败与超时样本。
