# 十项审查收尾

> 历史收尾记录，2026-09-24 归档并合入同日组件重构记录。发布版本、构建中断、设备连接及测试状态均指当时快照，不代表今天的状态；后续验证见 [主机记录](../performance.md)。

日期：2026-09-20。本文针对用户列出的十项问题，区分代码、主机回归、发布产物和设备验收。工作区包含其他未提交修改；早期审查中的复现与测试仅代表修复前快照。

## 最终收尾状态

按用户要求停止所有后台构建后，改为串行完成必要验证，不再启动并行任务或发布构建。十项对应代码修复已落实；不能宣称完整发布验收或全仓测试全绿。

### 动态 HLS 与低延迟兼容回退（2026-09-20）

- 认证标准动态 HLS 已支持：没有 ENDLIST 时要求有效 TARGETDURATION 及完整分片，持续重读清单，响应禁止缓存；资源注册先完整校验再提交，失败刷新保留当前播放地址。非清单资源离开窗口两分钟后回收，旧地址永不复用；仍有 20,000 资源上限。
- LL-HLS 仅提供普通完整分片回退：过滤 PART、PRELOAD-HINT、RENDITION-REPORT、PART-INF、SERVER-CONTROL，不触发部分分片/阻塞/增量请求，不承诺低延迟效果。仅部分分片、SKIP 增量、未知扩展继续拒绝。**DASH、DRM 尚未实现**；DRM 还需要合法许可证端点、授权配置及播放器平台接入，不能用 AES-128 HLS 支持替代。
- 锁定 SDK 隔离副本串行回归 **41 项通过、0 失败**（`/tmp/starflow-live-hls.log`），覆盖动态刷新、资源过期/重新引入、失败刷新原子性、低延迟回退及已有 relay/native transport；修改文件静态分析无问题。没有安装包构建、版本递增或设备低延迟测量；以下为此前快照。

### 后续 HLS 完善（2026-09-20）

- 此前新增标准认证 HLS 点播代理：嵌套清单、初始化/媒体分片、AES-128 identity 密钥和 WebVTT 地址均登记后改写；跨 origin 不继承来源凭据，按重定向后的基址解析，保留签名 query。资源数、清单字节数、嵌套深度和等待时间有界。当时动态清单、DRM、DASH 与未知标签/属性仍明确拒绝；动态支持以顶部后续记录为准。
- 锁定 Flutter 3.38.10 在隔离副本中串行执行 9 个相关测试文件：**128 通过、0 失败**，日志 `/tmp/starflow-hls-isolated.log`。包含 HLS 密文、密钥 Range、相对 URL、外域请求、循环引用、恶意载荷、超大清单、关闭会话、原生传输、旧直链、凭据及配置 IO 回归；同副本 `dart analyze lib test tool/verify_tv_release.dart` **无问题**。隔离依赖解析未回写原工作区锁文件。
- 本轮全仓串行测试到 **1,656 项通过**时，工作区 `.dart_tool/package_config.json` 被移除，后续编译无法继续；发现另一个终端正在运行不同 SDK 的 iOS 发布流程，因此停止本任务测试，保留 `/tmp/starflow-full-serial-hls.log`，**不计作全量通过**。未终止或回滚外部终端工作。本任务未运行安装包构建、未递增版本；外部流程的版本/锁文件变化不属于本轮验证结果。
- 以下 200 项及 JVM/Swift 结果为此前快照，不与本轮 128 项累加。没有新增设备媒体解码或 Android 6 启动证据。

### 此前串行收尾快照

- 锁定 Flutter 3.38.10，单测试进程、`--concurrency=1` 的收尾集合 **200 项通过、0 失败**，日志 `/tmp/starflow-serial-closure.log`。覆盖上轮全部失败文件以及网络凭据、配置 IO、FNTV 启动释放、MPV/iOS relay、原生传输、旧直链与发布校验。详情按钮按实际可点击控件滚动定位，首页调度改为虚拟时钟，原行为断言保留；`fake_async` 显式声明为测试依赖。
- 该 200 项集合不是全仓测试；上轮锁定 SDK 全量在用户停止前有详情定位、着色器资源和计时失败，最终被中断。上述文件均已在本次串行集合通过；不把中断退出码或早期通过数包装为完整全绿。
- 补齐测试依赖并离线解析后，锁定 SDK 执行 `dart analyze lib test tool/verify_tv_release.dart` 无问题，`git diff --check` 通过。所有本次串行验证命令均已结束。
- Android 最后完整 JVM 快照为 **473 通过、1 可选样本跳过、0 失败**；Swift 策略/存储 runner 和全 Runner iOS13 类型检查通过。证据仍不替代设备播放。
- **此前收尾未交付新 APK**。1.9.175 因 SDK API 不兼容构建失败；修正后 1.9.176 构建被用户停止（Gradle 143），残留产物不符合内部版本核验。当时 `pubspec.yaml` 保留 1.9.176，不回滚、不重命名旧包；后续外部终端版本变化不据此回退。完整 APK 静态检查及 Android 6 启动仍待验收。
- 历史 Android Debug 签名身份仍保留以兼容覆盖升级，未迁移新证书。MPV/iOS 后续补上标准带认证 HLS 点播及动态清单代理，低延迟仅完整分片回退；DRM、DASH、其他播放列表/远程光盘仍明确拒绝。普通请求头及 Android 安全 data source 的 HLS 路径不受此代理限制。

## 当前实现

| 方向 | 实现与证据入口 |
| --- | --- |
| 网络凭据 | `http_origin_policy.dart` 检查协议/主机/端口及目录范围；Emby API/WebDAV 请求限制重定向，旧 Emby/NAS 直链同样经来源校验。Android 点播逐跳隔离来源 headers，覆盖清单、分片和网络字幕。`library_network_security_test.dart`、`network_security_test.dart`、`playback_target_resolver_test.dart` 及原生 data source 测试使用合成凭据和 loopback。 |
| 配置保护 | `LocalAppSettingsRepository.load` 仅将解析错误降级为内存默认值，不覆盖原始记录；Cookie 读取和协调保存 IO 错误不进入保存默认值分支。`storage_failure_recovery_test.dart` 注入异常。 |
| TV 发布 | 锁定 Flutter/engine、双 ARM/API23，禁止 SkipBuild，显式既有签名及 APK 内容核验。旧 1.9.174 的 API24 强符号结论不因新增预检自动变成兼容。签名仍是历史 Android Debug 身份，未迁移证书。 |
| 点播恢复 | 硬恢复不关闭页面会话 owner；恢复意图与 iOS 用户命令隔离迟到操作。新 FNTV 会话在读取播放记忆前接管，存储读取或取消失败走幂等释放。`playback_recovery_intent_test.dart`、`playback_startup_coordinator_test.dart`、episode guard 测试及 Swift runner 分别覆盖 Dart/原生策略。 |
| 元数据 | TMDB 身份包含媒体类型，失败不作无结果缓存，清缓存后的旧请求不覆盖新代。`tmdb_media_identity_test.dart`、`metadata_cache_race_test.dart`。 |
| TV 输入 | 媒体命令与 ActivateIntent 分离，共享控件接入指针操作。`tv_playback_input_test.dart` 是组件输入测试，不是物理遥控器。 |
| 字幕 | 无符号 moviehash、明确错集拒绝、过期字幕结果隔离。收尾补上手动飞牛字幕下载的选择版本保护，嵌套 guard 保留父启动保护，并阻止旧目标/偏好回写。 |
| 直播生命周期 | 生产适配器支持队列外 cancelOpen，控制器等待取消确认；静音随页面会话保留，音频焦点暂停/抑制不作为断流。原生卸载本身挂起时不冒险并发重开。 |
| Android 音轨 | 连续重建保留尚待恢复的音轨；明确 AAC/AC3 等冲突拒绝匹配，未知编码保持保守。NativePlaybackSession/AudioTracks JVM 回归。 |
| 直播数据 | EPG 发现值与用户覆盖分离，独立 EPG TTL；稳定 tvg-id 迁移偏好，版本化直播备份单事务恢复，旧刷新失效。备份不属于普通应用配置，可能包含明文凭据。 |

## 本轮验证

- 收尾前扩展 Flutter 集合 296 项通过，覆盖网络、配置、详情/元数据、点播应用层、TV 输入、字幕；此结果先于新增手动飞牛字幕保护。
- 新增字幕保护后的 6 文件集合 43 项通过：`playback_track_guard_test.dart`、`player_startup_cancellation_test.dart`、`player_auto_skip_interactions_test.dart`、`playback_recovery_intent_test.dart`、`fntv_transcode_test.dart`、`subtitle_pipeline_regression_test.dart`。两组有重叠，不累加为唯一总数。
- 直播 9 文件 105 项通过，覆盖备份文件/界面、EPG、身份迁移、取消确认、静音、焦点暂停和扫码传输，定向分析无问题。
- TV 公共控件 76 项、关联搜索/详情布局 20 项通过；公共设置输入弹窗另 6 项通过。Chip 恢复默认 50px，新增大字体与指针覆盖，设置弹窗等待退场后释放焦点资源。
- 详情恢复/取消及 `detail*test.dart` 集合 177 项通过。原生播放记忆通道 mock 和 TMDB 类型夹具补齐，原断言未放宽；删除同步测试同样补存储注入，3 项通过。
- 发布校验 32 项通过，锁定 SDK 预检通过，默认 Flutter 3.41.6 正确被拒绝。PowerShell 未安装，仅 Bash 运行时及隔离脚本验证。旧 1.9.174 APK 的 ARM64 Flutter 引擎仍被四个 `LIBC_N` 强符号检查拒绝。官方锁定引擎 ARM32/ARM64 build note 为 API21/22，无本次检测的较新版本强符号；不是新完整 APK 的验收。
- iOS Swift AVFoundation 策略 runner 通过；Runner 与 RunnerTests 在 iPhoneOS SDK、arm64/iOS13 目标无签名对象编译通过。新增迟到会话释放、退出幂等及命令入口回归；未执行 XCTest 或真实媒体播放，测试源码保留一条弱引用编译器建议警告。
- Android Gradle `:app:testDebugUnitTest -x :app:compileFlutterBuildDebug -Pandroid-skip-build-dependency-validation=true --offline --console=plain` 完成；XML 汇总 465 项，464 通过、0 失败/错误、1 跳过（未提供可选 LPCM 样本）。本轮补充快速连续重建、同步手动选轨 override、明确编码冲突及 mock 原生直播 View 生命周期；不是设备 AudioTrack/TextureView 验收。首次 5 个失败来自 Mockito 非空参数/嵌套 stubbing 和生命周期观察器夹具，修正后完整 JVM 复跑通过。
- `dart analyze lib test tool/verify_tv_release.dart` 无问题；播放策略生成检查与 Bash 语法检查通过。首页与详情清理 24 项复测通过。Swift startup runner 再次编译运行通过，覆盖 10 个用户命令入口及取消前后清理顺序。
- 补充调用链审查后，旧 Emby/NAS 直链入口及历史 Token 回归 83 项通过；FNTV 启动存储故障/退出释放相关集合 52 项通过。Android 新增安全 data source 9 项后完整 JVM 再跑 474 项，473 通过、0 失败/错误、1 可选样本跳过；该结果取代上方 465 项快照，不累加。
- HLS 扩展前的历史快照：MPV/iOS 安全 relay 定向集合 45 项、原生 launcher 传输通道 8 项通过；Swift 全 Runner 在 arm64/iOS13 SDK 类型检查通过，models/storage runner 加入传输地址不污染历史身份回归后通过。当时认证 HLS/DASH 等格式显式拒绝；不是当前 HLS 支持的测试证据，也不是媒体解码或设备后台保活验收。
- 使用锁定 Flutter 3.38.10 实际构建时发现新版 `TickerMode.valuesOf` 与 `ListView.separated.findItemIndexCallback` 不兼容，已改为等价旧版 API，并保留分隔列表的双倍子节点索引。`pubspec.lock` 同步 SDK 约束下的测试/分析依赖。锁定 SDK 静态分析修正后无问题；1.9.175 构建失败未交付，按预设不回滚版本，后续构建与全量结果以最终记录为准。
- 首轮完整 Flutter 为 2119 通过、25 失败；第二次完整执行为 2155 通过、4 失败，其中一个编译失败来自运行期间 coordinator 接口并行修改，另三个为删除同步测试缺少原生播放记忆 mock。性能集合随后通过，删除同步 20 项复跑通过。两次完整快照均不记全绿；以顶部串行收尾记录为最终状态，未完成命令不记为通过。

## 设备边界

本机最近一次 `adb devices` 为空。未提供真实 NAS/订阅或 Android 6、TV、iOS 设备，不能在此条件下完成真机启动、遥控器/空鼠、真实转码释放、CDN 重定向、AudioTrack/HDMI 与 AVPlayer 播放验收。设备场景见 [performance-device.md](../performance-device.md)，网络边界见 [development-network.md](../development-network.md)。

API23 的 manifest、SDK 锁定和 ELF 检查属于发布门禁，不等于 Android 6 真机成功启动；历史签名保持升级身份，不应宣传为已更换正式签名。没有设备数据时不填写成功率、换台耗时、首帧、内存或音画同步收益。

## 组件边界重构

本记录对应详情、搜索与转存、缓存、播放器与 iOS 宿主四组并行整理。目标是明确任务和资源的所有者、消除重复业务编排，不以文件行数下降证明性能改善。组件的最终职责见 [架构说明](../architecture.md)，入口见 [代码地图](../code-map.md)。

### 保持的契约

- 详情匹配保持来源优先级、并发上限、逐批候选更新和取消检查；旧会话不回写新目标，不改变 TV 焦点或缓存恢复。
- 搜索保留结果去重、验链限流、页面失活取消排队和旧请求隔离；收藏与搜索的显示入口不变。
- 两种网盘继续使用独立协议客户端和工作流；共享入口只负责分发、凭据准备及反馈，不增加自动写操作重试。
- 缓存保留公共仓库入口、偏好 key、持久化格式、合并读取、串行修改和详情通知；组件拆分不是数据迁移。
- 播放器保持启动代次、恢复预算、切集、订阅释放及系统会话行为；Dart、Media3 和 AVPlayer 不合并为同一个内核实现。
- 本轮不调用发布预设，不递增版本，不生成交付安装包；已有其他任务的修改不回退。

### 重构前验证

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

### 落地边界

| 分组 | 新所有者 / 入口 | 保留职责 |
| --- | --- | --- |
| 详情匹配 | `DetailLibraryMatchCoordinator` 与统一候选/取消类型 | 页面继续负责缓存恢复、选择状态、弹窗和 TV 焦点 |
| 搜索与转存 | `SearchRequest / SearchSession / SearchShareValidator`、`CloudSaveDispatcher` | 页面保留输入、收藏与提示；各网盘客户端和后处理独立 |
| 本地缓存 | `DetailCacheStore / MediaServerCacheStore`、公共模型文件 | `LocalStorageCacheRepository` 保留 provider、导出与兼容方法 |
| MPV 与 iOS | `MpvPlaybackLifecycle / MpvSubtitleSession / PlaybackPlatformSessionOwner`；四个 iOS 独立类型文件 | 页面保留启动/切集编排和恢复预算；AppDelegate 保留通道装配 |

搜索和详情均使用共享保存结果映射：115 已知协议错误保留客户端的具体提示，未预期的失败显示“保存未确认，请检查网盘后再重试”。不吞掉部分保存状态，不自动重发写操作。新增详情组件测试覆盖网络异常变成批次未确认后，只有一次保存请求且无 STRM/刷新。

仍保留的 `player_page_*.part.dart` 属于同一个页面 library；本次分离的是实例订阅、字幕观察器与系统会话资源，不宣称播放器全部业务状态均已迁出。详情页与搜索页仍包含较大的交互/展示子树，未为了缩短文件再引入额外抽象。

### 重构后验证

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

### 后续精简复核

2026-09-20，复核 `768a6b0..74dffd4`：详情、搜索、存储、播放及 `ios/Runner` 的生产代码合计新增 5606 行、删除 5589 行，净增 17 行；同提交 `test`、`scripts` 与 `tool` 下测试与脚本净增 1905 行。提交包含并行性能工作，不能全部归因于组件重构，也不能以主文件缩短证明整体简化。

本次后续精简只修改三个生产文件：详情控制器改由 notifier 单独持有状态，合并重复会话递增逻辑，移除未使用 getter；详情页删除四个纯转发函数，用 `listEquals/mapEquals` 替代手写比较；详情缓存删除未调用的状态读取包装。相对复核时 HEAD，生产代码新增 44 行、删除 118 行，净减少 74 行；新增控制器回归测试 71 行，无新增业务文件，无用户可见行为或性能改善声明。

本次重新执行九文件定向测试共 106 项通过：`detail_page_controller_test`、`detail_library_match_service_test`、`detail_library_match_coordinator_test`、`media_detail_match_cancellation_test`、`media_detail_match_restore_test`、`media_detail_enrichment_test`、`detail_online_resource_update_test`、`local_storage_cache_repository_test`、`cache_store_delegation_test`。`dart analyze lib test` 无问题。这是主机回归结果，不是全仓测试、发布构建或真机性能测量；此前记录不作为本次验证替代。
