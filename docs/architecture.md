# Starflow 架构说明

这份文档描述的是仓库当前已经落地的实现，而不是早期规划稿。

## 1. 总体定位

Starflow 不是单一播放器，而是一个面向个人影音库的统一入口，把这些能力放进同一个 App：

- 本地媒体源：`Emby`、`WebDAV`、`Quark`
- 内容发现：豆瓣
- 聚合搜索：本地资源、`PanSou`、`CloudSaver`
- 播放：内置 `MPV` + App 内原生播放器容器页 + 系统播放器
- 入库联动：夸克保存、`SmartStrm` Webhook、自动增量刷新索引
- 本地持久化：设置、详情缓存、图片缓存、`WebDAV` 元数据索引
- 诊断与运维：结构化本地日志、Android 原生退出信息、日志预览与导出

## 2. 技术基线

- 框架：`Flutter`
- 状态管理：`flutter_riverpod`
- 路由：`go_router`
- 播放：`media_kit`
- 设置、详情缓存与 Emby 分片缓存：`SharedPreferences`
- `WebDAV` 索引库：`Sembast`

应用入口在 `lib/main.dart`，启动时完成：

- Flutter 绑定初始化
- `media_kit` 初始化
- `ProviderScope` 注入

## 3. 代码组织

```text
lib/
  main.dart
  app/
    app.dart
    router/
    theme/
  core/
    network/
    platform/
    storage/
    utils/
    widgets/
  features/
    bootstrap/
    details/
    discovery/
    home/
    library/
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

一级导航固定为：

- 首页
- 搜索
- 媒体库
- 设置

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
- `TV` 主要页面和弹窗的普通方向键使用 Flutter 默认寻焦，不再声明 `OrderedTraversalPolicy / NumericFocusOrder`；文本编辑弹窗仅在输入框局部把上下键映射为前后焦点，选择弹窗只在首帧请求一次初始焦点，不安排延迟补焦点
- `TV` 焦点视觉态已经收敛到 `ValueNotifier + ValueListenableBuilder` 局部更新，并补了 `TvFocusVisualStyle.none`
- `TV` 页面级焦点边界、页头回顶锚点和统一的上下方向焦点兜底
- `TV` 页面级焦点壳与方向动作面板，便于首页、搜索、媒体库、详情、设置等页共用同一套焦点边界
- `TvPageFocusScope` 安装 `TvSafeDirectionalFocusTraversalPolicy`：方向寻焦读取候选节点坐标时若遇到动态刷新产生的暂时未布局 `RenderBox`，忽略当前按键并保持原焦点；其他异常仍继续抛出
- `StarflowApp` 仅覆盖默认 `DirectionalFocusIntent` Action，补齐页面级策略覆盖不到的路由/Overlay 焦点：只捕获 `RenderBox was not laid out` 并忽略当次按键，不做下一帧重试、候选过滤或顺序改写；警告按 Action 实例做 `5s` 限频
- 首页在重新变为活动页以及 `hasPendingSections` 从 `true` 变为 `false` 时各安排一次下一帧检查；仅在主焦点为空、落在 `FocusScopeNode`、已卸载或不可请求时调用现有侧栏恢复入口，已有可操作焦点时不做任何处理
- TV 主壳处理返回键时先以 `UnfocusDisposition.scope` 清理当前焦点及作用域历史，再聚焦当前页面对应的侧栏入口；仅当该入口已经持有主焦点时，再次返回才进入退出确认
- 焦点诊断统一写入 `tv.focus-recovery`：首页实际缺焦恢复为 `info`，返回清理为 `trace`，未布局候选为限频 `warning`；正常寻焦与普通方向键不写日志
- WebDAV STRM 文本解析在返回播放 URL 前把裸 `#` 替换为 `%23`；已编码地址保持不变，避免文件名中的集号被 URI fragment 规则截断
- `TV` 焦点进入长列表项时，会尽量把目标控件维持在视口中线附近，并驱动页面一起滚动
- 页面级保留态异步结果封装：`core/navigation/retained_async_value.dart` 与 `core/navigation/retained_async_controller.dart`
- 桌面端横向列表的统一左右翻页按钮容器，供首页海报流、剧集横排、剧照横排复用
- 设置区共用页面骨架和交互组件
  - 统一的设置页容器、顶部工具栏按钮、操作按钮
  - 统一的选择条目、开关条目、可展开区块
  - 统一的选项弹窗与 `TV` 文本编辑弹窗入口

### `features`

按业务拆分：

- `bootstrap`：启动预热
- `home`：首页模块装配与 Hero
- `library`：媒体源接入、`WebDAV` 索引、`Quark` 目录源、刷新、删除
- `details`：详情页、详情缓存、手动索引入口、人物关联影片页
- `metadata`：`WMDB / TMDB`
- `search`：本地搜索、在线搜索、夸克保存、`SmartStrm`
- `playback`：播放器
- `settings`：设置、配置导入导出
- `storage`：详情缓存 revision 等辅助状态

### `tool`

仓库里的 `tool/` 目录除了开发辅助工具外，还承担外部品牌资源导出：

- `tool/generate_brand_assets.py` 会生成 Android、iOS、macOS、Web、Windows 的外部 App Icon
- 同一脚本也会同步生成启动页所用的 `assets/branding/starflow_launch_logo.png` 与 iOS `LaunchImage.imageset`
  这条链路输出的是透明底主图案，不复用外部 app icon 的方形底板
- 同一脚本也会同步生成 Android 启动页使用的 `android/app/src/main/res/drawable-nodpi/launch_logo.png`
- 同一脚本也负责生成 Android TV Banner
- 外部 App Icon 当前以 `assets/branding/starflow_icon_master.svg` 为设计源
- 脚本会先从矢量母版直接生成 `build/brand_assets/app_icon_raw_capture.png`
- 脚本会直接程序化生成统一分发母版 `build/brand_assets/starflow_app_icon_master.png`
- 最后再缩放分发到各平台资源目录

### `scripts`

仓库里的 `scripts/` 目录当前除了开发辅助脚本，也包含 TV 与 Windows 打包链路：

- `scripts/build_tv_apk.ps1` 默认把 TV 安装包输出到桌面
- 支持按需临时嵌入配置 JSON，打包结束后自动清理
- 内部默认使用 `flutter build apk --release --android-skip-build-dependency-validation`
- TV 文件名使用 `starflow-tv[-config]-主版本.月份.序号.apk`
- 当前显示版本号按标准三段式 `主版本.月份.序号` 自动递增
- 当前 Release APK 会继续启用 `v1 + v2` 签名，并沿用本机 debug keystore
- `scripts/build_windows_installer.ps1` 默认把 Windows 安装器输出到桌面
- 这条脚本会先执行 `flutter build windows`，再调用 Inno Setup 生成单个安装器
- 当前安装器文件名使用 `starflow-windows-版本号-setup.exe`
- Inno Setup 编译器当前会优先在 `E:` 和 `C:` 下的常见安装目录查找 `ISCC.exe`
- `scripts/connect_mumu.ps1` 会扫描 MuMu 的 `vm_config.json`，优先尝试桥接模式的 `guest_ip:5555`，再回退到 `127.0.0.1:host_port`

## 3.1 近期架构与性能收口（2026-08）

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
- NAS 索引链收口：`NasMediaIndexer` 已拆成 `nas_media_indexer_refresh_flow.dart / nas_media_indexer_storage_access.dart / nas_media_indexer_indexing.dart / nas_media_indexer_grouping.dart / nas_media_indexer_refresh_support.dart` 多段 `part` 文件；主文件回到约 `1k` 行量级，先把刷新编排、存储访问、metadata 匹配与分组逻辑解耦，为后续 isolate 化、`IndexStore` 增量 upsert 和多级并发预算继续铺路
- NAS 分区读链收口：显式分区查询直接交给 `NasMediaIndexStore.loadSourceRecords(..., sectionId: ...)`，Sembast 在数据库层组合 `sourceId + sectionId` 过滤；只有整源查询继续复用来源级内存缓存
- 首页模块加载与元数据预取已拆成独立调度器：前者限制首页数据源扇出并串行应用结果，后者统一约束 Hero、评分、元数据补全和显式维护任务；两者共享一个持久化最大并发值，各自保留首批数量和后续批次间隔
- 元数据调度器在前台交互结束后按可配置静默期恢复；首页、媒体库和集合页只在进入“内容加载中”状态时申请一次静默期，避免 widget rebuild 持续推迟后台任务
- 单击导航栏首页会触发统一软恢复边界：页面 revision 终止旧的 Hero/评分预取会话，媒体刷新协调器取消后台 NAS/WebDAV/Emby 刷新，首页与元数据调度器只清除自身的批次/静默等待并继续 drain；活动任务、前台 lease 和并发计数不会被强制归零
- `TV` 退出确认框使用短生命周期的元数据前台 lease，只在对话框显示期间阻止新的后台预取；取消后以零延迟释放，真正确认退出仍走播放器与系统会话清理，不复用导航软恢复
- 首页重新 active 或模块 ID 顺序变化时会在下一帧校验焦点所属路由；编辑器等已退出路由遗留的 FocusNode 不视为有效首页焦点，优先请求 Hero 下方首个模块，失败才回侧栏
- Android / TV 真正确认退出时，Flutter 先清理播放会话、媒体通知、画中画和后台播放，再通过 `starflow/platform` 调用原生 `finishAndRemoveTask()`；桥接不可用时才回退 `SystemNavigator.pop()`，避免任务仍留在启动器中被自动恢复
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

## 3.2 跨 feature 新结构关系（Home / Detail / Playback / Library / Settings Slices）

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
  - 播放目标补全（`Emby / Quark`）
  - 解析结果回写详情缓存
- `HomeHeroPrefetchCoordinator` 与详情链路复用同一套详情缓存与 enrichment provider，避免首页和详情各自维护一套补全逻辑。
- 详情页 presentation 入口已经进一步拆成 `detail_page_providers.dart`、`detail_hero_section.dart`、`detail_resource_info_section.dart`，`media_detail_page.dart` 主要保留页面级 session / callback / section wiring。

### Playback

- `PlaybackTargetResolver`：先把播放目标解析到可播地址/headers。
- `PlaybackStartupCoordinator`：统一串起目标解析、续播/跳过配置读取与路由判定输入准备。
- `PlaybackEngineRouter`：封装路由判定（系统播放器 / 原生容器 / 内置 MPV）。
- `PlaybackStartupExecutor`：执行路由动作，并返回是否继续走内置 `MPV` 打开链。
- `player_page.dart`：只保留页面壳、状态字段和顶层装配；平台会话、启动/MPV、运行期动作和播放器控制已经沉到 `presentation/widgets/player_page_*.part.dart` 与独立 widgets。
- `PlaybackMemoryRepository`：负责最近播放/续播记忆，并通过单调递增 `updatedAt` 保证最近播放列表稳定排序。

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
- `network_failure.dart` 把错误统一归类为 `timeout / tlsHandshake / dns / connection / connectionClosed / httpStatus / circuitOpen / cancelled / unknown`
- `NetworkRequestGuard` 按 `policy + host` 保存连续临时故障状态，提供总请求超时、可选的幂等重试和熔断；非幂等操作默认不重试
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
- Android 原生侧读取 `ApplicationExitInfo`，把上一进程的 ANR、Java/Native 崩溃、低内存和资源异常退出合并进日志

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
- 人物关联影片页
- 元数据索引管理页
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
- 最近播放卡片的主标题会优先显示电影名或剧集总名；对于单集，`SxxEyy`、进度等信息继续留在副标题，不再把具体集名作为首页主标题
- Hero 当前主要外显配置是 Logo 形态标题、`normal / borderless` 展示方式和背景图
- Hero 会根据横竖屏优先选择对应方向的素材；横屏优先横图、竖屏优先竖图，只有单张图可用时会直接按海报布局展示
- `Hero` 当前项、翻页按钮和指示状态已经收口到局部监听；切换当前 Hero 时不会再带动首页根节点整块重建
- 首次进入首页时，如果 Hero 条目信息不全且还没有 metadata refresh 成功 / 失败标记，会后台 best-effort 补一次信息，并把结果写回详情缓存
- 首页 `Hero`、背景图与海报图会按显示尺寸传递 decode 尺寸；移动端 `PageController` 也做了边界稳定化，降低首屏切换和大图解码抖动
- 静态 Hero 与精简 Hero 视觉由一个界面开关原子更新，全屏背景图仍单独持久化
- `TV` 首页会给 Hero、模块标题和内容区之间补齐明确的方向焦点路径，避免焦点停在 Hero 图片层后无法继续下移
- 桌面端首页普通横向海报流也会复用统一的左右翻页按钮，而不是只让 Hero 独占这套交互

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

### WebDAV

`WebDAV` 页面消费模型不是“页面实时扫目录”，而是“索引驱动”：

1. `WebDavNasClient` 扫描目录
2. `NasMediaIndexer` 做识别、聚合和补元数据
3. `NasMediaIndexStore` 把结果落到本地
4. 首页、媒体库、详情页优先读取索引

补充约束：

- 用户触发的增量刷新会先按来源清除持久化 WebDAV 子目录快照，再重新读取当前作用域；索引和元数据阶段仍只处理新发现文件，已有记录直接复用。夸克保存后的自动刷新仅在发现新文件时失效对应来源快照；如需重新处理并修复旧条目，使用重建索引
- 这一步会遍历作用域内目录来识别变更，但不会越过到其他分区
- 增量阶段的 sidecar 和在线元数据补全只针对新发现文件执行；已有记录的缺失或失败状态不在增量阶段重试，旧条目修复交给重建索引或显式元数据操作
- 只有当当前作用域索引为空时，才允许在后台调度一次自动全量重建；读链路本身不再同步等待这次重建
- 指定分区的普通读取保持媒体源原有索引作用域：先由 Sembast 使用 `sourceId + sectionId` 精确过滤；若记录统一归属扫描根，再读取同源记录并按规范化 URI 目录段边界过滤。点击 `quark` 等子目录不会把它临时冒充成新的索引作用域，也不会误混入 `quark-old / 115` 等相邻目录
- 每份 NAS / WebDAV / Quark 索引状态持久化媒体源资源身份；同一 `sourceId` 的 endpoint、根路径或 Quark 根目录变化时，启动与设置保存链会停止旧扫描并清除该来源的索引、WebDAV 目录快照、内存聚合结果和详情页本地资源关系，再由当前来源正常重建
- 媒体源删除或配置导入后，索引 state、记录、WebDAV 子目录快照、Emby snapshot 或详情缓存中找不到对应设置来源的孤儿缓存都会按来源清理；在线海报、简介和评分仍保留，播放历史不作为来源缓存删除
- 本地存储页清理“媒体库索引”走同一失效版本与取消链，同时清持久化和内存态，不再直接只删 Sembast 表
- 旧的应用侧 trace helper 保持静音；正式诊断信息统一进入结构化日志系统

`NasMediaIndexer` 负责的事情包括：

- 文件指纹
- 标题、年份、类型、季集识别
- 目录名 / 文件名里的 `{tmdbid-...}`、`{tvdbid-...}`、`{imdbid-...}`、`{doubanid-...}` 等嵌入式外部 ID 标签清洗，避免污染识别标题、系列分组标题和 metadata 查询词
- 包装目录 / 版本说明忽略，例如 `分段版 / 特效中字 / 会员版 / 导演剪辑版 / 清晰度 / 音轨 / 字幕` 等目录不会再被当成系列名
- 电影版本目录使用保守的兄弟目录规则：同一影片根目录下至少两个技术标签目录同时存在，且所有文件都无明确季集信号时，才会被标记为同一 `movie` 的多个可播放版本；技术标签包含清晰度、音轨/语言（如英语、日语、韩语）、字幕和码率等组合；版本目录下的 `Disc / CD / Remux` 等嵌套组织层会继续沿用外层影片根目录，`S01E01` 等剧集标记和 `4K 12集` 这类剧集包装层不进入该分支
- 结构推断无法确认版本或季集时，索引仍优先采用媒体源下的一级媒体目录作为叶子项名称；文件名仅在文件直接位于媒体源根目录、没有可用目录名时作为最后兜底。电影目录名中的年份等括号内容会原样保留，但发布文件名即使包含目录标题也不会覆盖稳定的目录标题，例如 `两杆大烟枪/Top026.两杆大烟枪...strm` 仍以“两杆大烟枪”入库
- 在线元数据的类型偏好以索引最终类型为准：明确的 `movie` 强制按电影候选匹配，只有 `episode / series` 或尚未明确为电影的识别结果才允许启用系列偏好，避免同名电影被目录启发式误配为电视剧；索引发现旧记录仍为错误 `webdav-series` 类型，或同时为 `movie` 和 `preferSeries=true` 时，增量刷新仍复用该记录，需通过重建索引或显式元数据操作修复，手动锁定的记录不受影响
- 单个电影发布包装目录是上述兄弟规则的窄例外：外层是有效片名、仅有一个“片名 + 年份 / 语言 / 字幕”子目录、子目录内只有一个无季集信号的视频时，直接使用外层目录名并索引为 `movie`；不会把 `strm / quark` 等传输目录当标题，也不会覆盖明确 NFO 标题
- 一级影片目录如果遍历后只有一个直接视频且没有子目录、季集号或 NFO 剧集信息，会在结构分配前锁定为 `movie` 并使用一级目录名作为卡片标题，不会被上层媒体库的剧集候选根误挂为 `webdav-series`；公共 `strm / quark / WebDAV` 目录下其他剧集的证据不会跨片名串入；但若同一片名目录的祖先存在明确季目录、集号、剧集 NFO 或其他强剧集证据，则保留剧集分配，兼容“一集一个文件夹”的剧集布局，结构规则版本变化时旧分组会自动重算
- 非传输目录一旦拥有子媒体目录，子目录和子文件统一归属于该父媒体；无法识别为电影版本或明确季集的子目录按隐式季分配，不会把子目录名或子文件名提升为新的剧名/电影名
- 子目录即使继续包含更深层文件夹，也保持最近父媒体目录的归属；结构分组先按 `sectionId` 与资源路径公共前缀自动剥离来源/分区根，再跳过内置的 `movies / strm / quark / WebDAV / NAS` 等常见包装层，取其后的第一个有效媒体目录作为剧名，不依赖手动过滤设置。只有传输目录之外的父根才能建立剧集分组，例如 `我的事说来话长/剧版/01.strm` 的 `剧版`只能作为隐式季，不能生成第二个系列；同一系列根目录下的特别篇进入第 0 季
- `NasMediaPathPolicy` 是外部存储路径语义的唯一入口：统一解析设置路径/分区路径与资源路径的公共前缀、默认及自定义包装层、首个电影目录、系列标题与结构根、嵌套电影发布目录。`WebDavNasClient` 的扫描分类与 `NasMediaIndexer` 的入库、搜刮和展示分组只消费该策略结果，不再各自维护目录常量和回退链
- 系列路径解析一次返回 `NasSeriesRootResolution`，其中同时包含标题、结构根片段和公共边界状态；展示标题与 `webdav-series` 分组键必须来自同一结果，避免标题使用父目录而分组键使用子目录
- 结构候选根会排除 `movies`、`strm`、`quark`、`WebDAV` 等传输或媒体库包装目录；扫描从具体媒体目录开始时仍保留空相对根作为有效剧集根，兼容分区扫描
- 统一路径规则的作用域版本为 `webdav-v11`；版本变化会使旧作用域重新索引。单资源结构指纹仍独立记录最终 `itemType / season / episode`，供重建索引和诊断比较使用；增量阶段不再用它重新分类已有记录，两种失效机制不可互相替代
- 电影多版本会在详情页 Hero 下方提供直接可见的“播放版本”选择控件；“本地资源”仅按来源分组并负责来源切换，播放版本仅按当前来源展开，两个选择互不混用，版本辅助行统一收口为来源、分辨率、首个格式和文件大小；`.strm` 包装文件的格式和大小不会进入辅助行，只有当前选中版本经详情解析器取得真实地址后才展示源视频格式和大小；NAS / WebDAV 详情路由没有携带原始目录范围时，会使用已经确定的 `sourceId + sectionId + itemId` 读取现有索引，而不是错误地重算整源范围键，因此选中目录索引里的版本不会被隐藏；WMDB / TMDB 匹配统一使用影片根目录名，清晰度和编码等文件名后缀只保留给版本展示，明确匹配的 NFO / sidecar 标题优先
- `顶层推断目录` 仅补充非标准自定义包装层；来源根、所选分区根和内置常见包装层由扫描上下文自动过滤。识别到剧文件或季目录后，命中额外配置的目录名会停止继续向上推断，并回退到下一级已推断目录或文件名
- 综艺/节目文件名轻量识别，例如 `第X期`、`01 会员版` 这类“集号 + 版本说明”形式会继续归到对应集，而不是把版本说明当标题主体
- 结构已经确认属于同一剧集分组时，如果同组中尚无显式季集标记的文件全部具有 `数字 + 分隔符 + 标题` 前缀，则该数字作为稳定集号参与排序与聚合；因此 `1 / 2 / 10 / 28` 按数值顺序展示并保留缺号，不把这条规则扩散到未确认类型的普通电影目录
- sidecar 读取
- `streamdetails`
- 外部 ID 提取
- `WMDB / TMDB` 在线补全，并继续保留上游返回的 `IMDb ID / IMDb` 评分标签
- 对开启目录结构推断的剧集条目，`WMDB / TMDB` 先统一使用目录推导出的剧名匹配，同剧各集共享进行中或已缓存的系列结果，不再将每个单集文件名反复提交给在线搜索；可选的“剧集复用系列级图片”还会跳过单集 still 请求，并把匹配年份固定为系列目录年份（目录无年份时统一使用无年份键），避免单集上映年份拆散系列缓存
- `MediaItem` 生成
- 剧集父子关系聚合
- 电影多版本聚合以影片根目录为边界：媒体库只生成一个代表卡片，底层索引保留每个真实资源（包括版本目录下的嵌套文件），详情页的“播放版本”再按可播放性、元数据完整度和画质排序展开。该结构规则使用条目级指纹；增量只处理新文件，旧误分类需通过重建索引或显式元数据操作修复，不通过整库 schema 失效迁移
- 目录名里如果能识别出明确季号，例如 `Season 1`、`S02`、`SE08`、`第2季`、`Stranger.Things.S02.2160p.BluRay.REMUX`，会直接把这一层当作季目录
- `SE08.06` 这类文件名会同时提供季号和集号；`陈鲁豫 · 慢谈 #19 .../video.strm` 这类单集目录会跳过集目录标题，使用上一级作为剧名并归入第 1 季
- 对 `2.巴以 / 5.美国 / 9.韩国` 这类“数字 + 标题”的专题目录，会额外要求同级里存在多个同类兄弟目录，避免把普通数字目录误判成季
- 明确剧名下面的多个年份分组目录（如 `2025 / 2026（4K）`）保留原目录名作为季名，索引与在线系列查询都继承上级剧名；`4K 12集` 这类只表达画质、版本或总集数且看不出季名的目录会折叠为包装层，文件有明确季号时按文件季号归组，否则进入默认季；媒体源顶层的纯年份目录不会因此被强制吞并
- 当年份已经作为独立字段识别时，WMDB / TMDB 客户端会从查询标题末尾移除同一个年份；纯年份标题不会被清空，标题中不同年份也不会被误删
- `LocalStorageCacheRepository` 会将 `16ms` 内并发到达的详情目标保存合并为一次序列化写入，并在编码结果与最后落盘内容完全一致时跳过写入；清理和其他详情缓存变更仍通过同一 mutation tail 保持串行
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
- 如果网络存储里开启了“同步删除夸克目录”，并为它选中了监听的 `WebDAV` 目录，那么只要删除命中了这些目录下的文件或文件夹，就会按当前夸克保存目录去匹配并同步删除对应影片或剧集目录
- `TV` 模式下媒体库筛选、分区入口、分页按钮都使用可聚焦控件，并尽量恢复到上次浏览位置
- 媒体库卡片读取详情缓存时也会复用批量缓存读取，不再为同一批条目逐条扫描本地详情 payload
- 媒体库当前可见页现在也支持切到“静态快照”模式；关闭运行时 overlay 后，只会在当前分页首次装配时做一次缓存合并，后台 metadata 更新不会再把可见页之外的条目带进重算

### Quark

`Quark` 媒体源当前走“目录直连”模型：

- 复用 `设置 -> 内容与来源 -> 网络存储 -> 夸克云盘` 中保存的全局 `Cookie`
- 通过选择一个夸克目录，把该目录作为本地媒体源根目录
- 可继续选择根目录下的子目录作为分区范围
- 索引、结构推断和在线搜刮配置复用 `WebDAV` 同一套外部存储扫描与 `NasMediaIndexer` 规则，包括本地 sidecar、顶层推断目录和“剧集只按剧名层级搜刮”
- 媒体库读取时递归列目录，直接把视频文件映射成 `MediaItem`
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
- 详情页与人物作品页已经收口到 `RetainedAsyncController`；页面 inactive、切回前台或播放期间页面让路时，会优先保留最近一次已解析结果
- 详情页在 inactive 时会取消当前匹配 / 刷新会话，但不会再无条件失效成功缓存；重新回到页面时优先复用已有详情结果
- 详情页在 inactive 时也会解除详情 provider 订阅并卸载剧集、剧照等延迟内容；最近一次成功结果继续由保留态控制器持有，返回页面时无需为了释放隐藏页面负载而牺牲已取得的数据
- 网络图片在展示层支持候选图回退，主图 `404` 或解码失败时会自动尝试下一张候选 artwork；全部候选失败会清空当前失败 Future 并有限重试，持久化图片解码失败时同时淘汰对应磁盘条目
- 详情页已经移除内联字幕搜索与外挂字幕选择；在线字幕搜索只保留在播放器页与独立字幕搜索页，仍按 `设置 -> 播放 -> 字幕` 里的配置使用 `ASSRT API / OpenSubtitles / SubDL`
- 详情页不再把字幕候选或选中项写入详情缓存，也不会在进入播放器前向播放目标注入外挂字幕；字幕选择改由播放器页会话独立持有
- 详情页资源信息区可直接切换播放器；这个入口最终会调用 `SettingsController.setPlaybackEngine(...)`，因此会和设置页里的全局默认播放器保持同一份持久化值

当前详情页与元数据链路还额外承担这些能力：

- 顶部 Hero 优先使用背景图，不再重复放置海报；文字覆盖区域单独加阴影，未覆盖区域保持原图
- 非 TV 使用标准详情 Hero；TV 固定使用精简详情 Hero
- `TMDB` 已接入 `poster / backdrop / still / profile / logo` 等图片字段，并把 `TMDB x.x` 写入统一评分标签链路；当前不再主动去 `IMDb` 搜索信息，`IMDb` 相关标签只会在上游 `WMDB / TMDB` 已返回时参与展示和保存
- 详情页评分标签会按来源归一去重；`豆瓣 / IMDb / TMDB` 各最多保留一条，避免 seed target、详情缓存和后续在线补全合并后出现重复评分标签
- 人物头像统一来自 `TMDB profile`，详情页公司 Logo 来自 `TMDB production_companies.logo_path`，不再把 `networks` 混作公司展示
- 详情页公司 Logo 位于资源信息之后的页面底部，使用带柔和高对比度背景卡片的单行横向 `PlatformRail`，超出可视区域时可左右滑动，TV 端每个 Logo 都有独立焦点目标并带轻微放大提示，不再通过多行 `Wrap` 换行
- `MediaItem` 只持久化演职员姓名，`MediaDetailTarget.resolved*Profiles` 负责无头像时的姓名占位；占位不写入真实 profile 列表。详情缓存、资源匹配和 TMDB 结果通过 `mergeMediaPersonProfiles(...)` 合并，同名条目优先保留已有顺序并用非空头像升级。NAS 索引已有完整文字元数据但没有人物图时，只允许一次面向 `TMDB profile` 的详情补全，不重新请求 WMDB
- 演职员头像可跳转到人物关联影片页，人物作品列表继续复用首页同款海报卡片；卡片右上角会优先显示题材/类型标签，左下角继续显示可用评分标签
- 剧集详情里的单集卡片已拆成两个入口：图片区继续走播放，图片下方的简介区进入单集详情
- NAS / WebDAV 的系列与季层级会随来源索引缓存一次构建，并按分区直接查找；切季和重新进入详情页不再重复扫描、分组整个来源索引
- 单集横排继续使用惰性列表；`TV` 单集图纳入全局四路图片加载门，卡片离开视口或页面失活时会取消尚未取得 permit 的任务；gate 直接追踪活动 permit，并为每个 permit 设置 `8s` 自恢复租约，避免隐藏组件漏释放后让全局图片队列永久停住
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
- 人物关联影片页支持按年份新到旧 / 旧到新排序，也支持按类别筛选；排序与筛选都基于已拿到的人物作品结果在本地完成

详情页本地资源匹配当前还有这些约束：

- 自动匹配由 `设置 -> 元数据 -> 元数据匹配 -> 自动匹配本地资源` 控制，默认关闭
- 当自动匹配关闭时，详情页只保留“重新匹配资源”这一条手动触发路径
- `设置 -> 内容与来源 -> 媒体源管理 -> 详情页匹配来源` 会直接限制详情页本地资源匹配的实际扫描范围；只会扫描被选中的已启用 `Emby / WebDAV / Quark` 来源
- 如果“匹配来源”未单独勾选，则默认使用全部已启用来源；如果保存的来源 ID 已失效，则自动回退到全部已启用来源
- 如果详情页 seed target 本身来自媒体库卡片或指定来源模块，并已经带了 `sourceId / sourceKind / itemId / sectionId` 这类来源上下文，匹配链路会先优先处理这个来源，而不是把所有来源完全等价并行处理
- 对非 `series` 聚合页，如果入口 target 本身已经是该来源下的已解析资源，候选列表会先直接补入这条入口资源；手动重新匹配时也会跳过对这个入口来源的重复扫描
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

搜索页会并发组合这些来源：

- 本地媒体源
- 在线搜索 provider

当前在线 provider：

- `PanSou`
- `PanSou` 认证优先级为完整用户名/密码登录取得新 JWT，其次才是手动 Token；这样同时保存两类认证信息时不会被过期 Token 抢先拦截，账号信息不完整时仍保留纯 Token 模式
- `CloudSaver`

搜索结果会在 provider 侧和页面侧继续做：

- 相同链接去重
- 网盘类型过滤
- 过滤词
- 强匹配
- 标题长度限制
- 配置夸克 Cookie 后，在线夸克结果进入页面级有限并发验证队列；搜索任务和链接验证全部完成后才向页面提交聚合结果。明确取消、过期、不存在或提取码错误的结果不进入列表，网络超时和限流保留为“暂未验证”，避免把瞬时网络故障误判成死链，也避免卡片先出现后消失
- `TV` 模式额外会把最近搜索词和上次选择的搜索来源保存在本地，减少重复输入和重复切换
- 搜索页顶部来源筛选、最近搜索和媒体库筛选统一复用 `StarflowChipButton` 这一类通用按钮规格，普通端横向列表容器也与统一按钮高度保持一致，避免单页样式漂移或裁切
- 空关键词会直接短路，不再启动整轮 provider 搜索
- 多来源结果会先在页内聚合，再通过短定时批量提交 UI；不会再每个来源一返回就全量排序并触发一次大 `setState`

搜索来源分成“可见 tab”和“当前选择”两层：

- `设置 -> 内容与来源 -> 搜索服务管理 -> 搜索来源` 只决定搜索页展示哪些本地媒体源和在线 provider tab
- 如果该设置未单独勾选任何来源，则搜索页展示全部已启用来源 tab
- 搜索页来源 tab 支持多选并保存在本地；每次实际请求以搜索页当前选中的 tab 为准，“全部”会并发搜索所有当前可见来源
- 设置变更后会保留仍然可见的已选 tab；如果已保存的 tab 全部失效或被隐藏，则自动回退到“全部”
- 从详情页进入搜索时，会先恢复搜索页保存的 tab 选择，再使用详情片名自动发起搜索，避免初始化竞态误用默认“全部”
- 从详情页进入搜索时，会复用同一个 `SearchPage`，但通过 `/detail-search` 路由额外补上返回工具栏，并维持无转场进入，减少 TV / 低性能设备上的切页成本

搜索后的联动链路是：

1. 保存到夸克
2. 按网络存储里的“STRM 触发等待时间”延迟触发 `SmartStrm` Webhook
3. 按“索引刷新等待时间”延迟执行指定媒体源的增量刷新；若保存结果包含新文件，刷新会在等待结束并停止旧任务后，先按来源删除持久化 WebDAV 目录快照，再读取真实目录，避免服务端目录指纹未变化时复用旧子树。保存未产生新文件的自动刷新可保留快照；媒体库手动触发的增量刷新始终先清快照，两类刷新都只为新文件建立索引和补元数据
4. 首页和媒体库读取到新的索引或缓存

同步删除会优先按当前 `sourceId`，其次按唯一来源名对齐监听目录；媒体源域名或挂载前缀变化时，设置协调器用稳定相对目录边界（例如 `strm/quark`）一次性改写到当前根并持久化，不把旧地址继续留作运行期来源。普通 WebDAV 删除仍要求远端成功；仅当路径明确命中夸克同步目录且服务返回 `403 / 405` 时，允许改由夸克源目录删除，夸克删除成功后才清理本地索引。

自动增量刷新的目标媒体源在网络存储里单独选择，默认会选中全部当前可刷新的来源。

网络存储页里的夸克链路当前还提供目录运维能力：

- 可直接浏览当前默认保存目录和子目录
- 可单独删除文件或文件夹
- 可一键清空当前目录
- 删除动作当前走夸克回收站语义，不做应用侧永久粉碎
- 可选开启“同步删除夸克目录”，让命中已选 `WebDAV` 监听目录的删除动作联动删除当前夸克保存目录里的对应影片或剧集目录

## 10. 播放链路

播放器页基于 `media_kit`，当前是“三种播放内核”分支：

- 内置播放器负责应用内播放、字幕增强、续播和跳过逻辑
- App 内原生播放器负责在 Android / iOS 上以原生容器页承载播放，尽量减少 Flutter 合成层干扰
- 系统播放器负责把播放地址交给平台默认视频应用
- Android `ExoPlayer（原生）` 的音频输出由 `NativePlaybackAudioPolicy` 和 `NativePlaybackRenderersFactory` 统一决策；`自动 / PCM 兼容 / 设备直通` 来自全局设置，也可在播放中按当前进度重建会话。TV 的自动模式遇到 `DDP / E-AC-3` 时禁用压缩音频直通，并加载仅包含 AC-3 / E-AC-3 解码器的 Media3 FFmpeg 扩展输出 PCM；视频渲染器与播放地址不变

主流程大致是：

1. 进入播放器页
2. `PlaybackStartupCoordinator` 解析播放目标，读取本地续播和按剧跳过偏好，并得到路由动作
3. 如果是 `Emby / Quark`，会在这一步补齐真实播放源和请求头
4. `PlaybackStartupExecutor` 按用户选择的播放器内核执行系统播放器、原生容器或内置 MPV 分支
5. 如果执行结果要求继续走内置 `MPV`，则进入轻量探测和等待态展示
6. 调用内置 `MPV` 打开链并应用启动期调优
7. 失败自动重试，最多 `3` 次
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
- 非 `TV` 的内嵌 `MPV` 当前使用 Starflow 自己的轻量播放叠层，而不是 `media_kit` 默认控制条：
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
  - `player_page_runtime_actions.part.dart`：续播、跳过、字幕、外挂字幕、在线字幕、启动 probe
  - `player_page_controls.part.dart`：返回、进度、选择器、播放设置、视频 surface
  - `player_playback_options_dialog.dart`、`player_playback_overlays.dart`、`player_playback_dialogs.dart`、`player_tv_playback_widgets.dart`、`player_network_speed_label.dart`：纯展示层组件；旧自定义 `PlayerMpvControlsOverlay` 已删除，非 TV 统一使用 media_kit Adaptive 控制层
- `lib/core/utils/playback_trace.dart`、`subtitle_search_trace.dart`、`metadata_search_trace.dart` 与 `detail_resource_switch_trace.dart` 仍保留调用点，但当前实现都已静音，不再产生运行时输出
- 内置 `MPV` 现已把 `ISO` 打开路径统一纳入同一条执行链：本地路径 / `file://` / UNC 优先尝试 `dvd-device / bluray-device`，远程 `ISO` 则直接回退普通 `Media(...)` 打开，并在回退前清理残留的 `dvd-device / bluray-device / http-header-fields`
- `TV` 分支当前仍保留自定义播放叠层：
  - 电视场景继续走“首层极简 + 二层高级”的 `NoVideoControls + 遥控器快捷键` 模式
  - 内置 `MPV` 首层只保留播放状态、进度、字幕和音轨快捷入口；菜单键 / 下键进入二层播放设置
  - Android 原生容器页首层会隐藏快进快退、外挂字幕、字幕偏移、在线搜字幕等高级按钮，改由二层“更多操作”入口承载
  - 这样可以把控件数量压到最少，并避免在当前 `TV` 分支里维护另一套复杂控制条
- `App 内原生播放器` 额外已接入：
  - 原生控制条与进度条
  - 本地续播记忆
  - 在线字幕搜索
  - Android 原生音轨/字幕选择、播放中音频输出切换、外挂字幕加载与外挂字幕偏移
  - Android 原生播放设置弹窗一级只保留本剧跳过片头片尾、音轨、字幕和选择剧集；播放速度、音频输出、主字幕大小、主/副字幕位置、副字幕大小、在线查找字幕、加载外部字幕和字幕偏移全部收进列表最下方的“更多”二级弹窗
  - Android TV 原生控制层只让播放/暂停参与遥控器焦点；右下角字幕、音轨和更多三个按钮仍保留显示与点击，但不再进入方向键焦点链，字幕/音轨/设置改用菜单键、字幕键等电视快捷键打开，避免底部右侧控件抢焦点
  - Android 原生播放器的主字幕大小可在“更多”里按 `20–78号` 调整，主/副位置和副字幕大小按百分比调整；改完立即重新套用 `NativeSubtitleStylePolicy / NativeDualSubtitleController`，并通过原生播放回调调用 Flutter `SettingsController` 的字幕样式窄保存入口。设置页、MPV 与 ExoPlayer 因而共用同一份全局值，不再保留原生会话临时覆盖
  - Android 原生音轨与字幕轨选择使用单选即应用的轻量弹窗；点选轨道或“关闭”会立即更新 Media3 `TrackSelectionParameters` 并关闭弹窗，不保留额外的确定步骤
- Android `NativePlaybackActivity` 使用 `Theme.AppCompat.NoActionBar` 派生的全屏黑色主题；音轨、字幕轨与音频输出都使用原生单选对话框，选中即应用，不依赖额外确定按钮
  - Android 原生字幕由 `NativeSubtitleStylePolicy` 把 Flutter 的 `20–78号` 设置分段映射到 `3.5%–9%` 画面高度，默认 `32号` 对应 Media3 的 `5.33%`；主位置默认 `80%`，副位置默认 `90%`，副字幕默认主字号的 `50%`。`SubtitleView` 默认使用 Canvas、白色中粗字、透明背景与黑色描边，保留 cue 内嵌样式但忽略内嵌字号；检测到系统 `CaptioningManager` 已启用时采用系统样式与字号，同时在双字幕模式保留应用设置的主/副布局
- 播放器页与独立字幕搜索页复用同一个 `OnlineSubtitleRepository`；仓库内部已经收口为 `searchStructured(...)` 一条结构化链路
- `searchStructured(...)` 会基于当前播放目标、详情外部 ID 和本地文件信息组装 `OnlineSubtitleSearchRequest`，优先尝试文件哈希、`IMDb ID / TMDB ID`、季集号、年份和标题
- 结构化源当前支持 `ASSRT API / OpenSubtitles / SubDL`；`ASSRT` Token 来自设置页，未填写时不会访问 API；`OpenSubtitles` API Key 通过 `--dart-define=STARFLOW_OPENSUBTITLES_API_KEY=...` 注入，账号密码来自设置页；`SubDL` API Key 直接来自设置页
- 多字幕源搜索会并行执行；`OpenSubtitles` 登录态会做短时会话缓存，避免同一轮搜索里重复登录
- 结构化搜索阶段会先在应用内预下载、验证并筛掉不可直接挂载的结果；页面只展示可直接挂载的 `SRT / ASS / SSA / VTT` 或可解压 `ZIP` 字幕
- 下载后的字幕会写入当前会话的临时目录 `starflow/online_subtitles/session-.../downloads`；当前不做 `cache-hit` 复用，重新搜索或重新选择时都会生成新的临时文件
- 播放器页本身不再直接承载全部启动决策；目标解析、路由判定与执行分支已经拆到独立 application 文件，页面层主要负责装配、等待态和内置 `MPV` 运行期行为，便于 controller 级测试和后续替换策略
- 播放器页 presentation 也已进一步拆开：`player_page.dart` 主要保留会话和流程编排，控制叠层、启动等待态、播放设置弹窗与平台会话子树分别沉到 `presentation/widgets` 与 `player_page_*.part.dart`

设置分类当前按能力拆分：

- 设置首页按内容来源、元数据、播放、界面、性能后台和数据维护分类；不再保留 `PerformanceSettingsPage` 中转目录
- `InterfaceSettingsPage` 和 `TaskSchedulingSettingsPage` 分别由“界面效果 / 任务调度”直接打开；自动匹配本地资源归入元数据匹配页，首页单击清理归入界面效果页
- 播放分类下现在是「播放 / 字幕 / MPV」三个同级一级入口，不再保留“播放器与字幕”混合页和“MPV 调优”独立页
- `MediaSourceSettingsPage`、`SearchServiceSettingsPage` 和 `NetworkStorageSettingsPage` 同属内容来源；网络存储的夸克、SmartStrm、同步索引编辑器通过 section 收口为三个三级入口
- `playback_settings_page.dart`、`subtitle_settings_page.dart` 与 `mpv_settings_page.dart` 三个同级页面分别承载播放器主偏好、字幕表单和全部 MPV 设置；日志预览组件、元数据测试卡片也分别下沉到 `logging_settings_widgets.part.dart` 与 `metadata_match_settings_widgets.part.dart`
- 媒体源编辑器把 `Emby / WebDAV / Quark` 连接表单下沉到 `media_source_editor_forms.part.dart`，WebDAV 路径统一复用 `WebDavDirectoryPickerPage`，不再维护第二套私有目录浏览器
- 透明磨砂与简化装饰、减少动画与静态导航、静态 Hero 与精简 Hero 分别合并为三个原子更新的界面开关；菜单栏自动隐藏和 Hero 背景继续独立保存
- 非 TV 使用标准详情 Hero 与标准播放界面，可单独设置激进 MPV 调优
- `TV` 固定使用无缩放 / 无阴影的轻量焦点、精简详情 Hero 与精简播放界面，并固定关闭自动更新卡片信息；固定项不在 TV 设置页展示开关
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

- Android 原生播放器容器页当前使用原生 `Activity + Media3/ExoPlayer` 承载播放，在 UI 中命名为 `ExoPlayer（原生）`；它会跟随设置选择 `自动 / 硬解优先 / 软解优先` 和独立的音频输出模式
- Android 原生播放器每次轨道变化都会把音频轨的 MIME、编码标记、声道数、采样率、支持状态和选中状态写入结构化 native 日志；初始化日志同时标记 `audioOutputMode / forcePcmAudioOutput / ffmpegAudioDecoder`
- Android 原生播放器的字幕菜单不使用 Media3 泛化轨道名称，而由 `NativeSubtitleTrackLabelPolicy` 按内置 MPV 的“标题 · 语言 · 默认/强制”顺序生成；`und / zxx` 不显示为语言，外挂字幕优先显示文件名
- Android 原生播放器的可选双字幕模式由 `NativeDualSubtitleController` 承担：同一 Exo 会话使用主/副两个文本渲染器分别解码两条分离的文本字幕轨，动态能力路由只让副渲染器认领英文轨，再按独立主/副位置输出两个 cue；副字幕字号、主位置和副位置从 Flutter 设置传入，并可在原生“更多”中覆盖当前会话。普通字幕模式仍只启用主文本渲染器，PGS/VobSub/DVB 图片字幕不进入双字幕候选
- Android 原生播放器的跨集字幕恢复由 `NativeSubtitleSessionPreferencePolicy` 匹配新的 `TrackSelectionOverride`；双字幕恢复成功后再重新配置 `NativeDualSubtitleController` 的主/副路由，不保存上一集的 Media3 group 或 override 实例
- 非 Web 内置 MPV 使用原生 `sid / secondary-sid` 选择两条分离的内封文本轨，同时向 libmpv 写入 `sub-pos / secondary-sub-pos / secondary-sub-scale`；由于当前 `libass=false`，画面上的主/副字幕由 Starflow 自定义 Flutter 叠层分别渲染，保证窗口态与全屏态都使用独立位置和字号。跨集时由 `PlaybackSubtitleSessionPreference` 分别匹配新的 `sid / secondary-sid`。图片字幕和临时外挂字幕不进入特殊模式。播放设置一级通过“更多”打开二级页，二级页同时提供字幕布局、后台播放、手势、卡顿恢复和性能调优开关
- 非 Web MPV 控制层左上角以返回按钮作为第一个控件，不保留人为前置间距；其右侧网速标签使用轻量轮询读取 libmpv `cache-speed`，展示当前缓存下层 I/O 读取速度。桌面 / 手机 Adaptive 控制层和 TV chrome 复用同一排列与网速组件
- Android 原生播放器同时记录视频轨 MIME、编码、尺寸、色彩信息与支持状态；检测到存在视频轨但当前设备全部不支持时，会以 `static=false` 重新请求 Emby 转码流并从原进度继续
- Android 原生播放器额外包含与 Media3 同版本的 `media3-exoplayer-hls`；仅对 SmartStrm 且文件名含 `#/%23` 的原生启动执行响应头级预检，按最终 Content-Type 直接选择 MP4/HLS，不持久化短期重定向地址；预检失败时仍由 `NativePlaybackHlsFallbackPolicy` 在首次解析错误 `3003` 后保留进度切换 HLS 一次
- Android 原生启动通过 `buildDeferredNativeEpisodeQueue` 携带当前季的完整未解析队列并保留真实 `currentIndex`，只用已解析目标替换当前条目；原生选集、上一集、下一集和播放结束自动续播统一通过 `starflow/native_playback_resolver` 回调 Flutter，按选中的单集执行 `PlaybackTargetResolver` 和必要的 SmartStrm MP4/HLS 探测。异步解析期间旧播放器不释放，成功后才更新队列条目并切换，失败或会话变化则保留当前视频
- 内置 MPV 的 TV、Material 和 Material Desktop 控制层都直接消费 `PlaybackEpisodeQueue`，不使用 media_kit 内部单媒体 playlist 的上一项/下一项按钮；三端统一显示边界可用状态和完整选集弹窗。手动选集、相邻集及自动续播最终收口到 `_switchPlaybackQueueIndex`：先用 `PlaybackTargetResolver` 解析目标单集并校验可播地址，成功后才保存旧集进度、关闭旧播放器并初始化新集，解析失败时队列索引和当前播放器保持不变
- Flutter、Android MediaSession 和 iOS MPRemoteCommandCenter 通过 `hasEpisodeQueue / hasPrevious / hasNext` 共享系统媒体动作语义：存在多集队列时隐藏 10 秒快退/快进并发布上一集/下一集，普通影片则继续发布快退/快进与进度拖动；系统命令不再在剧集边界回退成 seek。MPV、Android 原生和 iOS 原生的切集成功路径均不显示额外提示，只保留解析中与失败反馈
- Android 原生播放器复用每秒运行循环做续播采样，实际仍按约 `10s` 的位置差值节流落盘；内置 `MPV` 和 iOS 原生播放器使用同一量级，生命周期暂停、返回、切集和关闭路径会强制保存
- Android / iOS 播放记忆仓库使用带 `reload()` 的 legacy SharedPreferences，与原生播放器共享物理键 `flutter.starflow.playback.memory.v1`；首次读取会按 `updatedAt` 合并并迁移旧异步存储快照，返回前台时递增播放历史 revision 使首页和详情页重新读取
- Android 原生播放器每 `10s` 记录一次位置、时长、缓冲位置、缓冲比例、播放态、首帧状态与视频尺寸；位置不连续事件单独记录旧/新位置和 Media3 原因码
- Android 原生播放器为当前 Exo 会话创建独立 `DefaultBandwidthMeter`，控制层完全显示时在右上角展示最近一次真实传输采样；手机 / TV 控制布局分别覆盖 Media3 的底栏动画高度，使两阶段自动隐藏的第一阶段把剩余进度条下沉到实际底边
- iOS 原生播放器容器页当前使用原生 `AVPlayerViewController` 全屏承载播放，不退出 App；它会复用同一份续播记忆，并补了在线字幕搜索入口，但解码走系统链路，当前不提供软硬解切换或字幕偏移
- iOS 原生播放器切集前从 `currentMediaSelection` 读取当前系统字幕选择，下一集的 legible group 可用后按语言与显示名称恢复；没有匹配项时回退全局自动字幕策略
- 详情页“从头播放”从当前选择生成 `allowResume=false` 的目标，“继续播放”从历史记录恢复具体目标并设置 `allowResume=true`；该字段在播放地址解析后保持不变，内置 `MPV`、Android `ExoPlayer` 和 iOS `AVPlayer` 都以它作为是否读取历史进度的唯一入口语义
- iOS 的播放会话桥接由 `ios/Runner/PlaybackSystemSessionBridge.swift` 承担，`AppDelegate` 会把它绑定到 Flutter channel，用于原生播放会话、遥控器命令和 AirPlay 入口
- Android 系统播放器优先调用原生 `ACTION_VIEW`，并显式标记 `video/*`
- 桌面端系统播放器通过临时 `.m3u` 交给系统默认视频应用
- 重型视频不会再因启发式规则自动改变播放器路径；内置 MPV 仅在当前会话内按片源调整缓冲与解码参数
- 内置 `MPV` 会跟随设置切换解码模式；系统播放器无法稳定回传进度，且解码方式由外部播放器自行决定，因此续播记忆只在内置 `MPV` 和 App 内原生播放器里生效
- 自动跳过片头片尾当前只在内置 `MPV` 里生效
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

当前设置范围包括：

- 媒体源
  - `WebDAV / Quark` 的目录结构推断、本地 sidecar 刮削、顶层推断目录与“剧集只按剧名层级搜刮”
- 搜索服务
- 搜索来源
- 豆瓣账号
- 首页模块
- Hero 来源、展示方式、Logo 标题与背景图
- 网络存储
  - 夸克保存目录
  - 同步删除夸克目录
  - 同步删除夸克目录对应的 `WebDAV` 监听目录
  - 当前夸克保存目录管理与删除
  - `SmartStrm` Webhook、任务名、`STRM` 触发等待时间
  - 自动增量刷新索引的媒体源选择与“索引刷新等待时间”
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
- 在线字幕优先语言（`简体中文 / 繁体中文 / 英语 / 日语`，可多选；不选时按字幕结果和系统语言自动处理）与单次最多验证条数
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
- 字幕收拢到独立的“字幕”一级页：字幕默认状态、默认字幕、主字幕大小、主/副字幕位置、副字幕大小、在线字幕来源与凭据、在线字幕优先语言、单次最多验证条数
- 主字幕大小、主字幕位置、副字幕位置和副字幕大小属于全局字段；设置页的步进项每次点击立即入有序保存队列，MPV 播放内修改走 `savePlaybackRuntimePreferences(...)`，Android 原生播放内修改经 Flutter 回调走 `savePlaybackSubtitleStylePreferences(...)`，三条路径最终写同一组 `AppSettings` 字段
- 主/副字幕位置统一使用 `50%–100%` 范围；设置页使用 `1%` 精细步进，MPV 播放内“更多”和 Android 原生位置选择器使用 `5%` 快速步进。副字幕大小继续使用 `5%` 步进
- `playbackSubtitleStyleDefaultsVersion` 只负责一次性把旧版未标记的副字幕 `75%` 默认值迁到 `50%`；新版本中用户明确保存的 `75%` 不再被重写
- 内置 MPV 的触屏交互、卡顿自动恢复和激进性能调优保留在全局设置的独立“MPV”一级页；播放器内的播放设置一级只提供“更多”入口，二级页复用同一组持久化字段，并额外集中提供后台播放与主/副字幕布局
- 三个页面都不再维护需要手动提交的页面草稿：选择、开关和步进项修改后立即排入持久化队列，文本输入使用 `250ms` 合并窗口；返回时会先把最后草稿加入有序写入队列，再立即关闭页面，不再显示保存确认框或工具栏提交按钮
- 三个全局设置页各自只写自己那段字段：播放页走 `savePlaybackPreferences(...)`、字幕页走 `savePlaybackSubtitlePreferences(...)`、MPV 页走 `savePlaybackMpvPreferences(...)`；播放器内二级“更多”使用 `savePlaybackRuntimePreferences(...)` 原子保存其当前完整快照，避免连续操作互相覆盖
- 媒体源、搜索服务、豆瓣账号和网络存储编辑页复用 `SettingsAutoSaveCoordinator`：以当前配置 JSON 作为指纹去重，连续修改使用 `250ms` 防抖并按队列顺序持久化，返回时立即冲刷最后草稿，删除前取消尚未开始的保存，避免删除后被旧任务重新创建
- 媒体源资源身份由类型、endpoint / 根目录及服务端资源身份字段组成；删除来源或改变资源身份时先持久化新设置，再提升来源失效版本、等待旧扫描结束并清理来源级缓存，防止旧任务在清理后反写
- 本地、文件和局域网导入在落盘前统一调用媒体源引用协调：移除不存在来源的首页模块、匹配/搜索来源、同步目录和刷新目标；可确认相对目录的新地址会保存到当前媒体源根，无法确认的旧引用不会继续使用
- 整页编辑不再保留保存按钮或未保存确认；单个文本输入弹窗里的“保存”仍只负责把该输入提交回当前草稿。新建媒体源/搜索服务在草稿没有实际内容时不会生成空记录
- 详情页资源信息区对播放器内核的切换会直接复用同一个 `setPlaybackEngine(...)` 写回入口，因此不会出现“详情页一种默认、设置页另一种默认”的分叉
- `AppSettingsPerformanceX` 只负责平台固定规则和少量有效值派生；独立子项不会因其它开关数量变化而自动联动
- 设置反序列化只读取当前独立性能参数；旧高性能标记、旧 Hero 开关/模块别名和旧 IMDb 自动匹配字段不再转换
- 搜索源只保存搜索服务字段；旧搜索源里的夸克、保存目录和 SmartStrm 字段不再读取，相关配置只以 `networkStorage` 当前结构为准
- 本地、文件和局域网导入都要求设置 JSON 明确包含 `schemaVersion: 2`；本地键为 `starflow.settings.v2`，不匹配时直接拒绝导入或回到默认设置，不执行跨格式迁移
- “自动更新卡片信息”默认可在普通端按需开关；`TV` 端固定关闭，设置页不显示重复开关

设置编辑页在 TV 下还额外做了输入方式分流：

- 文本项优先显示为可聚焦设置条目
- 需要编辑时再进入独立弹窗输入
- 避免页面级 `TextField` 长时间占据焦点并把遥控器操作锁在系统键盘里
- 媒体源、搜索服务、豆瓣账号、网络存储、播放、配置管理等主要设置页，当前尽量共用同一套页面骨架和按钮分类，减少页面间的操作分叉
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
- 所有设置导入入口只接受当前 `schemaVersion: 2`，旧格式不会做字段映射或补迁移
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
- 长列表中的焦点会尽量停在屏幕中部，滚动容器随焦点一起平滑移动
- 媒体源、搜索服务、豆瓣账号、网络存储等编辑页里的文本项会先显示成可聚焦条目，再进入独立编辑弹窗
- 播放、界面与性能后台页面从一级分类直接进入，每页首个条目具有明确 TV 初始焦点
- 多数设置编辑页已经统一到同一种工具栏、保存按钮、危险操作按钮和选择条目样式
- 仍有少量弹窗和编辑流需要继续补齐焦点细节

## 12. 本地持久化

### SharedPreferences

用于保存：

- 应用设置
- 当前设置 payload 使用 `starflow.settings.v2`，并要求 `schemaVersion: 2`
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

- 当前会话下载的在线字幕 `starflow/online_subtitles/session-.../downloads`
- 同一会话里再次选择同一字幕时，可优先复用已下载文件
- 结构化在线字幕验证缓存 `starflow/validated_online_subtitles`
- 新链路预下载后筛出的可直接挂载字幕文件

### Sembast

用于保存 `WebDAV` 元数据索引。指定分区的读请求会在 Finder 层组合 `sourceId + sectionId` 条件，只把目标分区记录交给 Dart。

### 持久化图片缓存

通过 `persistent_image_cache` 抽象统一访问，不同平台走各自实现或 stub。

当前图片缓存策略已经补齐这些约束：

- identity 按 `URL + 归一化 headers` 区分，避免不同鉴权请求误命中同一份缓存
- 磁盘层会保存 metadata，并按 `30` 天 TTL 做过期判断
- 远端失败但本地还保留旧字节时，会优先回退到 stale bytes，减少短期网络抖动导致的图片缺失
- 单次网络读取最多等待 `15s`；组件在全部候选失败后按 `1s / 4s / 12s` 重试，失败与恢复分别写入 `image.load` 日志
- raster 解码失败会同步从 Flutter image cache 与持久化缓存中淘汰对应条目，下一次重试重新请求原图
- 内存层按条目数和字节预算双阈值淘汰，尽量减少重复 decode

## 13. 平台分支

项目有一层明确的平台适配：

- Android 会识别 `TV` 设备
- TV 模式切换为左侧窄栏磨砂菜单和焦点式交互
- 左侧菜单是否自动隐藏由设置控制；开启后会由菜单自身的焦点范围直接同步显隐，而不是监听全局焦点后延迟推断；隐藏中的菜单会被排除出寻焦树，已聚焦菜单则不会压缩成零宽布局
- 设置首页及部分设置子页会优先使用更适合遥控器操作的可聚焦按钮与入口
- Android 主清单显式声明了 `INTERNET`、`ACCESS_NETWORK_STATE` 和明文流量支持，保证 TV 端能访问局域网与在线元数据资源
- Android 当前实际最低兼容版本固定为 `API 23 / Android 6.0`
- Release APK 当前启用了 `v1 + v2` 签名，兼容老一些的电视安装器
- 当前 Release APK 仍使用本机 debug keystore 签名；如果设备里已有其他签名的旧版 `com.example.starflow`，覆盖安装会失败，需要先卸载旧包
- `TvMenuButtonScope` 用来把菜单键语义统一上抛到页面壳
- `TvReturnToTopScope` 与 `TvDirectionalFocusBoundary` 只负责页头回顶和方向越界；普通候选仍由 Flutter 默认策略决定
- 首页、搜索、媒体库、详情与设置页不再挂载空的焦点记忆作用域，也不做坐标校验或反向候选拦截
- 首页 Hero 的翻页焦点只会请求已挂载且可用的按钮；单项 Hero 按左直接回到主菜单。媒体库首页则只让顶部筛选项申请初始焦点，异步加载的合集与网格不再竞争首焦点
- `TvFocusableAction` 在垂直滚动容器里会尝试把焦点项保持在视口中线附近，降低 TV 遥控器纵向浏览时的视线跳动
- `TvFocusableAction` 的焦点视觉态已经改成局部 `ValueNotifier` 更新；TV 固定使用无缩放、无阴影的轻量高亮
- `SettingsTextInputField` 会在 TV 模式下把页面内文本输入改成“设置条目 + 弹窗编辑”交互；弹窗输入框局部保留上下键退出处理，减少焦点被输入法占据的情况
- 配置管理当前按平台分支：
  - Android TV 使用应用内局域网传输
  - Web 使用浏览器下载和本地文件选择器，不需要手填路径
  - iOS / iPadOS 使用原生系统文件导出器与文件选择器
  - 其他 IO 平台继续使用目录 / 文件选择器
- IO / Web 平台对本地数据库、图片缓存、配置导入导出各有分支实现

平台外部图标资源当前也统一走同一条导出链路：

- Android、iOS、macOS、Web、Windows 的外部 App Icon 都由 `tool/generate_brand_assets.py` 生成
- Android TV Banner 也由同一脚本生成
- 启动页首帧图标、Android 启动页主图与 iOS 原生 LaunchImage 也由同一脚本同步生成，且当前只保留主图案本身
- Android 启动器小图标与 TV 横幅里的小方形 Logo 复用同一份 `assets/branding/starflow_icon_master.svg`
- 小尺寸外部图标当前不再做额外锐化，避免星星边缘出现暗边
- 当前约定以 `build/brand_assets/starflow_app_icon_master.png` 作为统一母版，再缩放到各平台资源，避免手工替换时出现偏移或不对称

## 14. 测试覆盖

当前 `test/` 已覆盖的重点包括：

- 当前设置模型与序列化
- 首页装配逻辑
- 首页控制器与 settings slices
- 首页 / 媒体库详情缓存批量读取
- 详情缓存
- 页面级 `RetainedAsync` 保留态控制器
- `Emby / WebDAV` 客户端
- `WebDAV` 识别与索引
- `NasMediaIndexer` 分组、增量刷新和并发预算
- 空库自动重建后台调度
- 元数据客户端
- 搜索 provider 与搜索仓库
- 夸克保存和 `SmartStrm`
- 播放记忆与最近播放排序稳定性
- 播放启动准备与路由判定
- 统一网络错误分类、超时、幂等重试边界与按主机熔断
- 本地日志轮转、脱敏、原生日志合并、预览与导出
- 首页模块和元数据预取的共享并发值及独立首批预算

## 15. 当前架构判断

这个仓库目前最重要的三个判断是：

1. `WebDAV` 的正确方向是“索引优先”，而不是“页面实时扫目录”
2. 详情页不是唯一元数据入口，索引阶段已经承担了大量 enrichment 工作
3. 搜索不是孤立功能，而是资源入库、`SmartStrm` 触发和自动增量刷新索引的上游触发器
