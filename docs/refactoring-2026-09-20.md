# 2026-09-20 组件边界重构

本记录对应详情、搜索与转存、缓存、播放器与 iOS 宿主四组并行整理。目标是明确任务和资源的所有者、消除重复业务编排，不以文件行数下降证明性能改善。组件的最终职责见 [架构说明](architecture.md)，入口见 [代码地图](code-map.md)。

## 保持的契约

- 详情匹配保持来源优先级、并发上限、逐批候选更新和取消检查；旧会话不回写新目标，不改变 TV 焦点或缓存恢复。
- 搜索保留结果去重、验链限流、页面失活取消排队和旧请求隔离；收藏与搜索的显示入口不变。
- 两种网盘继续使用独立协议客户端和工作流；共享入口只负责分发、凭据准备及反馈，不增加自动写操作重试。
- 缓存保留公共仓库入口、偏好 key、持久化格式、合并读取、串行修改和详情通知；组件拆分不是数据迁移。
- 播放器保持启动代次、恢复预算、切集、订阅释放及系统会话行为；Dart、Media3 和 AVPlayer 不合并为同一个内核实现。
- 本轮不调用发布预设，不递增版本，不生成交付安装包；已有其他任务的修改不回退。

## 重构前验证

2026-09-20，本轮编辑前的六文件定向回归共 **47 项通过**：

```sh
flutter test --no-pub --reporter expanded \
  test/detail_library_match_service_test.dart \
  test/media_detail_match_cancellation_test.dart \
  test/features/search/presentation/search_page_share_validation_test.dart \
  test/features/details/presentation/detail_online_resource_update_test.dart \
  test/local_storage_cache_repository_test.dart \
  test/player_startup_cancellation_test.dart
```

这是重构前主机行为基线，不是重构后结果，不覆盖实际播放、NAS 服务端、TV 焦点设备操作或 AVPlayer 真机生命周期。

随后补充的九文件跨模块基线 **80 项通过**，覆盖 `home_controller_test`、`library_cached_items_test`、`media_source_cache_lifecycle_test`、`detail_cache_episode_identity_test`、`detail_episode_restore_test`、`media_detail_match_restore_test`、`library_cache_scope_test`、`home_cache_scope_test` 和 `unification_regression_test`。这组结果同样只作为组件替换前的行为对照。

## 落地边界

| 分组 | 新所有者 / 入口 | 保留职责 |
| --- | --- | --- |
| 详情匹配 | `DetailLibraryMatchCoordinator` 与统一候选/取消类型 | 页面继续负责缓存恢复、选择状态、弹窗和 TV 焦点 |
| 搜索与转存 | `SearchRequest / SearchSession / SearchShareValidator`、`CloudSaveDispatcher` | 页面保留输入、收藏与提示；各网盘客户端和后处理独立 |
| 本地缓存 | `DetailCacheStore / MediaServerCacheStore`、公共模型文件 | `LocalStorageCacheRepository` 保留 provider、导出与兼容方法 |
| MPV 与 iOS | `MpvPlaybackLifecycle / MpvSubtitleSession / PlaybackPlatformSessionOwner`；四个 iOS 独立类型文件 | 页面保留启动/切集编排和恢复预算；AppDelegate 保留通道装配 |

搜索和详情均使用共享保存结果映射：115 已知协议错误保留客户端的具体提示，未预期的失败显示“保存未确认，请检查网盘后再重试”。不吞掉部分保存状态，不自动重发写操作。新增详情组件测试覆盖网络异常变成批次未确认后，只有一次保存请求且无 STRM/刷新。

仍保留的 `player_page_*.part.dart` 属于同一个页面 library；本次分离的是实例订阅、字幕观察器与系统会话资源，不宣称播放器全部业务状态均已迁出。详情页与搜索页仍包含较大的交互/展示子树，未为了缩短文件再引入额外抽象。

## 重构后验证

2026-09-20，本轮并行任务与主任务分别执行，测试集合有重叠，**不相加为唯一测试总数**：

- 详情组：11 文件、114 项通过，含 10 项新增协调器用例及取消、缓存恢复、选集与 TV 布局回归。
- 搜索组：搜索及相关保存/收藏集合 222 项通过；补充容量测试后的两个新增文件再次执行，21 项通过。
- 缓存组：六文件、54 项通过，含 15 项新增独立队列、兼容 facade、失效及释放用例。
- 播放组：定向 60 项及扩展 95 项通过，两批有重叠；新增测试覆盖旧实例关闭、迟到 sid 注册、订阅取消失败、平台绑定代次与后台节流。
- 主任务跨模块集成：11 文件、105 项通过，包含详情/搜索保存流程、首页/媒体库缓存消费者、剧集身份及恢复和公共逻辑；已包含新增详情未确认保存测试。
- 主任务新增组件与相邻行为复测：八文件、67 项通过，覆盖匹配协调器、搜索 session/保存分发器、MPV/系统会话所有者、缓存仓库、播放器启动取消和搜索验链。
- 主任务缓存所有权与 UI 回归：六文件、64 项通过，覆盖缓存释放/清空、搜索焦点/来源筛选、TV 二级页面和播放器小弹窗。Widget 测试不能替代实体遥控器操作。
- `dart analyze lib test`：无问题，记录对应本轮检查时工作树。
- `dart tool/generate_playback_policy.dart --check`、Xcode 工程 `plutil -lint` 与 `git diff --check`：通过；未修改策略生成值或运行发布入口。
- iOS：新增 `scripts/test_native_playback_storage.swift` 模型/存储 runner 通过，既有记忆契约 10 项与字幕契约 16 项通过；Runner Swift 语法、类型及模块编译检查通过，RunnerTests 仅完成类型检查。无签名、arm64、iOS 13.0 目标的 `xcodebuild` Debug 构建成功，不是签名安装包或发布预设。

并行工作区仍有性能、日志等其他任务的修改，以上不是全仓 Flutter 测试或 Android/iOS 完整发布构建结果，也没有新增设备性能测量。`NativePlaybackStartupGate.swift` 的既有主线程隔离警告及图标资源警告仍存在；未执行 XCTest、TV 遥控器、AVPlayer 真机后台切换或真实账号转存验收。

## 后续精简复核

2026-09-20，复核 `768a6b0..74dffd4`：详情、搜索、存储、播放及 `ios/Runner` 的生产代码合计新增 5606 行、删除 5589 行，净增 17 行；同提交 `test`、`scripts` 与 `tool` 下测试与脚本净增 1905 行。提交包含并行性能工作，不能全部归因于组件重构，也不能以主文件缩短证明整体简化。

本次后续精简只修改三个生产文件：详情控制器改由 notifier 单独持有状态，合并重复会话递增逻辑，移除未使用 getter；详情页删除四个纯转发函数，用 `listEquals/mapEquals` 替代手写比较；详情缓存删除未调用的状态读取包装。相对复核时 HEAD，生产代码新增 44 行、删除 118 行，净减少 74 行；新增控制器回归测试 71 行，无新增业务文件，无用户可见行为或性能改善声明。

本次重新执行九文件定向测试共 106 项通过：`detail_page_controller_test`、`detail_library_match_service_test`、`detail_library_match_coordinator_test`、`media_detail_match_cancellation_test`、`media_detail_match_restore_test`、`media_detail_enrichment_test`、`detail_online_resource_update_test`、`local_storage_cache_repository_test`、`cache_store_delegation_test`。`dart analyze lib test` 无问题。这是主机回归结果，不是全仓测试、发布构建或真机性能测量；此前记录不作为本次验证替代。
