# Starflow 代码地图

内存优先缓存（2026-09-26）：`features/playback/application/mpv_memory_priority_policy.dart` 拥有实际高水位学习与许可判定，`presentation/widgets/player_page_memory_priority.part.dart` 独立采样并探测 MPV 运行时补充选项。`PlaybackRelayBufferControl` 是可选缓存控制契约，原生桥接处理 `setNativePlaybackBufferState`；relay 拥有 4 秒许可、前台接管在途预取，disk cache 拥有游标淘汰／读块保护。Android 对应 `NativePlaybackLoadControl / NativePlaybackReadAheadPolicy / NativePlaybackDiagnostics / NativePlaybackRuntimeController`，iOS 对应 `NativePlaybackBufferingTuning / NativePlaybackViewController`。新增策略回归 `test/mpv_memory_priority_policy_test.dart`、`test/playback_disk_cache_forward_retention_test.dart`；网络竞态与桥接回归扩展 `playback_read_ahead_race_test.dart` 和 `native_playback_cache_bridge_test.dart`。

网盘账号与恢复（2026-09-26）：`features/settings/domain/cloud_account.dart` 定义本机账号状态/指纹，`data/cloud_credential_store.dart` 提供安全存储接口，仓储负责明文迁移与导出隔离，控制器区分账号切换和 Token 轮换；`features/search/data/aliyun_transfer_journal.dart` 保存跨盘任务快照，`presentation/aliyun_transfer_tasks_page.dart`（settings 下）提供恢复/停止/清理。新增回归 `test/cloud_account_security_test.dart`、`test/features/settings/presentation/aliyun_transfer_tasks_page_test.dart`，恢复协议扩展 `aliyun_to115_workflow_test.dart`，并发刷新扩展 `aliyun_transfer_protocol_test.dart`。iPhone QR 相册写入在 `ios/Runner/AppDelegate.swift` 的 `saveLoginQrImage`，仅添加权限。

阿里扫码登录（2026-09-26）：`features/settings/data/aliyun_login_client.dart` 负责官方消费版二维码生成、状态查询与确认凭据解析；`aliyun_open_login_client.dart` 与 `aliyun_open_oauth_config.dart` 负责内置 OpenList 授权入口和 Open OAuth 凭据；两个 presentation 登录页分别处理轮询生命周期、刷新与迟到结果隔离；阿里设置页按 `aliyunAuthMode` 验证后保存对应本机轮换凭据。协议与页面测试为 `test/aliyun_login_client_test.dart`、`test/aliyun_open_login_client_test.dart`、两个登录页测试，接入和凭据保存回归在 `test/aliyun_save_settings_test.dart`。

阿里保存与转 115（2026-09-26）：`features/search/application/aliyun_to115_workflow.dart` 编排两种保存；`data/aliyun_transfer_client.dart`、`cloud115_instant_upload_client.dart`、`cloud115_upload_cipher.dart` 与 `aliyun_transfer_http.dart` 负责协议；`features/settings/presentation/aliyun_transfer_settings_page.dart` 负责本机凭据与独立自动转存开关。无逐次确认弹窗。测试入口 `test/aliyun_to115_workflow_test.dart`、`aliyun_transfer_protocol_test.dart`、`aliyun_save_settings_test.dart`，搜索入口模式回归在 `features/search/presentation/search_page_save_progress_test.dart`，设置回归复用 `app_settings_repository_reconciliation_test.dart`。秒传协议测试覆盖毫秒时间/token 一致性、可选成功字段、异常状态和日志脱敏；工作流测试覆盖缺哈希源快照恢复、副本回执复用与未知上传不重放。

阿里功能对齐：`application/aliyun_sync_delete_service.dart` 处理 WebDAV 相对路径匹配与删除前身份复核，由 `library/data/media_repository.dart` 在 WebDAV 删除确认后执行。`search_share_validator.dart` 接入只读阿里验链；`details/application/detail_online_resource_update_service.dart` 和详情页注入阿里 workflow，按当前目标检查更新。阿里设置页复用目录选择/管理组件，持有独立目录、STRM 和监听配置，名称修正读取通用设置；转 115 后跳转已有 115 设置。

网盘通用设置：`features/settings/presentation/network_storage_settings_page.dart` 的 `NetworkStorageCommonSettingsTile` 是网盘根页唯一入口，`NetworkStorageEditorSection.common` 展示 Webhook、STRM 延迟和媒体库刷新；夸克、115、阿里单项页不重复放置。`domain/network_storage_settings_scope.dart` 定义字段归属和局部合并，控制器在执行保存时应用到最新配置；回归见设置层级导航、自动保存和持久化测试。

名称规则统一：`NetworkStorageConfig.effectiveQuarkNameCharacters / effective115NameCharacters / effectiveAliyunNameCharacters` 都只读取通用启用开关和字符，保存工作流、去重与详情更新预览使用同一结果；旧独立字段保留 JSON 兼容但不参与运行规则。`test/network_storage_name_rules_test.dart` 覆盖旧 JSON、关闭/空字符和字段作用域隔离。

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
| `assets/` | 品牌资源、bootstrap 目录和本地性能样本；只打包两张运行时 Logo 和 bootstrap，设计源图/样本保留但不打包；嵌入设置只由显式发布参数临时写入 |
| `scripts/` | 发布、环境准备、依赖重建及平台检查；部分脚本修改版本和构建目录 |
| `tool/` | 代码生成、主机计时、Web 开发代理与手动诊断 |
| `test/` | Dart 单元 / 组件 / smoke 测试及跨语言 fixture |
| `docs/` | [文档索引](README.md)、现行架构与专题；`reviews/` 集中保存带日期的历史审查，HTML 是品牌设计素材 |
| `backups/branding/`、`icons/` | 品牌历史说明与设计原图，不是应用运行数据 |
| `pubspec.yaml / pubspec.lock` | 版本、依赖、插件覆盖和资源；自动发布会改版本 |
| `analysis_options.yaml`、`devtools_options.yaml` | 静态检查和开发工具设置 |

`build/`、`.dart_tool/`、Pods、插件二进制缓存和本机日志是生成物或诊断产物，不作为手工维护源码。不要为了更新说明而运行会清理缓存或递增版本的发布脚本。

## 启动、路由与公共层

内容排版入口：`app/theme/app_typography.dart` 定义语义行高与内容间距，`app_theme.dart` 应用公共标题／正文样式；首页和详情 Hero、详情简介、设置公共组件复用。回归入口为 `app_theme_test.dart`、`settings_content_spacing_test.dart`、`detail_overview_section_test.dart`，不覆盖字幕或原生播放器排版。

| 入口 | 职责 |
| --- | --- |
| `lib/main.dart` | 初始设置、代理、结构化日志、错误钩子、帧监测、启动标记、MediaKit 初始化及 ProviderScope；关闭 Riverpod 自动重试 |
| `features/bootstrap/application/bootstrap_controller.dart` | 配置 / 缓存 / 首页启动编排与 10s 总截止时间；不覆盖此前初始化或同步阻塞 |
| `features/bootstrap/application/startup_crash_recovery.dart` | 启动标记及异常启动恢复，不代替原生崩溃日志 |
| `app/router/app_routes.dart`、`app_router.dart`、`app_navigator.dart` | 壳页和详情、人物 / 公司、播放器、设置、搜索等附加路由 |
| `app/router/app_navigation_shell.dart`、`app/shell_layout.dart` | home / search / favorites / library / settings / live-tv 六个壳路由，默认隐藏收藏，菜单选择来自当前设置 |
| `app/lifecycle/app_runtime_recovery_boundary.dart` | 后台、前台、低内存和退出弹窗的调度准入租约 |
| `core/navigation/` | `PageActivityMixin` 和 RetainedAsync 控制器，暂停工作但保留稳定页面结果 |
| `core/network/` | 共享 HTTP、IO 代理、Web 转发、失败分类、超时与按主机熔断；详见网络文档 |
| `core/logging/` | IO 本地日志、轮转、脱敏、帧告警；Web 是文件日志 stub |
| `core/storage/` | 偏好存储、URL + headers 图片缓存、资源路径身份及本地存储模型 |
| `core/platform/` | TV 检测、系统退出、后台播放、媒体会话及 Android PiP 通道 |
| `core/scheduling/queue_wait_diagnostics.dart` | 队列等待诊断，不自行执行网络请求 |
| `core/state/riverpod_retry.dart` | provider 重试策略 |
| `core/widgets/` | TV 焦点、图片并发门、海报、对话框、横向翻页、Logo 等共享 UI |
| `core/widgets/tv_remote_input.dart` | TV 命令键按下/重复/松开配对、单次执行与失焦取消；`TvRemoteShortcuts` 供应用入口、按钮、海报、弹窗和播放器复用，回归见 `test/core/widgets/tv_remote_input_test.dart` |
| `core/widgets/mobile_text_input_dismissal.dart` | 应用入口统一挂载的手机输入框外点击收键盘规则；回归见 `test/core/widgets/mobile_text_input_dismissal_test.dart` |
| `core/utils/` | 文本、评分、图片 headers、默认 seed；旧静默 trace helper 已删除，结构化日志与错误记录保持活跃 |

本节路径除 `lib/main.dart` 外相对于 `lib/`。`SeedData` 提供默认配置，不应将已经接入真实数据的仓库称为 mock 仓库。

## 业务模块

以下路径相对于 `lib/features/`。

| 模块 | 主要入口 | 职责与下游 |
| --- | --- | --- |
| `bootstrap` | `application/bootstrap_controller.dart`、`presentation/bootstrap_page.dart` | 启动阶段与超时兜底，调用设置、缓存和首页 |
| `home` | `application/home_controller.dart`、`home_feed_repository.dart`、`home_controller_models.dart` | 来源 seed 与本地详情装饰分离；独立首页调度、Hero 预取、元数据刷新及 settings slices；页面拆成 home / hero / sections |
| `discovery` | `data/discovery_repository.dart`、`douban_api_client.dart`、`douban_network_guard.dart` | 豆瓣列表与详情数据，提供给首页 / 详情；不单独占一个默认主导航 tab |
| `library` | `data/media_repository.dart`、`application/app_media_query_service.dart` | AppMediaRepository 管刷新 / 删除，query service 管读；media_server_client 协调 Emby / 飞牛，NAS 索引覆盖 WebDAV / 夸克 |
| `details` | `application/detail_page_controller.dart`、`detail_target_resolver.dart`、`detail_metadata_service.dart` | 详情恢复、统一元数据执行、本地匹配、评分预取、版本选择与从头播放；季集 UI 按目标懒加载 |
| `metadata` | `data/metadata_match_resolver.dart`、`wmdb_metadata_client.dart`、`tmdb_metadata_client.dart` | WMDB / TMDB 匹配、结果复用、网络 guard 与共享限流；IMDb 为默认关闭的 NAS 配置功能，`imdb_rating_dataset.dart` 后台构建有界字节/行偏移索引，客户端共享下载与解析 |
| `playback` | `application/playback_startup_coordinator.dart`、`presentation/player_page.dart` | 启动、路由、播放会话、可靠性、字幕、播放记忆及平台适配 |
| `live_tv` | `data/live_repository.dart`、`live_playlist_parser.dart`、`live_epg_parser.dart`、`application/live_playback_controller.dart` | 独立订阅/频道/节目单存储、MPV/Exo 直播会话；`presentation/live_tv_page.dart / live_sources_page.dart / live_player_page.dart` 为界面入口 |
| `search` | `data/search_repository.dart`、`presentation/search_page.dart` | PanSou / CloudSaver / 本地来源搜索、分享验证、收藏及网盘保存工作流 |
| `settings` | `application/settings_controller.dart`、`settings_slice_providers.dart`、`domain/app_settings.dart` | 配置模型、窄字段保存、来源生命周期、自动保存、导入导出、日志、代理与 WebDAV 同步 |
| `storage` | `data/local_storage_cache_repository.dart`、`application/local_storage_cache_revision.dart` | 本地详情及媒体服务器分片缓存、统计与清理，revision 驱动本地派生刷新 |

`library/data/mock_media_repository.dart`、`discovery/data/mock_discovery_repository.dart`、`search/data/mock_search_repository.dart` 已由正式命名文件取代，排障和新测试不要继续引用旧路径。

## 关键调用链

### 首页与详情

2026-09-22 补充返回键回归：`test/core/widgets/app_network_image_test.dart` 使用 `GoRouter` 的首页、可返回详情路由及实际 `DetailImageGallery` 弹出预览，覆盖返回/确定键按下、重复、松开、系统返回、退出预览后的剧照焦点恢复，以及再次系统返回退出详情。预览保留焦点直到消费松开事件才关闭；此前仅校验按下消费的测试不足以覆盖 Android BACK 松开重派发。这是主机 widget 验证，不代表 TV 真机验收。

剧照横排由 `details/presentation/widgets/detail_shared_widgets.dart` 持有已成功解码的图片源，剧照使用仅内存的 `networkOnly` 策略，不写入磁盘；`detail_image_preview.dart` 负责全屏双指缩放、双击切换 2.5 倍缩放、放大后拖动、未放大时下滑关闭、点击图片外空白退出、失败重试与系统返回退出。预览不再放置右上角缩放/关闭按钮，双指缩放围绕实际两指中心，TV 由不可见焦点宿主接收返回键，返回或确定只关闭预览并回到详情页，失败重试按钮仍可参与焦点移动。`AppNetworkImage.onImageReady` 只交付成功解码帧对应的未缩放 provider，预览独立限制解码尺寸；关闭预览只驱逐预览尺寸，详情剧照组件销毁或切换图片集时驱逐源图、804×452 缩略图和 2048px 预览尺寸，不清空全局 `ImageCache`。2026-09-22 验证范围为主机 widget 回归（临时链接二次请求失败、双指缩放、双击缩放、下滑关闭、点击图片外空白、关闭后缩略图保留、TV 返回/确定回到详情页与焦点宿主），不代表 Android / iOS 真机验收。

```text
HomePage -> HomePageController -> HomeFeedRepository -> 来源 / 豆瓣 seed
                                                   -> 批量详情缓存装饰
MediaDetailPage -> DetailPageController -> DetailTargetResolver
                                       -> resolveDetailMetadata
                                       -> DetailLibraryMatchCoordinator
                                       -> 评分 / 季集 / 版本
```

详情缓存 revision 只驱动装饰层本地重算，不应重新抓取整轮首页来源。详情被播放器覆盖时保留剧集组件、季选择和滚动，活动状态控制订阅及新增任务。

`detail_library_match_coordinator.dart` 负责优先来源与后备来源两阶段读取、最多两路并发、逐批候选和取消检查；`detail_library_match_service.dart` 提供候选类型、评分与合并规则。页面不再维护另一套同构候选模型，焦点、弹窗和缓存恢复仍属于页面生命周期。

2026-09-20 M01–M04 修复边界：最终版本展开在每次来源读取前后检查页面 session / 匹配 controller，返回后在页面候选、手动目标和缓存提交前再次校验；取消不撤销取消前已经展示的逐批候选。`library/domain/tmdb_media_identity.dart` 将 TMDB 身份限定为 movie / TV + ID，详情匹配与在线更新排除明确相反类型；未知类型不再参与类型化 TMDB、标题或其他外部 ID 匹配。TMDB 搜索去重保留同数字 ID 的电影和剧集，详情元数据转换保留媒体类型。

TMDB / WMDB 标题和 ID 查询缓存以 generation 隔离清空前请求，finally 仅删除自身 future 的占位；旧请求仍可向原调用者返回，但不能回填清空后的缓存或移除新请求。仅缓存非空结果，null（包括 TMDB 详情 404）下次可重试；TMDB 详情鉴权、限流和服务错误抛异常，不再作为“没有匹配”持久复用。覆盖文件：`test/metadata_cache_race_test.dart`、`test/tmdb_media_identity_test.dart`、`test/media_detail_match_cancellation_test.dart`；这些是主机 MockClient / completer / widget 回归，不是设备或真实元数据服务测量。十方向审查报告仍是修复前快照。

### 媒体库与存储

2026-09-24：`library/domain/media_work_aggregation.dart` 是“全部”及最近新增的作品卡片分组入口，不改变 `AppMediaQueryService.fetchLibrary` 的资源返回值；`MediaItem.workResources` 随详情导航转成瞬态候选，`DetailCachedStateRestorer` 恢复当前成员及来源选择。回归入口为 `test/media_work_aggregation_test.dart`、`test/features/library/presentation/library_cache_scope_test.dart`、`test/home_controller_test.dart` 和 `test/media_detail_match_restore_test.dart`。

```text
AppMediaRepository -> AppMediaQueryService -> MediaServerClient / 本地索引
                   -> MediaRefreshCoordinator -> 来源刷新 / NAS enrichment
                   -> WebDAV 删除确认 -> 可选网盘同步删除 -> 本地失效
```

- Emby / 飞牛使用媒体服务器缓存分片；根列表读取最多 400 条 summary，分区只读目标 shard，完整匹配最多两路解码。飞牛刷新成功后按前后快照的条目 ID 差集清理详情关联、匹配候选、续播记录和剧集播放偏好；刷新失败继续保留旧快照。
- NAS 索引由 `nas_media_indexer.dart` 及 `refresh_flow / storage_access / indexing / grouping / refresh_support` 的 `part` 文件共同实现；这些不是彼此独立的服务。
- `nas_media_index_store_impl_io.dart` 使用 Sembast；Web 有单独实现。当前 schema 是 `webdav-v17`，支持分区过滤与 upsert / patch，不再只做整库覆盖。`external_media_structure.dart` 保存作品目录、资源角色及季集证据；扫描、索引、分组和删除共享该归属，`ExternalScanResult` 传递扫描完整性。`nas_media_indexer_grouping.dart` 按一级媒体目录统一剧集/电影入口。只读真实目录诊断入口为 `tool/debug/webdav_directory_grouping_test.dart`，配置和相对目录通过环境变量传入，禁用在线及 sidecar 补全，索引仅写入内存，并检查《重启人生》的季集与版本数量。
- `webdav_nas_client.dart` 的 structure / sidecar / background 文件也是同一 Dart library。普通页面优先读索引，不实时扫全目录。
- `resource_path_identity.dart` 与 `media_source_identity.dart` 分别处理资源路径和来源身份；不要因元数据身份相同复用不同资源的直链或鉴权头。
- `library/data/nfo_metadata.dart` 共享 WebDAV / 夸克 XML 字段解析，`details/domain/cached_artwork.dart` 共享图片 URL 与 headers 配对合并；`library/presentation/library_resource_deletion.dart` 复用两级媒体库页面的删除确认。
- 详情缓存按 16ms Timer 收集批次后进入串行写链；相同编码内容跳过重复持久化。这是本地优化，不改变服务器请求协议。

`local_storage_cache_repository.dart` 保留 provider 和公共兼容入口；`detail_cache_store.dart` 与 `media_server_cache_store.dart` 分别持有详情及分片缓存的读取复用、修改队列和内存状态，`local_storage_cache_models.dart` 保存公共类型并由旧入口导出。重构不改变存储 key 或缓存格式，并保留整理期间已落地的 Timer 批量写入。

### 搜索、转存与收藏

`search/domain/search_result_resolution.dart` 识别在线结果的清晰度标记；`search/presentation/search_page.dart` 缓存识别结果并组合网盘、清晰度筛选，不改搜索请求或收藏模型。
`search/presentation/widgets/search_filter_row.dart` 管理三组筛选的标签对齐、手机横向滚动、宽屏 / TV 换行与大字体布局；筛选状态和清除操作仍由搜索页持有。

```text
SearchPage -> SearchRequest -> SearchSession -> SearchRepository
                                           -> SearchShareValidator
           <- 不可变结果快照 / 验证状态 / 进度
用户确认保存 -> CloudSaveDispatcher
             -> QuarkSaveWorkflowService / Cloud115SaveWorkflowService
             -> CloudSavePlanner -> 可选名称清理 -> SmartStrmWebhookClient
             -> MediaRefreshCoordinator
```

公共规划器负责目录复用、单层展开、递归去重和新增范围；协议客户端只负责各自 API。`CloudSavedNameSanitizer` 仅处理本次新增内容，不能为改名扫描并改写旧内容。115 Cookie 不进入配置 JSON，也不是已接入的直连媒体源。

`cloud_save_postprocessing.dart` 共享 STRM 触发、延迟规范化和保存后刷新失败反馈。来源修改 / 导入时，settings 层通过公共来源路径规则协调夸克与 115 监听目录，删除来源时清理两者引用；不因此放宽实际同步删除的匹配范围。

搜索、收藏与详情在线更新统一经 `cloud_save_dispatcher.dart` 分发到原有两种工作流；共享入口规范化分享凭据、验证网盘配置并返回 `CloudSaveOutcome`。页面只持有忙碌状态和反馈 session；未知 115 转存结果提示先检查网盘，不自动重试写操作。

收藏由 `search_preferences_repository.dart` 持久化，`favorite_auto_sync.dart` 控制可选同步触发，`favorite_sync_document / favorite_sync_payload` 定义版本与精简传输，`settings/data/webdav_sync_service.dart` 负责 WebDAV IO。手动配置快照与每设备收藏文件是不同协议，收藏没有启动定时同步或轮询。

### 直播电视

以下相对 `lib/features/live_tv/`，基础入口按 2026-09-20 实现核对，后续变更按节注明；有效约束见 [直播实现契约](live-tv.md#实现契约)，不使用已移除的实现前草稿类名或具名播放路由。

| 入口 | 职责与边界 |
| --- | --- |
| `domain/live_models.dart` | `LiveSource / LiveChannel / LiveLine / LivePreference / LiveProgramme / LiveSnapshot`；来源内频道身份、偏好覆盖、可见列表与节目区间 |
| `data/live_repository.dart` | Sembast store、串行事务、来源代次、同源刷新合并、到期检查、频道/EPG 分阶段提交与本地节目查询 |
| `data/live_database.dart` 及 `live_database_io / web / stub.dart` | 条件导出；IO 应用支持目录 `starflow-db/live_tv.v2.db`，Web `starflow-live-tv-v2`，其他目标明确不支持 |
| `data/live_playlist_parser.dart / live_epg_parser.dart` | M3U/TXT、媒体 headers、XMLTV/时区及保留窗口；Gzip 有界解压由仓库入口执行 |
| `data/live_logo_provider.dart` | 独立四路、15s/2 MiB 台标请求和取消，不是影视图片磁盘缓存 |
| `presentation/live_logo.dart` | 频道首页的 64×40 台标；192×120 上限等比解码、完整显示及同尺寸失败占位；播放器选台菜单不加载台标 |
| `data/live_channel_probe.dart` | 线路首包检测：自动补测与手动恢复共用 GET／Range 提示、6 秒总期限、首块即关闭、重定向与凭据隔离；不解码、不验证 HLS 子资源 |
| `application/live_channel_probe_controller.dart` | 可见 200ms 准入、TV 焦点优先、两路并发与离屏取消；单定时器可见项到期刷新、5 分钟成功缓存及失败退避、暂停保留缓存、线路协调及网络失效，不写数据库 |
| `data/live_probe_network.dart` | 前台首页系统连接类型事件，集合去重，无互联网可达性探测；页面拥有订阅和释放 |
| `presentation/live_probe_viewport.dart` | 布局／滚动后检查已挂载行与列表视口相交，排除离屏预构建行，不自行请求网络 |
| `presentation/live_probe_label.dart` | 台名同行的响应耗时／失败状态及线路／时间提示，不将连通性标为可播放 |
| `application/live_playback_controller.dart` | `LiveEngine` 的 MPV/Exo 适配、单实例串行所有权、换台合并、失效事件、有限重连及全局清理注册 |
| `application/live_mpv_options.dart` | MPV 直播默认请求标识、订阅覆盖优先级、网络协议白名单及 FFmpeg 6 HLS 分片参数；不改变点播配置 |
| `application/live_playback_error.dart` | Android `LiveTvPlaybackError.kt` 摘要的白名单解析、固定错误类别和失败文案；控制器按 generation 读取，不保留原始异常或媒体地址 |
| `presentation/live_tv_page.dart` | 频道列表、搜索/收藏/分组、频道与分组映射/隐藏/排序、主页面活动状态和本地 now/next 更新 |
| `presentation/live_sources_page.dart` | 来源编辑、文件导入草稿、保存后刷新、启停、更新及删除确认；TV 手机扫码，其他平台本地选文件 |
| `data/live_playlist_transfer_service{,_io,_stub}.dart` | 单次 LAN 文件/备份接收及备份下载、类型化结果、随机令牌/来源校验；频道文件 8 MiB / 备份 32 MiB / 接收 30s 边界及会话关闭；不写仓库 |
| `presentation/live_playlist_transfer_dialog.dart` | 复用 `LanTransferQrAddressCard`，拥有 TV 扫码弹窗、后台/退出清理和迟到会话隔离 |
| `presentation/live_player_page.dart / live_widgets.dart` | 固定顶栏、无底栏的全屏播放器，按需全屏设置（频道/节目单/音轨/线路/内核）、本地返回记录、Flutter TV 焦点及共享直播按钮；不提供上下频道按钮或静音入口 |
| `presentation/live_channel_picker.dart` | 播放器左分组／右频道选择器，固定 64dp 行高、当前频道定位、独立列滚动与 TV 跨列焦点；接收本地批量 now/next，复用 `live_widgets.dart` 的 `LiveCurrentProgramme` 显示各台当前节目，不自行读库或拥有播放会话 |
| `presentation/live_network_speed_label.dart` | 将 `LiveNetworkSpeedSource` 和换台 generation 适配到 playback 的共享 `playback_network_speed_label.dart`；格式／平滑位于 `domain/playback_network_speed.dart`，Exo 原生统计位于 `LiveTvNetworkSpeed.kt`，跨 Dart / Kotlin fixture 为 `test/fixtures/playback_network_speed.json` |

```text
AppRoutes.liveTv (/live-tv) -> LiveTvPage -> LiveRepository -> 独立直播数据库
                                       -> LiveSourcesPage (MaterialPageRoute)
                                       -> LivePlayerPage (root Navigator)
                                          -> LivePlaybackController
                                             -> MpvLiveEngine / ExoLiveEngine
                                                -> Android LiveTvView
```

设置“内容与来源”另提供直播与订阅入口。直播不调用点播 `PlaybackTargetResolver`、影视观看历史或 NAS 匹配；独立库及直播内核偏好不随配置 JSON/WebDAV 配置备份/影视收藏同步。实现边界见 [直播电视](live-tv.md)，焦点见 [TV 清单](tv-focus.md#直播焦点边界2026-09-20)。

扫码传输专项：`test/live_playlist_transfer_service_test.dart` 覆盖真实本机 HTTP、原始编码、备份校验、模式端点隔离、鉴权、上传边界、单次备份下载和清理，`test/live_playlist_transfer_page_test.dart` 覆盖 TV 分流、共享二维码、文件/地址草稿确认、返回/后台及迟到启动；`test/live_backup_transfer_page_test.dart` 覆盖 TV 手机备份/恢复、合并/替换确认、取消和后台丢弃，不等于手机到电视的跨设备验收。

共用文本扫码：`features/settings/presentation/widgets/settings_text_input_field.dart` 在 TV 输入弹窗内提供入口，同目录 `text_input_transfer_dialog.dart` 拥有会话，`features/settings/data/text_input_transfer_service{,_io,_stub}.dart` 接收最多 64 KiB 文本。服务边界见 `test/text_input_transfer_service_test.dart`；密码、多行、数字及确认取消见 `test/features/settings/presentation/settings_text_input_field_test.dart`。不依赖直播传输服务。

测试导航：`test/live_tv_test.dart` 为解析/仓库/控制器，`test/live_tv_data_test.dart` 为数据边界，`test/live_playback_lifecycle_test.dart` 为串行所有权/迟到事件/恢复预算，`test/live_tv_page_test.dart` 为布局/模拟遥控器，`test/live_exo_bridge_test.dart` 为 mock MethodChannel。路由、菜单配置和设置层级另见 `test/app/router/app_routes_test.dart`、`test/app_navigation_shell_tv_focus_test.dart`、`test/app_settings_test.dart`、`test/features/settings/presentation/settings_hierarchy_navigation_test.dart`。合并后这 9 文件共 132 项通过，最终统计见 [主机记录](performance.md#2026-09-20-直播前置验证快照)。Android 的 `LiveTvPolicyTest / LiveTvHttpTransportTest` 覆盖会话、画面比例、同源 headers、重定向与 HTTP 字节范围，共 17 项主机 JVM 测试。

`test/live_tv_data_test.dart` 与 `live_tv_test.dart` 的历史集合 38 项通过，不作为当前最终总数。`live_review_regression_test.dart` 覆盖独立 EPG TTL、发现地址、备份和取消确认；`live_backup_page_test.dart` 覆盖文件与弹窗。`channelOwners / epgLogos` 记录历史归属和台标。`live_backup.dart` 定义版本化备份，文件 IO 与界面分别由 `live_backup_file_*`、`live_backup_dialog.dart` 承担。生产播放适配器通过 `CancellableLiveEngine` 在队列外请求取消，控制器等待卸载确认再串行清理；原生永久挂起仍不是已验证的限时清理场景，详见直播文档。

### 播放与字幕

```text
PlaybackStartupCoordinator -> 本地续播 / 跳过准备
                           -> PlaybackTargetResolver
                           -> PlaybackEngineRouter -> PlaybackStartupExecutor
                             -> Flutter PlayerPage / 原生容器 / 外部播放器
```

- `player_page.dart` 是页面壳；`presentation/widgets/player_page_*.part.dart` 共享该 library 的状态，分别承载 MPV 启动、调参、恢复、控制、系统会话、运行动作和性能采集。
- `application/playback_stream_relay_service_io.dart` 负责 MPV/iOS 的敏感来源认证代理、媒体前缀验证和有界资源注册/过期回收；`playback_hls_rewriter.dart` 解析标准 HLS 点播/动态清单白名单并改写子请求，将 LL-HLS 回退为完整分片，不负责完整低延迟协议或 DRM。`native_playback_launcher_io.dart` 将传输地址与原始目标分开传递、回收迟到/关闭会话。Android `NativePlaybackHttpDataSource.kt` 复用逐跳 origin 策略，覆盖点播和媒体子请求。
- `playback_seek_coalescer.dart` 累计和合并 TV 定位输入；`playback_track_guard.dart` 给异步自动选轨提供会话/手动操作边界；`external_playback_file_store.dart` 只清理专属播放列表分配目录，不扫描系统临时根目录。
- `MpvPlaybackLifecycle` 持有单实例订阅及 `MpvSubtitleSession`，关闭时先失效回调并捕获旧资源的清理 Future；页面级恢复预算不随实例重建重置。`PlaybackPlatformSessionOwner` 持有系统媒体会话绑定、发布快照与生命周期代次，页面继续提供播放状态及遥控命令适配。
- 非 TV 控件基于 media_kit Adaptive Material / MaterialDesktop，TV 使用专用遥控层；Web 的 `embeddedMpv` 枚举值实际路由浏览器后端，不是浏览器里运行 libmpv。
- `playback_engine_support.dart` 是平台选项边界；`native_playback_launcher_io.dart` 桥接 Android Exo / iOS AVPlayer，`system_playback_launcher_io.dart` 负责外部应用 / 系统打开。
- `FntvSessionOwner` 与 `native_fntv_service.dart` 负责转码会话所有权和原生回调，失败 / 迟到的新会话也需释放；Exo 不另写一套 Authx 客户端。
- `playback_episode_browser.dart` 管季集浏览缓存，queue / next-episode 策略只预解析一个目标，不预建第二个播放器。
- `playback_episode_advance_guard.dart` 管自动切集取消、手动优先、失败去重和提交令牌；`playback_episode_preparation.dart` 管地址缓存、在途复用及一次前台期限。两者分别拥有操作意图和网络结果。
- `playback_interaction_player.dart` 在后端命令前截获手动 seek / 播放意图；`playback_intro_start_guard.dart` 在启动期间校验片头越界与就绪基线；`playback_completion_state.dart` 保存独立于真实进度的会话完成标记。
- `playback_remote_preflight.dart` 保留给原生 SmartStrm 格式探测；MPV 不调用该旧式启动预检。敏感凭据 relay 的有界媒体前缀验证属于独立安全传输边界。
- 在线字幕的 provider protocol、IO repository、validation pipeline 与共享 content processing 分工见 [subtitles.md](subtitles.md)；搜索结果不等于已经下载验证。
- `mpv_subtitle_render_binding.dart` 串行合并每个 Player 的字幕可见性属性写入；`player_menu_style.dart` 为播放菜单提供共享半透明主题，不改变解码逻辑。
- `playback_memory_repository.dart` 保存续播、最近播放、跳过规则和剧集字幕偏好；外挂文件仍限定当前集。

## 原生平台

### Android

直播专用 `LiveTvView.kt` 由 `MainActivity.configureFlutterEngine` 注册，视图类型 `starflow/live_tv`、实例通道 `starflow/live_tv/<viewId>`。Flutter 使用 `open / cancelOpen / stop / volume / audioTracks / audio / networkSpeed / cacheBytes / cacheDurationMs / videoFormat`；原生另有 `pause / play` 分支，但直播 UI 没有暂停/时移入口。状态与速率／缓存／格式查询携带换台 generation，TextureView 非焦点；标准 renderers 注册随包 FFmpeg 音频扩展并启用 decoder fallback，不进入点播 NativePlaybackActivity，也不继承其 TS/双字幕/自定义音频输出策略。`LiveTvDiagnostics.kt` 负责单实例音轨与输出、缓冲／流结束、掉帧／欠载的脱敏原生日志，不改变通道协议。能力边界见 [直播电视](live-tv.md)。

主要目录：`android/app/src/main/kotlin/com/example/starflow/`。

| 文件组 | 职责 |
| --- | --- |
| `MainActivity`、`StarflowApplication`、`NativeAppLogger` | Flutter 通道、启动及本地日志；系统历史退出信息要求 API 30+ |
| `NativePlaybackActivity / LaunchController / Coordinator / Session` | 原生页面装配、启动及 Exo 生命周期，不把策略都放回 Activity |
| `NativePlaybackSource / Target / Options` | Dart JSON 契约、媒体源与会话设置 |
| `NativePlaybackRuntimeController / RecoveryController` 及各 `*Policy` | tick、启动进展、缓冲、恢复、错误、HLS、TV seek 和焦点规则 |
| `NativePlaybackLoadControl / ReadAheadPolicy / HealthPolicy / FrameRateController` | TV 点播有界动态预读、活动读取采样、卡顿诊断限频与可选 Surface 帧率提示；Session 接入，Runtime 复用每秒循环 |
| `playback_relay_disk_cache.dart / playback_stream_relay_service_io.dart` | MPV／Exo／iOS 可选临时区间缓存、LRU／512 MiB 最低剩余空间保护、有验证器的滚动前向窗口、HLS VOD 分片与 WebVTT、会话清理和网络回退；本地文件直读，不提供独立下载 |
| `playback_stream_relay_contract.dart / native_playback_launcher_io.dart` | `PlaybackRelayCacheControl` 可选契约、当前会话磁盘快照及暂停／seek 控制；原生 resolver 通道校验 owner、URL 和 generation，隔离迟到响应 |
| `NativePlaybackRenderersFactory / AudioPolicy / AudioTracks` | renderer / sink、实际 MIME 输出策略、音轨身份恢复 |
| `NativeAudioOutputState` | 每个播放器的 sink 输入、decoder 与实际输出观测，供倍速重建判断及输出故障分类；不跨实例复用 |
| `NativeAudioPrecisionHistory / NativeAudioDecoderPrecisionPolicy` | 当前媒体按源音轨身份记录倍速临时降精度，恢复只尝试一次；FFmpeg float 恢复候选排除固定 PCM16 的 AC-3 |
| `NativePlaybackExtractorsFactory / PcmBluRayReader / PgsReader` | 有证据的 TS 扩展解析、LPCM 保位深转 PCM16/PCM24、PGS 显示集；高精度/兼容输出由 AudioPolicy、Session 和默认 AudioSink 决定 |
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

- `ios/Runner/AppDelegate.swift` 承载 Flutter 通道和宿主装配；`NativePlaybackViewController.swift` 管 AVPlayer 容器，`NativePlaybackModels.swift` 管请求、剧集队列及字幕偏好模型，`NativePlaybackMemoryStore.swift` 管播放记忆，`SettingsDocumentExporter.swift` 管文档导出。`PlaybackSystemSessionBridge.swift` 继续管共享音频会话、Now Playing、封面及远程控制。
- `NativePlaybackStartupGate / BufferingTuning / StallRecovery / Metrics` 分别管 AVPlayer 启动、缓冲、卡顿和指标；`NativeSubtitleLanguagePolicy.swift` 与 Dart / Kotlin 共用语言 fixture。
- `NativeExternalSubtitle.swift` 提供 iOS 有界文本字幕解析、时间定位、下载及原生文本叠层；`NativePlaybackViewController` 持有文档选择、在线搜索、选轨代次和退出清理。叠层不进入 PiP 视频，能力边界见 [字幕链路](subtitles.md)。
- `scripts/test_native_playback_startup.swift` 是 AVPlayer 策略主机 runner，验证预热在途、失败/取消和 HLS 分类；不是设备解码或像素首帧测试。iOS Metrics 的 `playingAtIso8601 / playingLatencyMs` 只表示播放状态信号。
- `ios/Runner/SceneDelegate.swift`、storyboard、Info.plist 和 Xcode 工程属于宿主配置。原生启动页只有深色底，Flutter Logo 是另一层。
- macOS 的 AppDelegate / MainFlutterWindow、Windows runner、Linux runner 主要负责 Flutter 宿主，不能据目录存在推断有 Android 同等原生播放器或后台会话能力。

## 工具与发布

2026-09-26 应用更新入口：`lib/features/update/application/update_controller.dart` 持有检查/下载/安装状态，监听 settingsController 的 webDavSync 配置；`domain/update_source.dart` 推导同步目录下 releases 地址并限制认证作用域。`data/update_manifest_client.dart` 有界读取普通 JSON，`update_manifest_parser.dart` 共用清单协议，`update_package_downloader{,_io,_stub}.dart` 持有私有流式下载与清理，`update_install_launcher.dart` 使用 `starflow/update`；`presentation/update_settings_page.dart` 接入设置入口及版本页脚。Android `AndroidUpdateInstaller.kt / AndroidUpdatePolicy.kt` 提供 APK 签名、安装身份校验与 FileProvider 授权，不加入播放通道。`tool/generate_update_manifest.dart` 生成普通 JSON 清单及 staging；清单 seed、公钥构建参数及其校验工具已删除，Android 签名配置不变；`scripts/publish_update_release.sh` 为本地发布准备入口。测试集中在 `test/update_*_test.dart` 与 Android `AndroidUpdate*Test`；上线与迁移步骤见 [应用更新](app-updates.md)。

| 入口 | 作用与注意事项 |
| --- | --- |
| `config/playback_policy.json` → `tool/generate_playback_policy.dart` | 生成 Dart `playback_policy_values.dart` 与 Kotlin `PlaybackPolicyValues.kt`；用 `--check` 校验，不手工单改生成值 |
| `config/release_version.json`、`tool/release_version.dart` | 四个发布脚本共用版本递增 / 显式批次值，Gradle 共用 Android 数字版本码策略；工具执行会写 pubspec，不作为只读检查 |
| `scripts/build_tv_apk.ps1` | TV 发布权威预设：release、API 23、ARM 双 ABI、按月版本、规范命名、桌面输出、显式配置嵌入 |
| `scripts/build_tv_apk_to_icloud.sh` | Bash 等价 TV 构建；普通交付用 `ICLOUD_INSTALLER_DIR="$HOME/Desktop"` |
| `scripts/build_ipa_to_icloud.sh` | 默认增量构建未签名 IPA，`STARFLOW_CLEAN_BUILD=1` 时先清理；不能直接当已签名安装包，会改版本 |
| `scripts/build_ios_then_tv_to_icloud.sh` | 串行执行 iOS IPA 和 Android TV APK 的 iCloud 构建；默认增量且跳过重复依赖解析，两端共用本次版本号，`STARFLOW_CLEAN_BUILD=1` 时清理，`STARFLOW_FORCE_PUB_GET=1` 时重新解析依赖，可选参数仅传给 TV 配置嵌入 |
| `scripts/prepare_ios_device_build.sh / verify_ios_device_frameworks.sh` | 清理误缓存的模拟器 Native Assets、检查设备 framework |
| `scripts/build_windows_installer.ps1`、`windows/installer/starflow_windows_installer.iss` | Flutter Windows 构建及 Inno Setup 安装器，会递增版本 |
| `scripts/flutter_with_mirror.ps1`、`connect_mumu.ps1`、`complete_android_setup.sh` | 镜像、模拟器连接和旧 SDK 辅助；环境与限制见网络文档 |
| `scripts/run_web_with_proxy.ps1`、`tool/web_dev_proxy.dart` | 本机 Web 开发转发；无身份验证，CORS 白名单尚未覆盖全部功能 |
| `scripts/rebuild_media3_audio.sh` | 固定源码重建 ARM 音频 JNI，需已有 AAR 提供 Java 类；非日常启动步骤 |
| `scripts/test_subtitle_language_contract.swift` | macOS 上独立编译的 Swift 语言契约 runner |
| `scripts/test_native_playback_storage.swift` | 使用隔离 UserDefaults 验证提取后的 iOS 队列、字幕偏好、续播、裁剪及外部写入失效；不是 AVPlayer 真机测试 |
| `tool/perf/run_perf_baselines.dart` | 五场景主机子进程计时，跨平台显式提供 `--output` |
| `tool/generate_brand_assets.py`、`generate_app_icons.swift` | Python 是统一资源导出入口，Swift 是转发兼容入口；使用 PNG 母版及 Edge 横幅渲染 |
| `tool/debug/manual_nas_grouping_test.dart` | 手动分组诊断，不属于默认 `flutter test` 回归集合 |

## 测试导航与维护原则

- 2026-09-24 结构证据入口：`library/data/structure_evidence.dart` 定义字段来源、显式优先级、规则编号和冲突；`external_media_structure.dart` 负责持久化兼容与编号合并。`webdav_nas_client_structure.dart` 在 WebDAV / Quark 共用推断分支记录依据，`nas_media_indexer_refresh_flow.dart` 保留 NFO 冲突。`test/external_media_structure_evidence_test.dart` 覆盖优先级、冲突去重/上限、旧 JSON 与命名规则；`test/nas_media_indexer_test.dart` 覆盖补全后的增量复用和记录序列化。

- Dart：`test/` 根目录及 `test/features/` 按领域覆盖模型、仓库、网络、缓存、页面和控制器；`test/core/` 覆盖公共身份等规则；`test/perf/` 是主机 smoke。
- 整理期间新增 `test/perf/performance_audit_probe_test.dart` 是行为 / 工作量审计探针，不在五场景计时脚本列表内，也不是设备性能报告；前面的全量结果不自动覆盖后续新增测试。
- Android：`android/app/src/test/kotlin/` 使用 JVM 单测及必要的 Android / Media3 stub，不执行 ARM decoder；测试报告不能替代电视显示、音频或网络验收。
- 跨语言字幕：`test/fixtures/subtitle_language_contract.json` 由 Dart / Kotlin / Swift 读取，修改语义时一起检查。
- iOS 的纯 Swift runner 不等于 Xcode 全量构建；macOS 模板 RunnerTests 也不等于所有业务回归。
- 当前执行结果、已知 Android 失败及运行命令见 [performance.md](performance.md)；不要在其他文档无日期地写“所有测试已通过”。

修改代码时优先保持现有 feature 边界、`part` 关系与平台条件导入；涉及用户行为同步 README 和专项文档。文档更新不得回退工作区已有变更，也不要提交凭据、原始日志、生成缓存或临时媒体样本。
