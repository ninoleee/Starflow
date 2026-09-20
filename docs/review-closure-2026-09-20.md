# 十项审查收尾

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

本机最近一次 `adb devices` 为空。未提供真实 NAS/订阅或 Android 6、TV、iOS 设备，不能在此条件下完成真机启动、遥控器/空鼠、真实转码释放、CDN 重定向、AudioTrack/HDMI 与 AVPlayer 播放验收。设备场景见 [performance-device.md](performance-device.md)，网络边界见 [development-network.md](development-network.md)。

API23 的 manifest、SDK 锁定和 ELF 检查属于发布门禁，不等于 Android 6 真机成功启动；历史签名保持升级身份，不应宣传为已更换正式签名。没有设备数据时不填写成功率、换台耗时、首帧、内存或音画同步收益。
