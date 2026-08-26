# Starflow 真机性能基线

这套基线在真实 iOS/Android 设备的 Flutter `profile` 模式中运行。一次独立应用进程依次测量五个场景，主机脚本重复启动应用并汇总 p50/p95：

| 场景 | 测量边界 |
|---|---|
| `startup` | 测试入口创建完整 `StarflowApp`，经过启动页、路由和首页构建，直到首个首页分区可见 |
| `home_first_frame` | 创建生产 `HomePage`，直到首个固定数据分区可见 |
| `detail_open` | 创建生产 `MediaDetailPage`，直到详情标题可见 |
| `player_open` | 创建生产 `PlayerPage` 并打开固定的本地 H.264 小视频，直到视频尺寸已知且首帧开始播放或进度已前进 |
| `media_index` | 将 600 个固定 WebDAV 剧集条目扫描、分组并写入临时 Sembast 数据库，再读回索引记录 |

首页、详情、播放器媒体和索引数据都是确定性的本地夹具，不依赖网络或个人媒体库。每次运行均为新的 profile 应用进程，因此 `startup` 样本不会复用上一轮 Flutter 状态。

截至 `2026-08-27`，生产应用的首页模块加载和后台元数据预取使用独立队列，但与 Emby、NAS / WebDAV 调度共用一个最大并发设置。真机基线虽然使用固定夹具，比较真实业务构建时仍应同时记录独立的界面 / Hero / 播放设置、启动首页/Emby 刷新开关、统一并发值、首页与元数据批次参数以及日志记录级别，避免把设置差异误判成代码回退。TV 固定保护属于平台基线，不作为可调开关记录。

电影技术版本目录现在会在 `media_index` 阶段本地聚合为一个代表卡片，同时保留所有真实文件供详情页选择；旧误分类通过条目级指纹定向重建。比较新旧基线时除耗时外还要核对最终代表卡片数和底层记录数，避免把正确的卡片收口误判成索引丢失。详情页性能补充样本应同时覆盖“多个来源”和“单来源多个版本”：前者只构建资源信息区的来源选择，后者在 Hero 下方构建播放版本选择，两者不会把全部候选重复铺到同一个控件。

## 前置条件

- 使用与项目一致的 Flutter SDK，并先执行 `flutter pub get`。
- 真机已解锁、信任开发机，并能被 `flutter devices` 识别。
- iOS 已在 Xcode 中配置可用的 Development Team 与签名；Android 已允许 USB 调试。
- 为便于横向比较，固定设备、系统版本、刷新率、构建提交和慢帧阈值。关闭低电量模式，保持相近温度和电量。
- 对真实业务场景做补充测量时，固定最大并发任务数（默认 `2`）、元数据首批/批次间隔/交互恢复时间（默认 `12 / 300ms / 400ms`）、首页首批/批次间隔（默认 `2 / 350ms`）和本地日志级别。剧集样本需同时记录唯一系列查询数，电影多版本样本需记录根目录查询词与代表卡片/真实文件数量，防止文件名重复查询或错误拆卡被平均耗时掩盖；Emby 根列表应命中最多 `400` 条的来源摘要，完整匹配的 shard 解码并发不得超过 `2`。

## 执行

只有一台真机在线时：

```sh
dart run tool/perf/run_device_perf.dart --runs 5
```

多台真机在线时明确指定设备：

```sh
dart run tool/perf/run_device_perf.dart \
  --device 00008140-000279492213001C \
  --runs 5
```

也可以显式传 `--device macos` 在物理开发机上验证整条采集链路；该结果只适合与同一台 Mac 的后续结果比较，不能替代目标 iPhone/Android 设备的发布基线。

日常回归至少采 5 次；准备发布或调查抖动时建议采 10 次。自定义输出位置和 120 Hz 设备的帧预算示例：

```sh
dart run tool/perf/run_device_perf.dart \
  --runs 10 \
  --frame-budget-ms 8.333 \
  --output build/perf/iphone-release-candidate
```

脚本拒绝少于 3 次的聚合，也会拒绝非 profile 数据、缺失场景、缺失指标或零帧样本。任一轮失败时不会生成看似完整的汇总。

## 输出与指标

默认输出到 `build/perf/device-baseline-<UTC timestamp>/`：

- `runs/run_XX.json`：每个独立进程的原始五场景数据。
- `summary.json`：设备、Flutter、Git 状态以及各指标的 min/max/p50/p95 和排序后的样本。
- `summary.md`：便于代码评审和人工比较的汇总表。

`durationMs` 是场景开始到就绪条件成立的耗时。`slowFrameRate` 是 build 或 raster 任一阶段超过帧预算的唯一帧数除以总帧数。内存使用 Dart VM 的 `ProcessInfo.currentRss`，每 20 ms 采样一次并记录开始、峰值、结束和增量；它表示整个应用进程的常驻内存，不是单个 Dart isolate 的堆大小。

p50 适合看典型体验，p95 用于发现抖动。样本只有 5 次时，最近秩算法的 p95 等于最慢一次，这是有意的保守结果。比较两个提交时优先关注同设备同环境下的 p95 回退，并结合 `runs/` 排除热降频或后台任务造成的离群值。

如果要专门验证低性能 TV 的启动与首页体感，除了五个固定夹具场景，还应人工检查日志中的 `home.scheduler`、`metadata.prefetch-scheduler`、`storage.emby-cache`、`app.frame-performance` 和 `network.http`：同一次冷启动不应出现两轮首页自动刷新；Emby 来源根列表应记录 `sourceSummary=true`，指定分区应只读取目标 shard，同一来源不应同时出现两次相同全量加载；前台交互期间不应继续放大后台预取扇出，网络失败应带统一的 `failureKind`。

采样期间不要切到后台或触发系统低内存：前台恢复会有首帧后的 `400ms` 后台静默期，低内存会增加独立 `2s` 静默并取消媒体库后台刷新，这些都属于保护路径而不是常规基线成本。若日志出现队列等待 warning，应同时核对 `pauseHoldCount / globalPauseHoldCount / oldestWaitMs`，区分主动暂停和真实阻塞。

## 直接调试单轮

需要排查场景失败时，可绕过聚合脚本执行一轮：

```sh
STARFLOW_PERF_OUTPUT_DIR=build/perf/debug \
STARFLOW_PERF_OUTPUT_NAME=run_debug \
flutter drive --profile \
  -d <device-id> \
  --driver test_driver/performance_baseline_test.dart \
  --target integration_test/performance_baseline_test.dart \
  --dart-define=STARFLOW_PERF_RUN_ID=debug
```

不要用 debug 模式的数据建立性能基线；测试入口会主动拒绝它。
