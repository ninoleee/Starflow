# 直播模块协作契约

## 2026-09-20 审查修复接口

本节为 L01-L04 / D01-D04 修复的现行协作补充；下面原始约定保持为实现前历史草稿，不覆盖当前文件名和 API。

- 本任务只修改 `lib/features/live_tv/**`、Android `LiveTv*.kt`、相应测试与两份直播文档。共享 README、storage/network、settings transfer 由主任务处理。新到的 `live_playlist_transfer*` 文件/测试先读取并保持原有单次 M3U/TXT 草稿上传职责，不误认为它已实现备份。
- `CancellableLiveEngine.cancelOpen()` 必须在本代原生媒体卸载后完成；controller 不等待旧 open Future 自行完成，但必须等待取消确认，再串行 stop/dispose/reopen。不得把 open 的 Future.timeout 当作取消确认。MPV 单命令 loadfile，原生非锁 stop；Exo generation-scoped cancelOpen。未响应的取消确认仍阻止重开，原生初始化/卸载卡死的绝对清理上限尚非已完成验收。
- Exo pause/suppression reason 上行；暂停停止 watchdog/retry，resumed 才重新计时。页面保存静音，开流前应用到两种内核。controller generation 与 native token 双重隔离音轨选择。
- `LiveSource.epgUrl` 为用户覆盖；`discoveredEpgUrl` 为订阅发现，`effectiveEpgUrl` 为实际地址。旧 epgUrl 无法无损推断来源，保留为覆盖；本地 playlist 不参与远端 EPG TTL。
- 频道 `identity` 为显式 tvg-id。源内唯一时 v2 ID 不含名称/分组；重复身份不合并。切换频道表后只按当前 ID 关联偏好和 lastChannel。
- `LiveBackup` v1 保存七个 store：sources、channels、preferences、channelOwners、epg、epgLogos、meta。导入保留原 ID，32 MiB 上限，未知版本/非法关系拒绝；merge 只加入新来源、同 ID 保留本地，replace 单事务替换。刷新 epoch 防迟到回填；凭据按明文备份处理，UI 二次确认。
- UI 入口 `LiveSourcesPage -> LiveBackupDialog`，本地路径/文件选取，Web 文件下载；不修改共享配置 JSON/LAN/WebDAV 流程。TV 路径权限与跨设备搬运需实际设备核验。

2026-09-20 收尾验证：直播备份/审查回归/生命周期/Exo 通道/基础数据/页面/扫码传输等 9 个 Flutter 文件共 105 项通过，定向 `dart analyze` 无问题。备份文件 IO 移入测试真实异步区，TV 路径弹窗资源由路由内 State 持有；生产 MPV 在首个 await 前建立取消所有权。本地重导入改变有效 EPG 时使旧 TTL 失效，恢复后的旧失败也受 epoch 保护。Android/最终全量结果见 [审查收尾记录](review-closure-2026-09-20.md)。不把下方历史测试或 fake 引擎结果当真机验收。

## 原始约定（实现前快照）

日期：2026-09-20。此文件规定本轮并行实现接口，不表示功能已验收。实际能力和验证结果另见直播说明及性能文档。

## 所有权

- 数据任务：`lib/features/live_tv/domain/`、`data/`、`application/live_tv_controller.dart` 及相应测试。
- 播放任务：`application/live_tv_playback*`、`presentation/live_tv_player*` 及相应测试。
- 界面任务：`presentation/live_tv_page.dart`、`presentation/live_tv_sources_page.dart` 和其他直播 UI widgets 及相应测试，不编辑直播播放器文件。
- 集成任务：路由、主导航、设置入口、当前配置中的菜单常量、相关测试和最终文档，不编辑上述直播业务文件。
- 主任务负责合并和跨边界验证；各子任务不修改其他任务工作区或主工作区。已有未提交修改必须保留。

## 固定数据接口

路径：`package:starflow/features/live_tv/domain/live_tv_models.dart`。

- `LiveTvSource({required String id, required String name, required String url, bool enabled = true, Map<String,String> requestHeaders = const {}, Map<String,String> streamHeaders = const {}})`；提供同名只读字段及 `copyWith`、JSON 序列化。空 URL 表示本地文本导入来源，不可远程刷新。订阅下载头与视频头显式分离。
- `LiveTvStream({required String url, String label = '', Map<String,String> headers = const {}})`；同名只读字段及 JSON 序列化。
- `LiveTvChannel({required String id, required String sourceId, required String name, String group = '', String logoUrl = '', String epgId = '', required List<LiveTvStream> streams})`；同名只读字段及 JSON 序列化。频道 ID 不依赖临时播放 URL，跨来源不自动合并。
- `LiveTvSnapshot({List<LiveTvSource> sources = const [], List<LiveTvChannel> channels = const [], Set<String> favoriteIds = const {}, Set<String> hiddenChannelIds = const {}, String lastChannelId = '', Map<String,int> preferredStreamIndices = const {}, Map<String,DateTime> updatedAt = const {}})`；同名只读字段、`copyWith`、JSON 序列化；`visibleChannels` 返回来源启用、未隐藏且有线路的频道。缓存与偏好保持不可变快照。

## 固定控制器接口

路径：`package:starflow/features/live_tv/application/live_tv_controller.dart`。

- `liveTvControllerProvider`：Riverpod AsyncNotifierProvider，监听结果为 `AsyncValue<LiveTvSnapshot>`。
- `liveTvRepositoryProvider`：可替换的数据仓库 provider，供测试注入。
- controller 方法均返回 `Future<void>`，操作失败以不含 URL 或凭据的可展示异常报告，不清空成功快照：
  - `upsertSource(LiveTvSource source)`：仅保存来源，不隐式发网络请求。
  - `refreshSource(String sourceId)`、`refreshAll()`：有界刷新；后者只刷新启用的远程来源。
  - `importText({required String name, required String text})`：新建本地来源并解析保存。
  - `removeSource(String sourceId)`：删除配置及其缓存和本地偏好。
  - `toggleFavorite(String channelId)`。
  - `setChannelHidden(String channelId, bool hidden)`。
  - `rememberChannel(String channelId)`、`rememberStream(String channelId, int index)`。
- 控制器持久化修改串行，刷新网络不能阻塞收藏等本地操作；删除或编辑来源后迟到的刷新不得覆盖新来源。
- 网络读取默认 20 秒总期限和 8 MiB 正文上限，解析最多 10000 个频道；更新失败或有效频道为零保留已保存缓存。UI 可显式刷新，第一版不创建后台定时任务。
- 使用现有代理传输与有界请求基础设施；日志不包含订阅或播放地址的路径、查询、凭据、原始异常正文。不要把敏感地址交给会原样记录路径的 HTTP 包装层。

## 固定页面接口

- `LiveTvPage()`：频道主分支页面，路径文件 `presentation/live_tv_page.dart`。
- `LiveTvSourcesPage()`：来源管理独立页面，路径文件 `presentation/live_tv_sources_page.dart`。
- `LiveTvPlayerPage({required String channelId})`：专属全屏播放器，路径文件 `presentation/live_tv_player_page.dart`。
- 路由 `AppRoutes.liveTv` 为 `/live-tv`，`AppRoutes.liveTvSources` 为 `/live-tv/sources`，`AppRoutes.liveTvPlayer` 为 `/live-tv/player`；播放使用查询参数 `channel`。通过 `context.pushNamed(AppRoutes.liveTvPlayer.name, queryParameters: {'channel': channel.id})` 打开。
- 主路由保留现有五个分支索引，直播追加为索引 5；可见菜单把直播放在设置前。当前默认菜单包含直播。
- 复用已有深色主题、Material 图标、TV 焦点和设置编辑组件。来源管理支持订阅 URL、本地文件/文本导入、名称、请求头、更新、启停、删除和结果反馈。订阅成功添加后显式执行首次刷新，刷新失败配置保留以便修正。

## 播放边界

- 首版用 media_kit 专属直播页，不复用点播进度、跳过、选集或影视元数据流程，不伪造 MediaSourceKind。
- 一个活动播放器，换台串行并用代次丢弃过期结果；退出、后台及全局清理释放媒体资源，旧会话不能停止新会话。
- 接入 ActivePlaybackCleanupCoordinator 和播放优先状态；维持屏幕唤醒并正确释放。使用现有运行期 MPV 代理及受控低内存缓冲，不全局更改点播策略。
- 上下换台、确认打开频道列表、返回先关闭叠层再退出，线路选择、收藏、音轨、画面比例、重试及明确加载/失败状态。触屏/鼠标同样能使用全部核心功能。
- 有限连接/首帧等待、重连与备用线路总预算；只执行最新换台目标，避免叠音和旧回调更新。
- 不承诺 EPG、时移、回看、录制或原生 Exo 直播交互；不引入外部服务器、不内置来源不明的频道。

## 验证与交付

- 各任务只提交自己拥有的变更，返回 commit SHA、工作区绝对路径、测试命令与实际结果、未完成边界。
- 所有手工编辑使用 apply_patch。不得运行递增版本/发布脚本、不得修改生成物或清理用户改动。
- 单测优先覆盖解析、缓存失败保留、来源编辑/删除竞态、收藏持久化、快速换台、有限重连、退出释放、路由和遥控焦点。
- 主任务合并后运行整体静态检查与针对性测试；真实电视首帧、解码、遥控器和弱网性能单独标为待设备验收。
