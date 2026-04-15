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

## 2. 技术基线

- 框架：`Flutter`
- 状态管理：`flutter_riverpod`
- 路由：`go_router`
- 播放：`media_kit`
- 设置与轻量缓存：`SharedPreferences`
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
- 本地图片缓存抽象
- 持久化图片缓存的 `URL + headers` identity、磁盘 metadata、过期与 stale fallback 策略
- 通用组件
- 网络图片请求头和调试工具
- `TV` 焦点组件、菜单键动作和焦点记忆
- `TV` 焦点记忆当前通过 `InheritedWidget` 传递，不再把 remember / clear 当成广播式页面重建信号
- `TV` 焦点视觉态已经收敛到 `ValueNotifier + ValueListenableBuilder` 局部更新，并补了 `TvFocusVisualStyle.none`
- `TV` 页面级焦点边界、页头回顶锚点和统一的上下方向焦点兜底
- `TV` 页面级焦点壳与方向动作面板，便于首页、搜索、媒体库、详情、设置等页共用同一套焦点边界
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

## 3.1 近期架构与性能收口（2026-04）

这一轮已经落地的 `P0` 收口主要有这些：

- 首页拆层：`_homeSectionSeedProvider` 负责来源抓取，`homeSectionProvider` 负责基于详情缓存 revision 的轻量装饰；详情缓存变化不再把首页整轮抓取一起打掉
- 首页重建范围收口：普通 section 改成各自独立订阅，`Hero` 当前项和分页状态也改成局部 `ValueNotifier` 监听，减少首页根节点重建
- 首页 presentation 落点也已进一步收口到 `home_page.dart`、`home_page_hero.dart`、`home_page_sections.dart`；页面主文件保留页面级状态、预取和焦点编排，厚的 Hero / section / shell UI 分别下沉到独立 part 文件
- 首页 `Hero` 后台补数新增快照去重与预取协同；同一批条目在首次进入、返回前台和高频 rebuild 时不会重复排队刷新
- 详情缓存批量化：`LocalStorageCacheRepository.loadDetailTargetsBatch(...)` 已接入首页和媒体库的卡片装配链，减少同一批条目的重复本地读取
- 设置粒度收口：`home_settings_slices.dart` 以及设置 / 搜索页里的 slice provider 开始替代整份 `AppSettings` 宽监听，优先只让高频页面订阅自己真正依赖的配置片段
- 页面级保留态异步模式：媒体库、详情页、人物作品页已经改成 `RetainedAsyncController / resolveRetainedAsyncValue`，避免页面 inactive、路由切换和播放让路时重复闪回 loading
- 页面 inactive 任务治理：详情、媒体库、人物作品、搜索等页在失活时优先取消当前会话，而不是顺手 `invalidate` 掉已成功 provider，减少返回页时的重复拉取
- 搜索页渲染收口：结果区切到 `CustomScrollView + SliverList`，让长结果集按需构建，不再一次性把整个列表塞进单个 `Column/ListView`
- 详情页局部状态收口：本地资源匹配、外挂字幕和播放版本选择改成 `ValueNotifier + ValueListenableBuilder`，高频状态变化只刷新资源信息区，不再带动整页详情重建
- 图片缓存收口：持久化图片缓存 identity 升级成 `URL + headers`，并增加磁盘 metadata、`30` 天 TTL、stale fallback 与更稳定的内存淘汰策略；同一候选图的解析/尺寸分析 future 也开始在组件间共享，减少同屏重复拉图与重复解码
- 绘制范围收口：页面背景 glow、桌面横向翻页按钮和海报卡片布局已经分别加上独立重绘边界或局部 notifier，滚动和焦点切换时避免整段区域跟着重建
- 统一性能派生：`AppSettingsPerformanceX` 新增 `effectiveUiPerformanceTier` 及一组 `effective*` 派生入口，路由、导航壳和播放器统一按同一档位判断动画、磨砂、自动隐藏和轻量播放 UI
- 读链路与后台任务分离：空索引时的自动重建通过 `EmptyLibraryAutoRebuildScheduler` 后台 best-effort 调度，读链路不再同步阻塞一次重建
- 播放启动拆分：`PlaybackStartupCoordinator` 串起目标解析、续播/跳过准备与路由判定，`PlaybackStartupExecutor` 负责执行系统播放器 / 原生容器 / 性能回退分支，`player_page.dart` 只保留页面壳和内置 `MPV` 打开编排
- `TV` 播放控制层收口：播放器页把高频控制状态合并成单个 notifier，替代多层 `StreamBuilder` 套娃，减少播放中叠层刷新成本
- 播放页 presentation 收口：`player_page.dart` 已继续瘦身，平台会话、启动/MPV、运行期动作和播放器控制拆到 `player_page_platform_session.part.dart`、`player_page_startup_mpv.part.dart`、`player_page_runtime_actions.part.dart`、`player_page_controls.part.dart`；控制叠层、播放设置、启动覆盖层、TV chrome 与运行期对话框拆到独立 widget 文件
- `mpv_tuning_policy.dart` 负责收口 `MPV` 的远程/直播识别、重片源判定、运行期质量预设降档和本地 `ISO` 设备源判断，避免这些策略散落在页面状态里
- 首页 application 收口：`home_controller.dart` 现在主要保留 controller 与 provider wiring，`home_controller_models.dart` 承载 view model，`home_feed_repository.dart` 承载首页 seed/cached section 装配
- `PlaybackMemoryRepository` 已补单调递增 `updatedAt` 策略，保证最近播放在 Windows 或高频保存场景下仍按真正“最后一次写入”稳定排序
- NAS 索引链收口：`NasMediaIndexer` 已拆成 `nas_media_indexer_refresh_flow.dart / nas_media_indexer_storage_access.dart / nas_media_indexer_indexing.dart / nas_media_indexer_grouping.dart / nas_media_indexer_refresh_support.dart` 多段 `part` 文件；主文件回到约 `1k` 行量级，先把刷新编排、存储访问、metadata 匹配与分组逻辑解耦，为后续 isolate 化、`IndexStore` 增量 upsert 和多级并发预算继续铺路

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
- 详情页 presentation 入口已经进一步拆成 `detail_page_providers.dart`、`detail_hero_section.dart`、`detail_resource_info_section.dart`、`detail_subtitle_section.dart`，`media_detail_page.dart` 主要保留页面级 session / callback / section wiring。

### Playback

- `PlaybackTargetResolver`：先把播放目标解析到可播地址/headers。
- `PlaybackStartupCoordinator`：统一串起目标解析、续播/跳过配置读取与路由判定输入准备。
- `PlaybackEngineRouter`：封装路由判定（系统播放器 / 原生容器 / 性能回退 / 内置 MPV）。
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
2. 预热首页模块
3. 完成启动页过渡
4. 跳转主壳首页

启动阶段是轻量预热，不做重型阻塞初始化。

主路由之外，还有这些关键独立页面：

- 首页编辑器
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
- 豆瓣兴趣条目
- 豆瓣个性化推荐
- 豆瓣片单
- 豆瓣首页轮播

首页装配特点：

- 模块配置持久化在设置里
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
- 高性能模式开启时，Hero 会被强制收敛为静态单卡、无阴影，并关闭翻页按钮、指示点与全屏背景图
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

### WebDAV

`WebDAV` 页面消费模型不是“页面实时扫目录”，而是“索引驱动”：

1. `WebDavNasClient` 扫描目录
2. `NasMediaIndexer` 做识别、聚合和补元数据
3. `NasMediaIndexStore` 把结果落到本地
4. 首页、媒体库、详情页优先读取索引

补充约束：

- 增量刷新会限制在当前“已选分区”或显式指定的作用域内扫描
- 这一步会遍历作用域内目录来识别变更，但不会越过到其他分区
- sidecar 和在线元数据补全只针对增量项继续执行
- 只有当当前作用域索引为空时，才允许在后台调度一次自动全量重建；读链路本身不再同步等待这次重建
- 当前仓库内置的 `WebDAV / metadata / subtitle / playback / detail resource switch` trace helper 都已静音；默认不再输出扫描、索引、匹配或播放链路日志

`NasMediaIndexer` 负责的事情包括：

- 文件指纹
- 标题、年份、类型、季集识别
- 目录名 / 文件名里的 `{tmdbid-...}`、`{tvdbid-...}`、`{imdbid-...}`、`{doubanid-...}` 等嵌入式外部 ID 标签清洗，避免污染识别标题、系列分组标题和 metadata 查询词
- 包装目录 / 版本说明忽略，例如 `分段版 / 特效中字 / 会员版 / 导演剪辑版 / 清晰度 / 音轨 / 字幕` 等目录不会再被当成系列名
- `顶层推断目录` 支持：识别到剧文件或季目录后，命中配置的顶层目录名会停止继续向上推断，并回退到下一级已推断目录或文件名
- 综艺/节目文件名轻量识别，例如 `第X期`、`01 会员版` 这类“集号 + 版本说明”形式会继续归到对应集，而不是把版本说明当标题主体
- sidecar 读取
- `streamdetails`
- 外部 ID 提取
- `WMDB / TMDB` 在线补全，并继续保留上游返回的 `IMDb ID / IMDb` 评分标签
- 对开启目录结构推断的剧集条目，可选启用“剧集只按剧名层级搜刮”：metadata 查询只使用目录推导出的剧名，不再把季/集标题拼进搜索词，也不会继续请求单集 still
- `MediaItem` 生成
- 剧集父子关系聚合
- 目录名里如果能识别出明确季号，例如 `Season 1`、`S02`、`第2季`、`Stranger.Things.S02.2160p.BluRay.REMUX`，会直接把这一层当作季目录
- 对 `2.巴以 / 5.美国 / 9.韩国` 这类“数字 + 标题”的专题目录，会额外要求同级里存在多个同类兄弟目录，避免把普通数字目录误判成季
- 一旦当前层被识别为季目录，上一级目录就会作为剧名；像 `怪奇物语/Season 1/Season 2`、`怪奇物语/Stranger.Things.S02.2160p.BluRay.REMUX` 都会把 `怪奇物语` 当剧名
- 当路径里已经确认存在显式季目录时，即使当前只有一季，也会继续保留“剧 -> 季 -> 集”层级，不再因为单季而直接拍平成集列表
- 当前实现上，`NasMediaIndexer` 已拆成 grouping / refresh flow / storage access / indexing / refresh support 多个 part 文件；并发预算也在 indexer 内按 `source / collection / enrichment` 三层收口

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

- 复用 `设置 -> 网络存储 -> 夸克与 STRM` 中保存的全局 `Cookie`
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
- 详情页在 inactive 时会取消当前匹配 / 刷新 / 字幕搜索会话，但不会再无条件失效成功缓存；重新回到页面时优先复用已有详情结果
- 网络图片在展示层支持候选图回退，主图 `404` 或解码失败时会自动尝试下一张候选 artwork
- 详情页不再在进入时自动搜索字幕；只有已经拿到可播放目标并手动点击资源信息区里的“搜索字幕 / 刷新字幕”时，才会按 `设置 -> 播放 -> 字幕` 里的配置手动搜索。页面会先走 `OnlineSubtitleRepository.searchStructured(...)` 结构化链路，只保留最多 `10` 条已经验证可直接挂载的结果；`ASSRT` 未填写 Token 时会直接走网页 `search(...)`，填写 Token 后则可按设置决定在结构化链没有命中可用结果时是否回退网页链路
- 这组字幕候选和当前选中项会一并写入详情缓存；再次进入详情页时会恢复，进入播放器后会把已选外挂字幕带给内置 `MPV` 与 Android 原生播放器链路
- 详情页资源信息区可直接切换播放器；这个入口最终会调用 `SettingsController.setPlaybackEngine(...)`，因此会和设置页里的全局默认播放器保持同一份持久化值

当前详情页与元数据链路还额外承担这些能力：

- 顶部 Hero 优先使用背景图，不再重复放置海报；文字覆盖区域单独加阴影，未覆盖区域保持原图
- 高性能模式开启时，详情页顶部大图区会进一步收紧高度、缩小信息区，并减少背景遮罩层
- `TMDB` 已接入 `poster / backdrop / still / profile / logo` 等图片字段，并把 `TMDB x.x` 写入统一评分标签链路；当前不再主动去 `IMDb` 搜索信息，`IMDb` 相关标签只会在上游 `WMDB / TMDB` 已返回时参与展示和保存
- 详情页评分标签会按来源归一去重；`豆瓣 / IMDb / TMDB` 各最多保留一条，避免 seed target、详情缓存和后续在线补全合并后出现重复评分标签
- 人物头像统一来自 `TMDB profile`，详情页公司 Logo 来自 `TMDB production_companies.logo_path`，不再把 `networks` 混作公司展示
- 演职员头像可跳转到人物关联影片页，人物作品列表继续复用首页同款海报卡片；卡片右上角会优先显示题材/类型标签，左下角继续显示可用评分标签
- 剧集详情里的单集卡片已拆成两个入口：图片区继续走播放，图片下方的简介区进入单集详情
- `TV` 详情页额外拆成了明确的方向焦点带：
  - `Hero` 主操作按钮左右只在顶部操作区切换
  - 剧集浏览区拆成“季标签一排 / 卡片上半播放区一排 / 卡片下半简介区一排”
  - 剧集卡左右切换默认优先停留在上半播放区，只有主动按下才进入下半简介区
- 单集详情仍然复用统一的 `MediaDetailTarget` 详情链路，但会继承剧集级搜索词与外部 ID 上下文，保证该集的本地资源匹配、字幕关联和在线补全不会只依赖单集标题
- `TV` 模式下详情页主操作默认优先聚焦“继续播放 / 立即播放”或“搜索资源”，并记住人物、剧集等横向列表的上次焦点
- 桌面端剧集横排与剧照横排会复用统一的左右翻页按钮，避免鼠标只能手动拖动或滚轮横移
- 如果详情页命中多个可播放候选，底部会进入统一的“播放版本”切换路径；这条路径现在覆盖 `movie` 和单集等可播放叶子项，`series / season` 仍保留聚合态浏览

`WebDAV` 详情页还提供 `建立/管理索引` 页面，用于：

- 修改搜索词
- 修改年份
- 切换是否按剧集匹配
- 手动搜索 `WMDB / TMDB`
- 直接写回本地索引和详情缓存
- 手动应用命中结果时会强制覆盖本地已存在的标题、简介、图片、人物、公司 Logo 和外部 ID，不再只补空字段
- 详情页“手动更新信息”同样会直接重新搜索，并把命中的在线结果覆盖到当前详情缓存
- 人物关联影片页支持按年份新到旧 / 旧到新排序，也支持按类别筛选；排序与筛选都基于已拿到的人物作品结果在本地完成

详情页本地资源匹配当前还有这些约束：

- 自动匹配由 `设置 -> 元数据与评分 -> 详情页自动匹配本地资源` 控制，默认关闭
- 当自动匹配关闭时，详情页只保留“重新匹配资源”这一条手动触发路径
- `设置 -> 元数据与评分 -> 匹配来源` 会直接限制详情页本地资源匹配的实际扫描范围；只会扫描被选中的已启用 `Emby / WebDAV / Quark` 来源
- 如果“匹配来源”未单独勾选，则默认使用全部已启用来源；如果保存的来源 ID 已失效，则自动回退到全部已启用来源
- 如果详情页 seed target 本身来自媒体库卡片或指定来源模块，并已经带了 `sourceId / sourceKind / itemId / sectionId` 这类来源上下文，匹配链路会先优先处理这个来源，而不是把所有来源完全等价并行处理
- 对非 `series` 聚合页，如果入口 target 本身已经是该来源下的已解析资源，候选列表会先直接补入这条入口资源；手动重新匹配时也会跳过对这个入口来源的重复扫描
- 如果入口来源当前还没有命中项，但 seed target 带了明确 `sourceId` 或分区上下文，`Emby` 会先优先扫描同来源分区，`WebDAV / Quark` 也会先优先扫描同来源，再回退到其他已启用来源
- 手动匹配按多个搜索源并发执行，先命中的结果会立刻显示，但不会取消其余源的搜索
- 如果一次手动匹配命中多个本地资源，详情缓存会连同候选列表和当前选中项一起保存；后续重新进入详情页时会直接恢复这组候选
- 其中只要候选里有多个可直接播放的叶子资源，详情页会优先展示“播放版本”切换，而不是只把它们当成一组普通候选
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
- `CloudSaver`

搜索结果会在 provider 侧和页面侧继续做：

- 相同链接去重
- 网盘类型过滤
- 过滤词
- 强匹配
- 标题长度限制
- `TV` 模式额外会把最近搜索词和上次选择的搜索来源保存在本地，减少重复输入和重复切换
- 搜索页顶部来源筛选、最近搜索和媒体库筛选统一复用 `StarflowChipButton` 这一类通用按钮规格，普通端横向列表容器也与统一按钮高度保持一致，避免单页样式漂移或裁切
- 空关键词会直接短路，不再启动整轮 provider 搜索
- 多来源结果会先在页内聚合，再通过短定时批量提交 UI；不会再每个来源一返回就全量排序并触发一次大 `setState`

搜索来源还有一层全局设置约束：

- `设置 -> 搜索服务 -> 搜索来源` 会直接决定搜索页允许参与执行的本地媒体源和在线 provider
- 如果该设置未单独勾选任何来源，则默认使用全部已启用来源
- 如果保存的来源 ID 已失效，则自动回退到全部已启用来源
- 搜索页内记住的勾选项只是这层全局范围内的二次筛选，不会越过全局设置重新启用被禁用的来源
- 从详情页进入搜索时，会复用同一个 `SearchPage`，但通过 `/detail-search` 路由额外补上返回工具栏，并维持无转场进入，减少 TV / 低性能设备上的切页成本

搜索后的联动链路是：

1. 保存到夸克
2. 按网络存储里的“STRM 触发等待时间”延迟触发 `SmartStrm` Webhook
3. 按“索引刷新等待时间”延迟执行指定媒体源的增量刷新
4. 首页和媒体库读取到新的索引或缓存

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

主流程大致是：

1. 进入播放器页
2. `PlaybackStartupCoordinator` 解析播放目标，读取本地续播和按剧跳过偏好，并得到路由动作
3. 如果是 `Emby / Quark`，会在这一步补齐真实播放源和请求头
4. `PlaybackStartupExecutor` 按播放器内核、`TV` / 高压力片源与性能策略执行系统播放器、原生容器或性能回退分支
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
- iOS 后台音频播放会话
- `TV` / 定制系统环境下，如果外部字幕选择器或其他外部打开能力不可用，页面会优先提示失败而不是直接崩溃
- Android `TV` 从原生播放器拉起独立字幕搜索页时，会把当前 `query / title / input` 一并透传给 Flutter 路由，避免字幕搜索页空查询打开；页面只预填，不会自动发起搜索
- 播放设置里的字幕默认项已收拢到独立二级页，和播放中临时字幕操作分开
- 非 `TV` 的内嵌 `MPV` 当前使用 Starflow 自己的轻量播放叠层，而不是 `media_kit` 默认控制条：
  - 首层只保留返回、播放/暂停、进度、全屏和“更多”；音量、字幕、音轨与其他高级播放项统一收进播放设置弹窗
  - 顶部标题栏、底部控制区和播放设置弹窗都收敛到更官方的 Material 组件组合：`Material + IconButton + Slider + Text + ListTile + TextButton`
  - `PiP / AirPlay` 入口继续按平台能力显示
- 非 `TV` 叠层的 fullscreen 状态由父级先读取，再以普通 `bool` 传给 `PlayerMpvControlsOverlay`；叠层在 `dispose()` 期间不再回头查 `FullscreenInheritedWidget`，避免 Windows 全屏退出时触发 deactivated ancestor 断言
- Windows `MPV` 会在新播放器初始化前先等待 `_playerShutdownQueue` 清空，通过 `_waitForPendingPlayerShutdowns(...)` 与 `_enqueuePlayerShutdown(...)` 串行执行上一实例的 `pause -> stop -> dispose`
- 播放退出、关闭后台播放、外部清理请求和打开新片源当前已经统一收口到同一套 detach/shutdown 流程；只有明确允许后台播放时才保留后台音频
- `PlayerMpvControlsOverlay` 的自动隐藏定时器、点击唤醒与 `setState` 现在都受 `_isDisposed / _canUpdateOverlayState` 保护；窗口态已不再响应 hover 唤醒，并会在全屏切换时重置 pointer wake 状态，减少全屏切换或返回时的 `setState after dispose`、`mouse_tracker` 异常以及窗口态闪烁
- `PlaybackOptionsDialog` 现在把轨道、倍速和音量等运行期状态收口成单层订阅 view state，替代多层 `StreamBuilder` 套娃，减少播放中弹窗的重复重建
- 播放页 presentation 当前已分成：
  - `player_page.dart`：页面壳、字段与顶层 wiring
  - `player_page_platform_session.part.dart`：PiP、后台播放、系统播放会话
  - `player_page_startup_mpv.part.dart`：播放启动、打开重试、`MPV` / ISO / 调优链
  - `player_page_runtime_actions.part.dart`：续播、跳过、字幕、外挂字幕、在线字幕、启动 probe
  - `player_page_controls.part.dart`：返回、进度、选择器、播放设置、视频 surface
  - `player_mpv_controls_overlay.dart`、`player_playback_options_dialog.dart`、`player_playback_overlays.dart`、`player_playback_dialogs.dart`、`player_tv_playback_widgets.dart`：纯展示层组件
- `lib/core/utils/playback_trace.dart`、`subtitle_search_trace.dart`、`metadata_search_trace.dart` 与 `detail_resource_switch_trace.dart` 仍保留调用点与设置字段，但当前实现都已静音，不再产生运行时输出
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
  - Android 原生音轨/字幕轨选择、外挂字幕加载与外挂字幕偏移
- 详情页与播放器页复用同一个 `OnlineSubtitleRepository`；仓库内部已经拆成 `searchStructured(...)` 和 legacy `search(...)` 两条链路
- `searchStructured(...)` 会基于当前播放目标、详情外部 ID 和本地文件信息组装 `OnlineSubtitleSearchRequest`，优先尝试文件哈希、`IMDb ID / TMDB ID`、季集号、年份和标题
- 结构化源当前支持 `ASSRT API / OpenSubtitles / SubDL`；`ASSRT` Token 来自设置页，未填写时不会访问 API；`OpenSubtitles` API Key 通过 `--dart-define=STARFLOW_OPENSUBTITLES_API_KEY=...` 注入，账号密码来自设置页；`SubDL` API Key 直接来自设置页
- `SubtitleValidationPipeline` 会在应用内预下载、解压并筛选结果，只向 UI 返回可直接挂载的 `SRT / ASS / SSA / VTT` 或可解压 `ZIP` 字幕
- `ASSRT` 未填写 Token 时会直接走网页链路；已填写 Token 时，只有设置允许网页回退且 API 没有可用结果时，才会继续访问 `ASSRT` 网页搜索
- `ASSRT` 网页查询仍会按站点自动做短查询 fallback，例如把 `片名 + SxxEyy` 或 `片名 + 年份` 逐步回退到纯片名
- `ASSRT` 如果返回错误页会直接按源失败处理，不再把错误页误判成“0 结果”
- legacy 下载后的在线字幕会缓存在应用支持目录下的 `starflow-subtitle-cache`；如果同一结果已经下载并解压过，再次选择时优先复用本地缓存
- 播放器页本身不再直接承载全部启动决策；目标解析、路由判定与执行分支已经拆到独立 application 文件，页面层主要负责装配、等待态和内置 `MPV` 运行期行为，便于 controller 级测试和后续替换策略
- 播放器页 presentation 也已进一步拆开：`player_page.dart` 主要保留会话和流程编排，控制叠层、启动等待态、播放设置弹窗与平台会话子树分别沉到 `presentation/widgets` 与 `player_page_*.part.dart`

高性能模式在全局视觉层面当前还会做这些简化：

- 所有客户端关闭磨砂/模糊背景、菜单栏自动隐藏、Hero 全屏背景图与页面背景 glow
- 关闭启动页入场动画与主导航切换动画，并把导航改成静态常驻
- 首页 Hero 固定为静态单卡海报样式，关闭翻页按钮、指示点和分页缓动
- 详情页顶部大图区会进一步瘦身，减少大面积背景叠层
- 移除通用 `SectionPanel` 阴影
- `TV` 焦点样式切到无缩放、无阴影的轻量高亮
- 播放器里进一步简化叠层显示和字幕背景，并更积极偏向硬解
- 路由、导航壳和播放器当前都会统一消费 `AppSettingsPerformanceX.effective*` 派生值，而不是各自单独解释高性能开关
- 内置 `MPV` 会在启动前按片源、平台与模式做额外调优：
  - 动态选择前向缓冲与回看缓冲
  - 默认开启 `demuxer thread`，并关闭 `interpolation / deband / audio-display`
  - 对远程流按 buffered remote 与 low-latency remote 两类配置不同的 `network-timeout / cache / cache-secs / demuxer` 参数
  - 质量预设支持按窗口态 Windows、远程流和重片源做运行期自动降档，但不会覆盖设置页里保存的默认预设
  - 在高性能模式、`TV`、重片源或高压力场景下尝试应用 `fast profile`
  - `TV` 与高性能模式下会进一步简化字幕渲染，降低叠加压力
  - 软解优先且片源较重时，适度降低解码侧开销，优先换取稳定性

播放性能模式的运行期保护目前还包括：

- 播放会话打开后，会直接通过统一的 `backgroundWorkSuspendedProvider` 把“非播放优先级”的页面工作切到暂停态，不再要求先手动开启高性能模式
- 播放页会更早把播放性能模式切到 active，尽量在首帧前就压住底层壳层动画与后台工作
- `StatefulShellRoute.indexedStack` 下的隐藏分支会关闭 `HeroMode`、`TickerMode`，并忽略命中测试，减少播放器上层的 Flutter 合成干扰
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

- Android 原生播放器容器页当前使用原生 `Activity + Media3/ExoPlayer` 承载播放，不退出 App；它会跟随设置选择 `自动 / 硬解优先 / 软解优先`，在 `TV` 下默认更偏向纯画面与二层菜单交互，但也不提供完整 Flutter 播放器里的高级能力
- iOS 原生播放器容器页当前使用原生 `AVPlayerViewController` 全屏承载播放，不退出 App；它会复用同一份续播记忆，并补了在线字幕搜索入口，但解码走系统链路，当前不提供软硬解切换或字幕偏移
- iOS 的播放会话桥接由 `ios/Runner/PlaybackSystemSessionBridge.swift` 承担，`AppDelegate` 会把它绑定到 Flutter channel，用于原生播放会话、遥控器命令和 AirPlay 入口
- Android 系统播放器优先调用原生 `ACTION_VIEW`，并显式标记 `video/*`
- 桌面端系统播放器通过临时 `.m3u` 交给系统默认视频应用
- 高性能模式开启后会更积极优先硬解；其中 Android TV 如果识别到高码率或高压力片源，会优先尝试切到 App 内原生播放器，再退到系统播放器
- 内置 `MPV` 会跟随设置切换解码模式；系统播放器无法稳定回传进度，且解码方式由外部播放器自行决定，因此续播记忆只在内置 `MPV` 和 App 内原生播放器里生效
- 自动跳过片头片尾当前只在内置 `MPV` 里生效
- 字幕偏移当前支持内置 `MPV` 与 Android 原生播放器的外挂字幕链路；iOS 原生播放器暂未提供字幕偏移

播放器默认偏好目前包括：

- 最大打开超时时间
- 解码模式
- 默认倍速
- 默认字幕策略
  - `跟随片源`：打开视频时按片源默认字幕轨处理
  - `默认关闭`：打开视频时默认不显示字幕
- 字幕大小
- 字幕默认项在设置页中以单独的“字幕”二级页承载，避免和播放内核、后台播放、默认倍速混在同一层
- 后台播放
  - 设置中提供独立开关
  - Android：开启后播放中切后台时允许进入画中画继续播放
  - iOS：开启后播放中切后台时启用后台音频会话，继续后台播放音频
  - 关闭该开关后，播放器退出或切新片源时会优先清理当前 `MPV` 会话，而不是继续在后台保活
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
- 元数据与评分
- 本地资源匹配来源
- 播放超时
- 解码模式
- 后台播放
- 默认字幕策略
- 默认倍速
- 字幕大小
- 在线字幕来源
- 各在线字幕来源的专属配置（`ASSRT Token / OpenSubtitles 账号密码 / SubDL API Key`）
- 优先语言与单次最多验证条数
- `ASSRT` 网页回退
- 播放器内核
- 透明磨砂效果
- 高性能模式
- 自动隐藏菜单栏
- Hero 全屏背景图
- 运行时卡片 / Hero 局部更新

播放设置在页面结构上额外做了分组：

- 一级页放播放器内核、打开超时、后台播放、默认倍速等主偏好
- 字幕默认项收拢到“字幕”二级页
- 详情页资源信息区对播放器内核的切换会直接复用同一个 `setPlaybackEngine(...)` 写回入口，因此不会出现“详情页一种默认、设置页另一种默认”的分叉
- `AppSettingsPerformanceX` 会把高性能模式和相关细项统一派生成有效档位；路由、导航、首页 Hero、详情页和播放器都通过这组 `effective*` 入口读取实际生效值
- 运行时卡片 / Hero 局部更新默认可在普通端按需开关；`TV` 端会强制关闭，设置页展示的是实际生效值而不是单纯保存值

设置编辑页在 TV 下还额外做了输入方式分流：

- 文本项优先显示为可聚焦设置条目
- 需要编辑时再进入独立弹窗输入
- 避免页面级 `TextField` 长时间占据焦点并把遥控器操作锁在系统键盘里
- 媒体源、搜索服务、豆瓣账号、网络存储、播放、配置管理等主要设置页，当前尽量共用同一套页面骨架和按钮分类，减少页面间的操作分叉
- 搜索来源、匹配来源等多选项当前统一复用同一套复选弹窗；`TV / 触屏` 共享一套选择流程与焦点逻辑
- `WebDAV` 路径选择页会缓存目录 Future，避免同一目录在页面重建或来回切换时重复列目录
- 高性能模式开启时，透明磨砂效果、自动隐藏菜单栏和 Hero 背景图等受统一性能策略接管的子项会显示实际生效值并禁用编辑，避免出现“可改但不生效”
- `TV` 端同样会把“运行时卡片 / Hero 局部更新”按实际生效值固定为关闭，避免焦点浏览和滚动过程中被后台缓存更新继续唤醒局部 provider 链路
- 首页、搜索、设置页以及部分壳层组件已经开始改成 slice provider 订阅；高频页面会优先只读取需要的设置片段，而不是整份 `AppSettings`

播放器运行期状态还会额外保存：

- 最近播放
- 电影续播进度
- 电视剧当前集与集内进度
- 按剧绑定的片头 / 片尾跳过规则

设置页还提供：

- 本地缓存查看与清理
- 当前清理项包括 `WebDAV` 索引、详情缓存、播放记忆、`TV` 搜索历史与来源记忆、图片缓存
- 在支持文件访问的平台上导出配置到 JSON
- 在支持文件访问的平台上从 JSON 导入并覆盖当前设置
- Web 端会直接触发浏览器下载 JSON，并支持选择本地 JSON 立即导入覆盖
- iOS / iPadOS 导出当前改走系统文件导出器，会直接弹出原生保存面板，可保存到“文件 / iCloud / 本机其他位置”
- iOS / iPadOS 导入继续走系统文件选择器
- `TV` 模式下改为应用内局域网配置传输
- 会启动一个临时本地 HTTP 服务，并在电视上展示访问码、端口与局域网地址
- 手机与电视连接同一网络后，可直接下载当前配置或上传 JSON 覆盖本机设置
- 关闭传输弹窗后会立刻停止该临时传输服务，不保留后台进程

Android TV 下的设置页还额外做了遥控器适配：

- 设置首页主要入口卡片支持焦点选中
- 多个二级设置页的主要按钮与保存操作支持焦点可达
- 长列表中的焦点会尽量停在屏幕中部，滚动容器随焦点一起平滑移动
- 媒体源、搜索服务、豆瓣账号、网络存储等编辑页里的文本项会先显示成可聚焦条目，再进入独立编辑弹窗
- 已加入“高性能模式”总开关，用于在所有客户端进一步压低动画、模糊背景、通用阴影和播放页叠层，并把导航收敛为静态常驻、首页 Hero 收敛为静态单卡海报；TV 端还会额外简化焦点样式
- 多数设置编辑页已经统一到同一种工具栏、保存按钮、危险操作按钮和选择条目样式
- 仍有少量弹窗和编辑流需要继续补齐焦点细节

## 12. 本地持久化

### SharedPreferences

用于保存：

- 应用设置
- 详情缓存
- 详情缓存里的本地资源匹配候选列表、在线字幕候选列表与当前选中项
- 详情缓存里已经刮削、手动更新或手动关联后的标题；首页、媒体库和详情页会优先读取它作为展示名
- 对存在多个可播放候选的详情页，还会额外保留当前选中的“播放版本”，包括影片和单集等叶子项
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

- legacy 在线字幕下载缓存 `starflow-subtitle-cache`
- legacy 解压后的字幕文件
- 详情页与播放器页复用的外挂字幕本地副本

### 临时目录

用于保存：

- 结构化在线字幕验证缓存 `starflow/validated_online_subtitles`
- 新链路预下载后筛出的可直接挂载字幕文件

### Sembast

用于保存 `WebDAV` 元数据索引。

### 持久化图片缓存

通过 `persistent_image_cache` 抽象统一访问，不同平台走各自实现或 stub。

当前图片缓存策略已经补齐这些约束：

- identity 按 `URL + 归一化 headers` 区分，避免不同鉴权请求误命中同一份缓存
- 磁盘层会保存 metadata，并按 `30` 天 TTL 做过期判断
- 远端失败但本地还保留旧字节时，会优先回退到 stale bytes，减少短期网络抖动导致的图片缺失
- 内存层按条目数和字节预算双阈值淘汰，尽量减少重复 decode

## 13. 平台分支

项目有一层明确的平台适配：

- Android 会识别 `TV` 设备
- TV 模式切换为左侧窄栏磨砂菜单和焦点式交互
- 左侧菜单是否自动隐藏由设置控制；开启后会在焦点离开菜单栏时自动收起
- 设置首页及部分设置子页会优先使用更适合遥控器操作的可聚焦按钮与入口
- Android 主清单显式声明了 `INTERNET`、`ACCESS_NETWORK_STATE` 和明文流量支持，保证 TV 端能访问局域网与在线元数据资源
- Android 当前实际最低兼容版本固定为 `API 23 / Android 6.0`
- Release APK 当前启用了 `v1 + v2` 签名，兼容老一些的电视安装器
- 当前 Release APK 仍使用本机 debug keystore 签名；如果设备里已有其他签名的旧版 `com.example.starflow`，覆盖安装会失败，需要先卸载旧包
- `TvMenuButtonScope` 用来把菜单键语义统一上抛到页面壳
- `TvFocusMemoryScope` 用来记录首页、搜索、媒体库、详情等页面上次停留的焦点元素
- `TvFocusMemoryScope` 当前已经改成 `InheritedWidget` 传递；记忆写入和清除不会再广播式触发整页依赖刷新
- `TvReturnToTopScope` 与 `TvDirectionalFocusBoundary` 用来给主要页面建立统一的页头回顶、上下方向越界兜底和模块间焦点切换规则
- `TvFocusableAction` 在垂直滚动容器里会尝试把焦点项保持在视口中线附近，降低 TV 遥控器纵向浏览时的视线跳动
- `TvFocusableAction` 的焦点视觉态已经改成局部 `ValueNotifier` 更新；轻量模式下可切到 outline only 或直接 `none`
- `SettingsTextInputField` 会在 TV 模式下把页面内文本输入改成“设置条目 + 弹窗编辑”交互，减少焦点被输入法占据的情况
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

- 设置模型与迁移
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

## 15. 当前架构判断

这个仓库目前最重要的三个判断是：

1. `WebDAV` 的正确方向是“索引优先”，而不是“页面实时扫目录”
2. 详情页不是唯一元数据入口，索引阶段已经承担了大量 enrichment 工作
3. 搜索不是孤立功能，而是资源入库、`SmartStrm` 触发和自动增量刷新索引的上游触发器
