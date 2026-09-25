# 主机性能与回归验证

本文负责主机侧 smoke 计时、可重复运行方法及自动化回归证据；验证日期以各节为准。2026-09-24 仅整理章节和归并直播记录，不重跑历史测试。电视、手机和桌面实际界面的测量方法见 [真机性能验证](performance-device.md)，组件关系见 [架构说明](architecture.md)。下文历史代码优化只说明工作量与策略变化，不代表已经测得设备收益。

## 2026-09-20 订阅保存按钮焦点配色

- `flutter test test/live_source_save_focus_test.dart test/live_sources_layout_test.dart test/live_accent_test.dart --reporter expanded`：3 文件共 52 项通过，其中新增 32 项覆盖全部 8 种强调色、添加／编辑订阅及 TV／非 TV；验证 TV 低亮度底色、白色描边的实际绘制、上下移焦和按钮尺寸稳定性，非 TV 保留强调色。
- `dart analyze lib/features/live_tv/presentation/live_sources_page.dart test/live_source_save_focus_test.dart`：无问题。
- 扩展检查未计为通过：运行时工作区的 `live_playlist_transfer_page_test.dart` 有 4 项失败（保存按钮匹配到多个元素及后台恢复状态转换断言）；`settings_text_input_field_test.dart` 因文件末尾存在 import 未通过编译。共用输入组件已修正 `const Semantics` 编译错误；对该组件分析另有一条既有 if 缺少花括号的 info。工作区扫码输入相关改动同期仍在更新，上述为执行时快照，不代表当前全部输入流程验收。
- 未执行真实 TV／遥控器验收，未生成 APK 或调整版本。此处为主机组件回归，不是设备性能测量。

## 2026-09-25 剧集卡片简介留白

使用项目固定 Flutter 3.38.10 运行 `test/detail_episode_summary_test.dart`、`test/detail_episode_restore_test.dart`、`test/detail_season_tabs_layout_test.dart`，共 30 项主机测试通过。新增 6 项覆盖 TV／非 TV 及 1／1.5／2 倍字体，断言三行简介下方仅保留 14dp 内边距（允许 1dp 取整误差）；修复前默认字体多留 22.75dp，新增断言可复现失败。选季布局、历史标记、滚动恢复、焦点与播放启动锁回归通过。卡片组件和摘要测试定向静态分析无问题。未做真机视觉验收、发布构建或版本递增。

## 2026-09-25 内容行高与间距统一

使用 `.fvm/flutter_sdk` 固定 Flutter 3.38.10。第一批运行主题、设置间距、详情简介／Hero／播放操作／剧集摘要与恢复／选季、首页呈现、搜索字体缩放、播放器选集、直播首页和设置层级共 13 个测试文件，214 项通过；第二批运行收藏海报与空标签间距、搜索字体缩放／分辨率筛选、媒体库可见性、设置选项弹窗／强调色、直播页面／订阅布局和首页横排共 9 个文件，68 项通过。两批包含重复文件，不合计为独立测试总数或全仓测试结果。

新增断言覆盖语义行高、按钮原有 padding、TV／非 TV 的 1／1.5／2 倍字体简介与设置项间距、空标签无占位，以及显式设置间距覆盖。搜索缩放与详情简介测试使用实际 `AppTheme`。最终 `flutter analyze --no-pub` 全仓通过；按用户要求不运行截图确认，未做真机视觉／遥控器验收、原生排版验证、发布构建或版本递增。字幕及原生播放器布局未修改。

## 2026-09-25 详情模块间距收紧

固定 Flutter 3.38.10 下，`detail_shared_widgets_test.dart`、`detail_episode_summary_test.dart`、`detail_episode_restore_test.dart`、`media_detail_match_restore_test.dart`、`detail_overview_section_test.dart` 共 65 项主机测试通过；6 个相关文件定向静态分析通过。验证公共模块外间距 14dp、TV／非 TV 与字体缩放下简介到下一区域的距离，以及卡片简介顶部 8dp／底部 14dp。初次扩展回归发现页面恢复测试仍断言旧卡片高度 269.25dp，更新为顶部收紧后的 263.25dp 后通过。未截图、未做真机验证、未构建发布包；本批与此前测试有重叠，不累加。

## 2026-09-25 剧集顶部与播放操作间距统一

固定 Flutter 3.38.10 下，`detail_hero_action_order_test.dart`、`detail_episode_summary_test.dart`、`detail_episode_restore_test.dart`、`media_detail_match_restore_test.dart`、`detail_season_tabs_layout_test.dart` 共 70 项主机测试通过，相关 6 个文件定向静态分析通过。新增手机／TV 双播放按钮到 Hero 底边均为 8dp 的布局断言；卡片顶部留白均为 14dp，覆盖字体缩放，底部与简介内部间距保持不变。横排默认总高随顶部增加 4dp 更新为 267.25dp。无独立端别设置，未截图、未真机验收、未构建发布包；与前批测试有重叠，不累加。

## 2026-09-25 电影标题 Hero 后间距

固定 Flutter 3.38.10 下，`media_detail_match_restore_test.dart`、`detail_hero_action_order_test.dart`、`detail_episode_summary_test.dart`、`detail_episode_restore_test.dart` 共 59 项主机测试通过，相关 3 个源码与测试文件定向静态分析通过。新增电影详情断言，要求 `DetailOverviewSection` 标题布局框顶部距 Hero 底边 8dp；剧集分支有独立卡片区块，不叠加该间距。未截图、未真机验收、未构建发布包。

## 2026-09-25 标题正文与模块间距再收紧

固定 Flutter 3.38.10 下，12dp 中间态先通过主题、公共设置间距、详情共享区块／简介／剧集／Hero／恢复、设置导航与选项、首页呈现、搜索收藏和直播页面共 13 个文件 179 项回归；随后按最终要求把设置区域标题上方也改为 8dp，并运行主题、公共设置间距、详情共享区块／简介／恢复和电影标题间距共 7 个文件 79 项回归，全部通过。最终规则为区域标题上方、区域标题到正文、详情正文模块之间和设置项默认间隔统一为 8dp；详情剧集横排底部另保留 10dp 焦点空间，卡片到下一区域合计 18dp。6 个相关文件定向静态分析无问题。未压缩正文行高、按钮 padding、TV 焦点区域或字幕排版。未截图、未真机验收、未构建发布包；各批测试有重叠，不累加。

## 2026-09-25 六档字号与 TV 字号统一

固定 Flutter 3.38.10 下，`app_theme_test.dart`、详情 Hero／简介／共享区块／剧集恢复、媒体库匹配恢复、首页呈现、搜索字体缩放、播放器选集、设置导航与选项、收藏海报和直播页面共 14 个文件 247 项主机测试通过；最终 `flutter analyze --no-pub` 全仓无问题，`git diff --check` 通过。字号统一为 36（Hero）、24（页面／大标题）、18（区域标题）、16（列表标题）、14（正文）、12（辅助说明），全局 TextTheme、详情、首页、播放器选集、设置和直播等显式字号已改用该组 token；详情 Hero 与选集面板移除 TV／普通端字号分支，同名内容两端同字号。品牌字标宽度、用户字幕倍率和头像首字母等按尺寸计算的动态值保持独立。剧集卡片自适应高度随正文从 13 调整到 14dp 字号，测试断言更新为 271.25dp。未截图、未真机验收、未构建发布包；本批与同日前序测试有重叠，不累加。

## 2026-09-25 标题正文与设置标题间距定稿

固定 Flutter 3.38.10 下，`app_theme_test.dart`、`settings_content_spacing_test.dart`、`detail_shared_widgets_test.dart`、`detail_overview_section_test.dart` 及相关详情回归通过；全仓 `flutter analyze --no-pub` 和 `git diff --check` 无问题。最终间距为区域标题到正文 10dp、上一内容到下一设置标题 12dp、正文模块之间 8dp、设置项之间 8dp。未截图、未真机验收、未构建发布包。

## 2026-09-25 资源信息行文字对齐

固定 Flutter 3.38.10 下，`detail_resource_info_section_test.dart`、`media_detail_match_restore_test.dart` 共 24 项主机测试通过，3 个源码与测试文件定向静态分析无问题。`FactRow` 与豆瓣链接行的标签、普通值统一使用 1.5 行高；链接按钮保留 30dp 点击高度并改为内容顶部对齐。新增断言覆盖状态、来源、链接和时长的标签与值顶部起点一致。未截图、未真机验收、未构建发布包。

## 2026-09-25 演职员分组标题层级

固定 Flutter 3.38.10 下，`detail_shared_widgets_test.dart` 和详情相关回归通过；新增 `DetailGroupLabel` 断言字号 16、`w700`、标题行高 1.3，并确认资源字段 `InfoLabel` 仍为 12。未截图、未真机验收、未构建发布包。

## 2026-09-25 Android 原生控制字号统一

Android `NativePlaybackEpisodePicker` 移除手机／TV 字号三元分支，标题、剧集行、季、状态和集号统一到 24/18/16/14/12；`native_player_control_view_phone.xml` 与 `native_player_control_view_tv.xml` 的标题、副标题和网速文字分别统一为 18/14/12。字幕用户倍率、图标和点击尺寸不进入字号统一。执行 Android 调试变体 Kotlin 编译验证；未构建 APK、未做 TV 真机验收。

## 2026-09-25 全局文本缩放设置

`AppSettings.uiTextScale` 将全局文本倍率持久化为 85%–130%、5% 步进、默认 100%；`设置 -> 界面 -> 界面文字大小` 使用公共步进控件调整。`StarflowApp` 将其乘到系统 TextScaler，Android 原生播放器通过 `uiTextScale` Intent extra 调整 Activity `fontScale`，因此 Flutter 页面、Flutter 播放器和 Android 原生播放器使用同一个用户设置。六档语义字号不变。

固定 Flutter 3.38.10 下，设置持久化、界面设置、原生播放传输和 App 启动共 5 个测试文件 59 项通过；修正倍率归一化的浮点误差后，`app_settings_test.dart` 32 项复跑通过。相关 7 个 Dart 文件定向静态分析无问题，Android `:app:compileDebugKotlin` 构建成功。未截图、未构建 APK、未做真机验收。

## 计时含义

`tool/perf/run_perf_baselines.dart` 串行启动 `flutter test` 子进程，用 wall-clock 记录整个子进程耗时，包含工具启动、可能的依赖检查、编译与测试执行。名称中的 `first_screen` 或 `player_open` 是场景标识，不是设备首屏 / 视频首帧时间，也不是远程服务吞吐量。

| 场景 | 实际测试入口（相对仓库根目录） | 主要覆盖 |
| --- | --- | --- |
| `startup` | `test/perf/bootstrap_smoke_test.dart` | Flutter 启动编排与截止时间 |
| `home_first_screen` | `test/home_controller_test.dart` | 首页来源及装配逻辑 |
| `detail_first_screen` | `test/media_detail_enrichment_test.dart` | 详情缓存和元数据补全 |
| `player_open` | `test/features/playback/application/playback_startup_preparation_test.dart`、`playback_startup_routing_test.dart`，以及 `test/perf/player_open_smoke_test.dart` | 本地准备、解析、路由、执行器协作，不运行真实 decoder |
| `index_refresh` | `test/media_repository_quark_source_test.dart` | 夸克来源索引读取 / 刷新契约，不等于真实 WebDAV 全库扫描耗时 |

默认每场景运行 5 次；`--scenario` 接受逗号分隔的场景 ID。每次保存原始 `runsMs`，p50 / p95 使用排序后的 nearest-rank（`ceil(n * p) - 1`）。只有 1 个样本时两者相等，5 个样本的 p95 实际就是最大值，不宜据此宣称稳定尾延迟。

## 当前验证记录

### 2026-09-25 日志页 TV 焦点

- 使用 `.fvm/flutter_sdk` 固定 Flutter 3.38.10 执行 `flutter test --no-pub test/core/widgets/tv_focus_test.dart test/core/widgets/tv_dialog_button_style_test.dart test/core/widgets/tv_remote_action_test.dart test/features/settings/presentation/settings_hierarchy_navigation_test.dart test/features/settings/presentation/home_auto_play_settings_test.dart test/features/settings/presentation/logging_settings_page_test.dart test/features/settings/presentation/log_export_page_test.dart --reporter expanded`，7 文件共 99 项通过。
- 新增回归覆盖日志开关、记录级别和预览级别保存期间保焦及重复确认拦截；日志预览新增项时保持当前节点，首条上移回到刷新、末条下移和左右键停留，空列表恢复刷新；清理确认默认取消并恢复触发按钮；电视导出页首焦点、二维码弹窗首焦点及返回链路、关闭弹窗后恢复导出入口。
- 对相关 8 个实现／测试文件执行 `flutter analyze --no-pub`，无问题。仅为主机组件验证，未做真实遥控器验收，未截图、未构建 APK 或调整版本。

### 2026-09-25 详情 Hero 与剧集刷新闪动

- 使用 `.fvm/flutter_sdk` 固定 Flutter 3.38.10，执行 `flutter test test/core/widgets/app_network_image_test.dart test/detail_episode_restore_test.dart test/detail_initial_artwork_test.dart test/media_detail_match_restore_test.dart test/detail_hero_section_test.dart test/detail_shared_widgets_test.dart --reporter compact`，6 文件共 73 项通过。
- 新增回归覆盖 TV／非 TV 的候选列表新增或重排、鉴权头变化、Hero 替换图片解码期间继续显示上一帧，以及预载／后加载季在元数据刷新后保留卡片、不闪回 loading、不重复读取。`flutter analyze` 全仓无问题，`git diff --check` 通过。
- 仅为主机组件和图片解码验证，未做真机视觉／遥控器验收，未构建安装包或递增版本。

### 2026-09-25 Hero 自动轮播焦点交接

- 使用固定 Flutter 3.38.10 执行 `flutter test --no-pub test/features/home/presentation/home_page_presentation_test.dart test/features/settings/presentation/home_auto_play_settings_test.dart test/tv_focus_regressions_test.dart --reporter expanded`，3 文件共 66 项通过；对首页页面、Hero 实现和新增测试执行 `dart analyze` 无问题，`git diff --check` 通过。
- 新增回归先让焦点从 Hero 移到下方模块，再返回 Hero，使用五张卡片连续自动切换两轮，并逐帧覆盖 `PageView` 惰性回收；普通／无边框模式、动画／简化模式修复前均会把焦点恢复到下方模块并停止轮播，修复后每轮焦点都落在新显示卡片。
- 修复未放宽用户主动移焦保护；已有自动轮播在翻页控件、下方内容、后台和覆盖路由时暂停的回归继续通过。仅为主机组件验证，未做 TV 真机长播验收，未构建 APK 或调整版本。

### 2026-09-25 共享按钮焦点与飞牛首页标题

- 最终调整：整个来源根的新增首页标题只显示来源类型，去掉“· 全部内容”，分区标题规则不变；原始 `sectionName` 保留。再次执行下述 3 文件回归，57 项通过，配置实现／测试静态分析无问题，`git diff --check` 通过。下条“来源根加全部内容”为本次调整前的中间状态。
- 后续统一全部来源命名：新增分区使用 `Emby / WebDAV / 夸克 / 飞牛 · 分区名`，来源根使用相同前缀加“全部内容”。固定 SDK 重跑 `flutter test --no-pub test/app_settings_test.dart test/home_controller_test.dart test/home_editor_tv_reorder_test.dart --reporter expanded`，57 项通过；实现及配置测试 `dart analyze` 无问题，`git diff --check` 通过。以下 139 项是此前只修改飞牛命名时的验证快照，不把“其他来源标题不变”视为最新命名规则。
- 使用固定 Flutter 3.38.10 / Dart 3.10.9，先执行 `flutter pub get`；`flutter test --no-pub test/core/widgets/tv_dialog_button_style_test.dart test/core/widgets/tv_focus_test.dart test/core/widgets/tv_playback_input_test.dart test/home_editor_tv_reorder_test.dart test/app_settings_test.dart test/home_controller_test.dart --reporter expanded`，6 文件共 139 项通过。
- 覆盖 8 种强调色下页面／弹窗的紧凑文字按钮与图标按钮：3 倍分辨率像素检查聚焦白边、失焦恢复、布局尺寸不变及遥控器确认；同时保留非 TV 配色、禁用／忙碌焦点和首页排序恢复回归。初次扩展测试使用 1 倍截图的边缘抗锯齿像素，32 项亮度断言失败；调整为描边内部高分辨率采样后完整重跑通过，未降低对比阈值。
- 分区配置测试覆盖飞牛默认“飞牛 · 分区名”、其他来源标题不变、来源／分区身份不变及自定义标题序列化保留。对两份实现与两份测试执行 `dart analyze`，无问题；`git diff --check` 通过。
- 仅为主机单元／组件验证，未进行真实 TV 遥控器验收，未构建 APK 或调整应用版本。

### 2026-09-24 最近搜索标题同排

- 固定 SDK 执行 `flutter test --no-pub test/features/search/presentation/search_page_source_tabs_test.dart test/features/search/presentation/search_page_text_scale_test.dart test/features/search/presentation/search_page_focus_test.dart --reporter expanded`，38 项通过；增加标题与关键词同排居中、彼此不重叠断言，覆盖手机 / 桌面 / TV、1 / 1.3 / 2 倍字体及横向滚动、TV 逐项导航和重新搜索。
- 对搜索页与两份修改的测试执行 `flutter analyze --no-pub`，无问题；`git diff --check` 通过。仅为主机组件验证，未做真机验收或构建安装包。

### 2026-09-24 搜索筛选分组布局

- 使用固定 Flutter 3.38.10，`flutter test --no-pub test/features/search/presentation --reporter expanded` 共 85 项通过；新增多选项在 390px 手机、1280px 桌面 / TV、2 倍字体下的分组布局、横向滚动及清除组合筛选回归。初次布局改动导致异步插入类型时两个 TV 焦点用例失败，选项约束容器补充稳定 key 后整组重跑通过。
- `flutter analyze --no-pub lib/features/search/presentation/search_page.dart lib/features/search/presentation/widgets/search_filter_row.dart test/features/search/presentation/search_page_resolution_test.dart` 无问题。使用 `STARFLOW_LAYOUT_SCREENSHOTS=build/search-filter-layout` 生成主机截图，并加载本机中文字体检查手机、TV 与大字体布局；测试数据不是实际服务结果，不等同于真机验收。未构建安装包或修改版本。

### 2026-09-24 Exo 媒体 URL 转义兼容

- 23:21 导出日志确认两次飞牛夸克 HLS 错误为 `Media HTTP request rejected: MALFORMED_URL`。WebDAV SmartStrm 的 Exo 首次首帧为 1580ms，续播首帧为 5557ms，另一条飞牛渐进式视频首帧为 2521ms；这是用户设备日志值，不是本机测量。两来源剧集文件路径的 MP4／MKV 标记不同，不能证明同文件；不再沿用此前 HTTPS 降级假设。
- 使用 JDK 17、固定 Flutter 3.38.10 的 Gradle 集成，沿用下节相同命令与六类测试选择，实际编译 Kotlin 并完成 43 项 JVM 测试，0 失败／错误／跳过。新增覆盖资源路径和查询中的未转义字符、真实 `x-oss-process={...}` 格式、签名转义大小写／加号／重复参数保留、相对及跨源重定向、真实 loopback 请求路径及凭据隔离；控制字符、反斜线、无效转义、authority、降级拒绝保持有效。`git diff --check` 通过。
- 使用当前 v3 配置重新调用飞牛接口后，失败主清单均返回 HTTP 200；分片 `x-oss-process=if_status_eq_404{hls/ts,from_<base64>}` 的原始花括号被 Java `URI` 拒绝，编码为 `%7B%7D` 后 CDN 返回 HTTP 200 / `video/MP2T`。因此根因已由真实配置与真实 CDN 响应确认，不再是推测。电视端完整播放仍待安装修复版本复测；没有构建 APK、递增版本或执行全仓测试。当前行为见 [开发网络](development-network.md#原生播放请求拒绝诊断2026-09-24)。

### 2026-09-24 Exo 请求拒绝诊断

- 在 `android/` 使用 JDK 17 和指向 `.fvm/flutter_sdk` 同一 Flutter 3.38.10 安装的 `local.properties`，执行 `./gradlew :app:testDebugUnitTest -x :app:compileFlutterBuildDebug -Pandroid-skip-build-dependency-validation=true --console=plain`，通过 `--tests` 限定 `*LiveTvPolicyTest`、`*LiveTvHttpTransportTest`、`*NativePlaybackHttpDataSourceTest`、`*NativePlaybackLoadErrorPolicyTest`、`*NativePlaybackErrorPolicyTest`、`*LiveTvPlaybackErrorTest`。6 类共 39 项通过，0 失败／错误／跳过；Kotlin 实际编译，跳过 Flutter 打包。
- 新增固定拒绝原因、URL parser 异常脱敏、重定向拒绝不发出目标请求、本地媒体的无效远程子请求，以及包装后的策略异常不重试回归；原有同源鉴权、跨源剥离、Range、gzip、HTTP 状态和传输监听回归保持通过。`git diff --check` 通过。
- 用户日志只能确认应用 HTTP 校验拦截，无法区分当时的具体拒绝原因；本机复查原清单返回 403，没有获得真实分片清单。此次为诊断及失败等待修复，不代表两部影片已能播放；需要新的失败日志或有效播放列表继续定位。未进行真机播放、全仓测试、APK 构建或版本递增。协议边界见 [开发网络](development-network.md#原生播放请求拒绝诊断2026-09-24)。

### 2026-09-24 网络资源清晰度筛选

- 使用 `.fvm/flutter_sdk` 固定 Flutter 3.38.10 / Dart 3.10.9，先执行 `flutter pub get`；`flutter test --no-pub test/search_result_resolution_test.dart test/search_models_test.dart test/search_repository_test.dart test/search_share_deduplication_test.dart test/features/search --reporter expanded` 共 224 项通过。
- 新增清晰度别名、中文标题、合集多档位、未知画质、来源及 URL 排除测试，以及手机 390px、桌面 / TV 1280px、2 倍字体下的组合筛选、取消、空交集、异步批次、新搜索重置、本地与收藏隔离组件回归。早期新增收藏测试使用旧数组格式，已改用现有 `FavoriteSyncDocument` 并注入独立偏好仓库后重新通过。
- 对清晰度模型、搜索页及两份新增测试执行 `flutter analyze --no-pub`，无问题。仅为主机单元 / 组件验证，未进行实际搜索服务、视频分辨率探测或 TV 真机验收，未构建安装包或递增版本。

### 2026-09-24 STRM 源文件大小

- 使用 `.fvm/flutter_sdk` 固定 Flutter 3.38.10，先执行 `flutter pub get`。`flutter test test/webdav_strm_file_size_test.dart test/webdav_nas_client_test.dart test/media_detail_enrichment_test.dart test/detail_resource_info_section_test.dart --reporter expanded`：4 文件共 77 项通过；补充 `flutter test --no-pub test/library_network_security_test.dart test/network_security_test.dart --reporter expanded`：2 文件共 27 项通过。
- 新增回归覆盖探测失败清除包装文件大小、HEAD/GET 206 总长度、未知/无效 Content-Range、忽略 Range 的完整响应、播放列表/错误文档/压缩长度排除、同源及跨源重定向、跨源后不恢复 NAS 凭据、重定向次数上限、非 HTTP 地址拒绝及响应正文立即取消。
- `flutter analyze --no-pub lib/features/library/data/webdav_nas_client.dart test/webdav_strm_file_size_test.dart` 无问题，`git diff --check` 通过。以上仅为主机模拟网络及现有本机 HTTP 安全回归，未使用用户实际异常资源、未做真机验证或全仓测试，未生成安装包或递增版本。网络规则见 [开发网络](development-network.md)。

### 2026-09-24 全部媒体库作品聚合

- 使用 `.fvm/flutter_sdk` 固定 Flutter 3.38.10 / Dart 3.10.9，先执行 `flutter pub get`，再运行 `flutter test --no-pub --reporter expanded`：`media_work_aggregation_test.dart`、`home_controller_test.dart`、`features/library/presentation/library_cache_scope_test.dart`、`media_detail_match_restore_test.dart`、`detail_entry_source_preference_test.dart`、`library_cached_items_test.dart`、`media_detail_models_test.dart`、`detail_episode_restore_test.dart`、`features/home/application/home_cache_scope_test.dart`、`detail_library_match_service_test.dart`、`detail_library_match_coordinator_test.dart`，11 个文件共 117 项通过。
- 覆盖整剧／电影 ID、IMDb 大小写、跨 ID 桥接、冲突与同名翻拍、缺年份拒绝合并、季集身份隔离、分页作品数、来源列表不聚合、资源 JSON 不变，以及无缓存／关闭自动匹配时切换来源季集树、电影来源与同来源版本的实际 widget 点击。
- 修正前运行曾包含不存在的 `detail_page_actions_test.dart` 路径；新增 widget 用例还修正了测试视口、延迟启动等待及版本控件定位。这些失败不是通过结果，以上最终集合已重新执行。聚焦本次实现与测试的 `dart analyze` 无问题，`git diff --check HEAD` 通过。
- 仅为主机单元／组件回归，未执行全仓测试、真实媒体服务器／NAS 播放或 TV 真机验收；未运行发布预设、构建 APK 或递增版本。

### 2026-09-24 结构证据与冲突持久化

- 使用 `.fvm/flutter_sdk` 固定 SDK，运行 `flutter test --no-pub --reporter expanded`，覆盖 `external_media_structure_evidence_test.dart`、`nas_media_indexer_test.dart`、`webdav_structure_real_world_naming_test.dart`、`webdav_nas_client_test.dart`、`media_repository_quark_source_test.dart`、`nas_media_index_store_scope_test.dart`、`nas_media_recognition_test.dart`、`nas_media_recognizer_test.dart`、`season_folder_label_parser_test.dart`。2026-09-24 本次复验 9 个文件共 195 项全部通过，包含新增结构证据用例及编号冲突的索引复用/序列化、仅规则变化落盘断言。
- 修正前快照为 194 项通过、1 项失败：`NFO fills gaps by ID only and survives refresh: true` 的时长预期 `100分钟`，实际 `1h 40m`。两者时长相同，失败是展示字符串断言不一致；当前测试已采用 TMDB 客户端 `_formatRuntime` 的既有格式 `1h 40m`，无需改变生产时长逻辑。另使用 `--plain-name 'NFO fills gaps by ID only and survives refresh'` 定向复验，有 ID 和无 ID 两项均通过。此前 192 项通过及后续失败均是历史快照，本次通过仅涵盖上述主机回归范围。
- 聚焦 `dart analyze` 检查结构模型、证据定义、WebDAV 扫描、索引刷新及相关新增/扩展测试，无问题；`git diff --check` 通过。没有全仓测试、真实 NAS/网盘请求、TV 真机验证或性能计时；未运行发布预设、未生成 APK、未为本次修改递增版本。

### 2026-09-21 直播 5 秒等待策略

- 调整直播单线路开流与无进展 watchdog 为 5 秒；自动恢复仍最多 3 次，按 2／4／6 秒退避并轮换多线路，恢复期间显示当前目标线路，单线路显示重新连接。开流 deadline 先于 progress watchdog 注册，避免同时到期时把阻塞中的开流误报为进度超时。
- 使用固定 Flutter 3.38.10／Dart 3.10.9，`.fvm/flutter_sdk/bin/flutter test --no-pub --concurrency=1 --reporter expanded test/live_playback_lifecycle_test.dart test/live_exo_bridge_test.dart test/live_tv_page_test.dart`：修正计时器顺序和页面测试进度事件后，3 文件共 44 项主机测试通过；`.fvm/flutter_sdk/bin/dart analyze lib/features/live_tv/application/live_playback_controller.dart lib/features/live_tv/presentation/live_player_page.dart test/live_playback_lifecycle_test.dart test/live_tv_page_test.dart` 无问题。
- 本次验证覆盖超时后的旧事件隔离、取消与线路提示、5 秒无进展恢复及重复会话布局；未运行发布预设、未构建 APK，也没有真实直播源或真机播放测量。用户日志中的部分频道首次首帧超过 5 秒，因此该策略会主动切换这些慢启动线路。

### 2026-09-20 直播选台移焦与滚动顺序

- 固定 Flutter 3.38.10／Dart 3.10.9，`.fvm/flutter_sdk/bin/flutter test --no-pub --reporter expanded test/live_channel_picker_test.dart test/live_tv_page_test.dart test/live_current_programme_test.dart`：3 文件共 29 项主机测试通过。选台专项单独运行 9 项通过，与合并集合重叠，不累加。
- 新增 100 频道场景在按键后、`pump` 前检查目标已获得焦点；下一帧检查目标行完整可见。覆盖可见行不滚动、下边缘最小滚动、反向移动／上边缘，以及同一绘制帧前连续长按重复事件推进。现有跨列、切组、打开定位、返回、触摸和节目单回归通过。
- `.fvm/flutter_sdk/bin/dart analyze lib/features/live_tv/presentation/live_channel_picker.dart test/live_channel_picker_test.dart` 无问题。以上验证焦点状态和布局时序，未进行真机逐帧录像、像素残影或遥控器验收；未构建 APK 或递增版本。

### 2026-09-20 直播首页工具按钮移位

- 固定 Flutter 3.38.10／Dart 3.10.9，执行 `.fvm/flutter_sdk/bin/flutter test --no-pub --reporter expanded --dart-define=LIVE_TV_REVIEW=true test/live_home_layout_test.dart test/live_tv_page_test.dart test/live_channel_probe_page_test.dart`，3 文件共 64 项主机测试通过。布局断言覆盖 320／390／768 竖屏与 640／844／1280 横屏、TV／非 TV，检查检测／订阅／整理均在收藏右侧同一行且不越界；原有分组、旋转、检测和页面交互回归通过。
- 页面布局测试补充检测与网络状态 provider 替身，解决首次回归中真实 connectivity 插件未注册导致的 5 项失败；未改变生产网络监听。页面及两个布局测试文件定向静态分析无问题。
- 检查 `build/live-tv-review/library-390.png` 与 `library-640.png`，确认标题栏不再显示三按钮、竖屏随收藏整体换行、横屏保持两列，无内容重叠。测试字体仍有既有收藏／历史标签缺字；使用合成数据，未做真机验收、构建 APK 或递增版本。

### 2026-09-20 直播可见频道自动补测

- 固定 Flutter 3.38.10／Dart 3.10.9，以下 10 文件最终共 **124 项主机测试通过**，定向静态分析无问题。不是完整测试套件或真机验收。没有运行发布预设、递增版本或更新此前 iCloud 安装包。

```sh
.fvm/flutter_sdk/bin/flutter test --no-pub --reporter expanded test/live_channel_probe_test.dart test/live_channel_probe_controller_test.dart test/live_channel_probe_page_test.dart test/live_probe_network_test.dart test/network_proxy_config_test.dart test/live_home_layout_test.dart test/live_tv_page_test.dart test/live_current_programme_test.dart test/live_navigation_resume_test.dart test/live_failure_logging_test.dart
.fvm/flutter_sdk/bin/dart analyze lib/features/live_tv/application/live_channel_probe_controller.dart lib/features/live_tv/presentation/live_tv_page.dart lib/features/live_tv/presentation/live_probe_label.dart test/live_channel_probe_controller_test.dart test/live_channel_probe_page_test.dart
```

- 覆盖同屏到期刷新、单调度定时器、成功 5 分钟、失败 45／90／180／300 秒退避及成功重置、刷新保留旧结果、离屏取消刷新、暂停清除定时器、恢复只补测可见过期项、路由返回复用有效缓存、播放器返回补测、手动暂停不被筛选／网络解除、后台（含其他路由覆盖期间）返回失效、离线跨后台恢复仍禁止准入。既有两路并发、慢清理占用名额与旧代结果隔离复测通过。
- 使用 `--dart-define=LIVE_TV_REVIEW=true` 单独运行检测页面的 `initial probe labels fit` 六个尺寸／平台用例，均通过。检查 `build/live-tv-review/probe-refresh-320-false.png` 与 `probe-refresh-1280-true.png`，刷新图标、台名及旧结果无重叠；截图是合成数据，收藏筛选仍有测试字体缺字，不代表真实设备字体或性能。
- 首页存活期间的系统网络订阅仅被动收事件，不是后台检测；离页／停止无检测定时器或新 HTTP 请求。同类型 Wi-Fi 切换仍依赖系统报告，后台或监听异常后返回保守失效。未验证真实源、网络切换、设备吞吐或 TV 帧率。

### 2026-09-20 直播检测调度与缓存优化

- 以下为自动补测改动前的历史快照；“仅重入 TTL／返回不重开”等旧预期已被上方记录取代，不作为当前行为验收。
- 使用固定 Flutter 3.38.10／Dart 3.10.9；新增 `connectivity_plus 6.1.5` 系统接口监听，`clock` 显式声明用于可控时钟，通过该 SDK 的 pub get 更新依赖及桌面插件注册。未运行 clean、发布预设、递增版本或生成交付 APK。
- 以下 10 文件共 **116 项主机测试通过**，包含横屏双列布局。新增覆盖 200ms 准入边界、短暂可见不请求、停止清除等待、TV 焦点优先、成功 5 分钟／失败 45 秒仅重入过期、元数据快照保留任务、线路变化／停用取消、离线恢复、代理变更与不重启停止会话、系统事件去重／取消订阅。初轮一项用例误把早已可见的排队频道作为新入屏频道，修正 fixture 后重跑通过。

```sh
.fvm/flutter_sdk/bin/flutter test --no-pub --concurrency=1 --reporter expanded test/live_channel_probe_test.dart test/live_channel_probe_controller_test.dart test/live_channel_probe_page_test.dart test/live_probe_network_test.dart test/network_proxy_config_test.dart test/live_home_layout_test.dart test/live_tv_page_test.dart test/live_current_programme_test.dart test/live_navigation_resume_test.dart test/live_failure_logging_test.dart
.fvm/flutter_sdk/bin/dart analyze lib/features/live_tv/application/live_channel_probe_controller.dart lib/features/live_tv/data/live_channel_probe.dart lib/features/live_tv/data/live_probe_network.dart lib/features/live_tv/presentation/live_tv_page.dart lib/core/network/network_proxy_runtime.dart test/live_channel_probe_controller_test.dart test/live_channel_probe_page_test.dart test/live_channel_probe_test.dart test/network_proxy_config_test.dart test/live_probe_network_test.dart
```

- 定向静态分析无问题。清理测试验证慢清理报警后仍未完成、客户端已关闭但继续等待响应流、完成日志仅含耗时／取消字段；loopback 覆盖等待头／正文时取消。挂起测试由受控 completer 最终释放，不证明任意操作系统故障可在有限时间清理。
- 在 `android/` 执行 `./gradlew :connectivity_plus:compileDebugJavaWithJavac -Pandroid-skip-build-dependency-validation=true --console=plain` 成功。插件 minSdk 19 与应用 API 23 目标兼容；构建自动安装所需 Android SDK Platform 34，输出本机 build-tools 36.1.0 `package.xml` 损坏告警与 Gradle 弃用告警，最终退出码 0。仅编译插件，不是完整 APK、iOS／桌面原生构建或真机网络切换验证。
- 系统连接类型通知不是互联网可达性或完整网络身份检测；同类型 Wi-Fi 热切换未报告时依靠后续重入 TTL／前台恢复失效／手动重测。本轮没有新增截图或真实吞吐、TV 帧率测量；历史截图与性能数据不自动升级为当前设备验收。

### 2026-09-20 直播首页横屏分栏

- 在当前横屏分栏与可见范围检测合并的工作区，固定 Flutter 3.38.10／Dart 3.10.9 执行以下 5 文件，共 **73 项主机测试通过**。首次运行的布局草稿误将 Android 内核下拉计作分组下拉；补充分组控件 key 并修正匹配后重跑通过，不改内核选择行为。

```sh
.fvm/flutter_sdk/bin/flutter test --no-pub --reporter expanded --dart-define=LIVE_TV_REVIEW=true test/live_home_layout_test.dart test/live_channel_probe_page_test.dart test/live_tv_page_test.dart test/live_current_programme_test.dart test/live_navigation_resume_test.dart
.fvm/flutter_sdk/bin/dart analyze lib/features/live_tv/presentation/live_tv_page.dart test/live_home_layout_test.dart
```

- 布局专项覆盖 390×844、768×1024 竖屏及 640×360、844×390、1280×720 横屏，均含 TV／非 TV；检查左分组右频道、独立滚动、长名称／1.5 倍字号、分组切换、旋转保留筛选与整理状态、分组删除／空库回退，以及模拟遥控器上下选组和左右跨列。检测、当前节目、导航及原页面交互在分栏后复测通过。
- 定向静态分析无问题。检查 `build/live-tv-review/library-390.png`、`library-640.png`、`library-1280.png`，确认竖屏下拉保留、横屏分栏及文字／操作无重叠。截图使用合成频道和测试字体，收藏筛选／历史按钮仍有测试字体缺字，不作为真实设备字体或遥控器验收。
- 未运行发布预设、构建 APK、递增版本或执行真实源／真机测量。与其他历史批次重叠，不累加为全仓测试总数。

### 2026-09-20 直播可见范围检测与取消

- 验证时点：本批完成于后续“横屏首页两列分组”改动之前，不自动覆盖该并行布局修改；后续布局需重跑可见范围和分组交互测试。
- 固定 Flutter 3.38.10／Dart 3.10.9 下，以下 6 文件共 **78 项主机测试通过**，其中 HTTP 服务 15 项、可见范围调度 6 项、首页检测交互 26 项。此批包含首次自动检测接入，与旧记录不累加；未运行 pub get、clean、发布预设或递增版本。

```sh
.fvm/flutter_sdk/bin/flutter test --no-pub --concurrency=1 --reporter expanded --dart-define=LIVE_TV_REVIEW=true test/live_channel_probe_test.dart test/live_channel_probe_controller_test.dart test/live_channel_probe_page_test.dart test/live_tv_page_test.dart test/live_current_programme_test.dart test/live_navigation_resume_test.dart
.fvm/flutter_sdk/bin/dart analyze lib/features/live_tv/data/live_channel_probe.dart lib/features/live_tv/application/live_channel_probe_controller.dart lib/features/live_tv/presentation/live_tv_page.dart lib/features/live_tv/presentation/live_probe_viewport.dart test/live_channel_probe_controller_test.dart test/live_channel_probe_page_test.dart test/live_channel_probe_test.dart
```

- 定向静态分析无问题。80 频道手机／TV widget 场景验证首次请求集合等于视口相交行，排除已构建但离屏的缓存行；滚动补测、返回复用结果、搜索切换、分组菜单暂停／关闭后继续均通过。检测结果仅局部刷新，未把工作量下降换算为设备帧率收益。
- 取消回归覆盖离屏移除排队任务、清理完成前保留两路名额、快速停止／重开不混入旧结果、后台／路由／非活动 tab／销毁取消、不自动重启、重复播放点击合并且开播等待清理。HTTP 测试验证取消时立即关闭客户端并等待异步响应流清理；真实 loopback 覆盖等待响应头时取消和首包即终止，不代表所有真实源／操作系统清理耗时都有严格上限。
- 首次自动检测覆盖空／隐藏／停用／无线路列表延后、等待订阅检查成功或失败、检查期间手动检测、尚未启动时离页不发请求。检查新生成的 `build/live-tv-review/probe-320-false.png` 与 `probe-1280-true.png`，台名／耗时／收藏无重叠；截图为合成结果，既有收藏筛选文本受测试字体缺字影响。没有真实源吞吐、播放器解码或 TV 遥控器验收，不是 APK 交付。

### 2026-09-20 直播首页连通检测

- 以下为首次自动检测前的历史快照：首页仅手动启动的旧预期已被后续实现取代，此批结果不作为自动触发的验证证据。
- 使用 `.fvmrc` 固定的 Flutter 3.38.10／Dart 3.10.9，以下 6 文件共 **62 项主机测试通过**，其中新增检测服务 14 项、队列 3 项、首页交互 14 项；与既有页面／节目／导航批次重叠，不累加为全仓通过数。

```sh
.fvm/flutter_sdk/bin/flutter test --no-pub --concurrency=1 --reporter expanded --dart-define=LIVE_TV_REVIEW=true test/live_channel_probe_test.dart test/live_channel_probe_controller_test.dart test/live_channel_probe_page_test.dart test/live_tv_page_test.dart test/live_current_programme_test.dart test/live_navigation_resume_test.dart
.fvm/flutter_sdk/bin/dart analyze lib/features/live_tv/data/live_channel_probe.dart lib/features/live_tv/application/live_channel_probe_controller.dart lib/features/live_tv/presentation/live_probe_label.dart lib/features/live_tv/presentation/live_tv_page.dart test/live_channel_probe_test.dart test/live_channel_probe_controller_test.dart test/live_channel_probe_page_test.dart
```

- 服务覆盖真实本机 HTTP 首包返回后主动结束、等待响应头时取消，以及模拟 HTTP 错误、空响应、非媒体类型、头部／正文超时、迟到响应清理、跳转上限／降级拒绝与跨源凭据剥离。队列覆盖只测首选线路、最多两路并发、无自动开始、停止后丢弃迟到结果和地址／headers／线路变化失效。
- 首页覆盖 320／390／1280 宽度、TV／非 TV，检查台名和数值同一行、手动开始／停止、筛选和快照变化取消、后台／路由／销毁取消、不自动重启、进入播放器前等待取消完成及重复点击合并。定向分析无问题；检查 `build/live-tv-review/probe-320-false.png` 和 `probe-1280-true.png`，结果紧邻台名，标题／结果／收藏操作无重叠。截图使用合成检测结果，部分既有筛选文字仍受测试字体缺字影响，不作为完整字体兼容验收。
- 本次仅验证主机 HTTP、组件布局及 fake engine／mock 通道交互，不验证实际直播源、解码可播率、真实 TV 网络／遥控器或吞吐量。首包毫秒值不是持续速度，HLS 入口响应不证明分片、密钥和编码可用；未执行发布预设、构建 APK 或递增版本。

### 2026-09-20 播放器选台移除台标

- 检测到工作区依赖来自 Flutter 3.41.6；确认没有本仓库并行 Flutter 构建后，使用 `.fvm/flutter_sdk/bin/flutter pub get` 按 `.fvmrc` 恢复 Flutter 3.38.10／Dart 3.10.9 的依赖解析，锁文件由该 SDK 自动更新，未手工修改 package config 或执行 clean。
- `.fvm/flutter_sdk/bin/flutter test --no-pub --concurrency=1 --reporter expanded --dart-define=LIVE_TV_REVIEW=true test/live_channel_picker_test.dart test/live_tv_page_test.dart test/live_current_programme_test.dart test/live_logo_test.dart`：4 文件共 35 项通过。320／390／560 宽度下，原始或自定义台标 URL 均不触发 provider；100 频道列表经过滚动、切换分组、选台及重新打开后请求计数仍为零，组件树无 `LiveLogo`／`Image`。
- 保留本地电视图标与行尾播放标记，当前节目文字、两倍字号固定行高、焦点、分层返回以及频道首页台标解码回归通过。`.fvm/flutter_sdk/bin/dart analyze lib/features/live_tv/presentation/live_channel_picker.dart test/live_channel_picker_test.dart test/live_tv_page_test.dart` 无问题，改动文件 `git diff --check` 通过。
- 人工检查 `build/live-tv-review/channels-390.png` 与 `channels-1280.png`，无台标区域空槽，频道／当前节目与播放标记无重叠。以上为主机 widget／provider 计数与 fake engine 截图，不是实际媒体带宽、首帧或流畅度测量；不承诺播放器之外的频道首页也停止台标请求。本任务未做真机验收、未构建 APK 或调整版本。

### 2026-09-20 选台当前节目

使用 `.fvm/flutter_sdk` 固定 Flutter 3.38.10，以下 5 文件共 **58 项主机测试通过**，定向静态分析无问题：

```sh
.fvm/flutter_sdk/bin/flutter test --no-pub --dart-define=LIVE_TV_REVIEW=true --reporter expanded test/live_current_programme_test.dart test/live_channel_picker_test.dart test/live_tv_page_test.dart test/live_navigation_resume_test.dart test/live_playback_lifecycle_test.dart
.fvm/flutter_sdk/bin/dart analyze lib/features/live_tv/presentation/live_widgets.dart lib/features/live_tv/presentation/live_tv_page.dart lib/features/live_tv/presentation/live_channel_picker.dart lib/features/live_tv/presentation/live_player_page.dart test/live_current_programme_test.dart test/live_tv_page_test.dart
```

新增 5 项验证来源 + 覆盖后的 EPG ID 匹配、同名 ID 来源隔离、过去／未来节目不能显示为正在播出、缺失占位、异步读取、分钟刷新、首页活动恢复、列表重开及前后台切换。保留页面持有旧查询时，播放器重开列表仍刷新；读库失败保留仍有效的缓存，后续分钟恢复。刷新不换台、不逐行查询完整节目、不抢焦点，关闭列表或后台不继续分钟批量查询。320／390／560px、两倍系统字号下检查 64dp 行高、文字无重叠及列表位置稳定。

`build/live-tv-review/channels-390.png`、`channels-1280.png` 及 `library-320.png` 已检查当前节目文本与布局；首页截图既有部分按钮文字使用测试默认字体显示缺字，不作为完整字体验收。截图使用合成 EPG 和 fake engine 黑色画布，未请求实际订阅或执行真实解码，不代表真机遥控器／节目准确度验收。未运行发布预设、未改版本或交付 APK；本集合与其他批次重叠，不累加。

### 2026-09-20 TV 直播隐藏顶部设置按钮

- 固定 Flutter 3.38.10，`.fvm/flutter_sdk/bin/flutter test --no-pub --concurrency=1 --reporter expanded --dart-define=LIVE_TV_REVIEW=true test/live_tv_page_test.dart test/live_channel_picker_test.dart`：2 文件共 21 项通过。覆盖 TV／非 TV、320／1280 宽度，断言 TV 无设置按钮且网速对齐右侧 12dp 内边距，非 TV 保留右侧按钮；关闭菜单后按钮可见性不变。
- TV 通过遥控器菜单键、非 TV 通过点击设置按钮打开播放设置，选台／节目单、焦点与分层返回回归通过；菜单关闭不停止或重开播放。原有台标、长列表与跨列导航测试一并通过。
- `.fvm/flutter_sdk/bin/dart analyze lib/features/live_tv/presentation/live_player_page.dart test/live_tv_page_test.dart`：无问题。人工检查 `build/live-tv-review/player-1280.png`，TV 顶栏右侧无设置按钮及空槽，内核与网速靠右排列，无重叠。
- 此处为主机 widget 与 fake engine 截图，未做真机遥控器或原生播放验收，未构建 APK 或调整版本。

### 2026-09-20 TV 直播隐藏顶部返回按钮

- 固定 Flutter 3.38.10，`.fvm/flutter_sdk/bin/flutter test --no-pub --concurrency=1 --reporter expanded --dart-define=LIVE_TV_REVIEW=true test/live_tv_page_test.dart test/live_navigation_resume_test.dart`：2 文件共 26 项通过。覆盖 TV／非 TV、320／1280 宽度，断言 TV 无“退出直播”按钮且标题从 12dp 内边距开始，非 TV 保留按钮；关闭菜单恢复顶栏后规则不变。
- TV 遥控器完整返回按压周期仍可退出，非 TV 分别验证点击返回按钮和系统返回；菜单先关闭、不停止或重开播放的既有回归及菜单栏历史恢复一并通过。
- `.fvm/flutter_sdk/bin/dart analyze lib/features/live_tv/presentation/live_player_page.dart test/live_tv_page_test.dart`：无问题。人工检查 `build/live-tv-review/player-1280.png`，TV 顶栏无返回按钮或空槽，频道信息与右侧设置／网速无重叠。
- 主机 widget／mock 通道测试与 fake engine 截图，不是实际遥控器或原生播放验收；未构建 APK、未调整版本。

### 2026-09-20 直播菜单透明度与选台台标

以下是移除播放器选台台标及调整背景不透明度前的历史快照；其中加载台标的旧预期已被“不请求／不解码台标”的新回归取代，背景现为顶栏 20%／菜单 70% 不透明，下述旧数值不作为现行行为。

- 固定 Flutter 3.38.10／Dart 3.10.9，执行 `.fvm/flutter_sdk/bin/flutter test --no-pub --concurrency=1 --reporter expanded --dart-define=LIVE_TV_REVIEW=true test/live_logo_test.dart test/live_channel_picker_test.dart test/live_tv_page_test.dart`：3 文件共 30 项通过。
- 新增 3 项覆盖 320／390／560 宽度的选台台标：自定义 URL 优先、真实 PNG 等比解码为 192×48、64×40 占位、无图回退、行尾播放标记、文字边界及点击台标选台。原有 100 频道定位、分组、方向焦点与返回测试一并通过。
- 播放器回归在手机／TV、320／1280 宽度断言顶部背景 alpha 0.3（70% 透明）、设置／频道／节目单 alpha 0.5（50% 透明），设置内部不另绘不透明 Material，不使用整个菜单的 Opacity 淡化文字；保留局部返回后播放不停止、不重开。
- `.fvm/flutter_sdk/bin/dart analyze lib/features/live_tv/presentation/live_logo.dart lib/features/live_tv/presentation/live_tv_page.dart lib/features/live_tv/presentation/live_channel_picker.dart lib/features/live_tv/presentation/live_player_page.dart test/live_logo_test.dart test/live_channel_picker_test.dart test/live_tv_page_test.dart`：无问题，改动文件 `git diff --check` 通过。
- 人工检查 `build/live-tv-review/player-{390,1280}.png`、`channels-{390,1280}.png` 及 `settings-390.png`，确认布局／占位／当前标记无重叠。截图使用 fake engine 黑底与无台标频道，不能作为实际视频透出效果或真实台标网络的验收；PNG 解码由独立测试覆盖。本任务未做真机验证、未构建 APK 或调整版本。

### 2026-09-20 直播台标比例

- 后续占位加宽至 64×40 逻辑像素、解码上限同步为 192×120 后，再次执行下述两文件命令，22 项全部通过（与初次集合重叠，不累加）。横向 480×120 原图解码为 192×48；页面新增断言覆盖 320／390／1280 宽度下固定台标尺寸、12 逻辑像素文字间距及文字不侵入收藏按钮。对 `live_tv_page.dart`、`live_logo_test.dart` 和 `live_tv_page_test.dart` 的定向分析无问题，未做真机验收或发布构建。
- 工具链与现有依赖均为 `.fvmrc` 固定的 Flutter 3.38.10／Dart 3.10.9；未切换 SDK，使用 `--no-pub`，未执行 clean 或发布预设。
- 修复前 `test/live_logo_test.dart` 9 项中三项复现变形：480×120 被解码为 144×120、240×240 被解码为 144×120、120×480 被解码为 120×120。原因是同时指定 `Image.memory` 的缓存宽高默认采用 exact，而非保比例缩放。
- 初次比例修复快照（加宽前）：改用 `ResizeImagePolicy.fit` 后，`.fvm/flutter_sdk/bin/flutter test --no-pub --concurrency=1 --reporter expanded test/live_logo_test.dart test/live_tv_page_test.dart`：2 文件共 22 项通过。新增 9 项使用主机生成的 PNG 实际解码，检查横向／方形／竖向比例、144×120 解码上限、小图不放大、错误占位，以及加载前后固定 48×40 逻辑像素尺寸；页面回归另覆盖 320／390／1280 宽度与遥控交互。
- `.fvm/flutter_sdk/bin/dart analyze lib/features/live_tv/presentation/live_tv_page.dart test/live_logo_test.dart`：无问题。仅修改台标解码策略，网络、图片请求池与列表尺寸不变。
- 此处为主机 widget／PNG 解码验证，不代表真实台标网络、设备截图或 TV 验收；本任务未构建 APK、未调整版本。

### 2026-09-20 直播菜单仅 TV 自动播放

- 工具链：`.fvmrc` 固定 Flutter 3.38.10，先执行 `.fvm/flutter_sdk/bin/flutter pub get`，测试与分析均使用同一 SDK。
- `.fvm/flutter_sdk/bin/flutter test test/live_navigation_resume_test.dart test/app_navigation_shell_tv_focus_test.dart`：2 文件共 36 项通过。覆盖 TV 菜单恢复历史、返回不重开、重复点击、无有效历史及异步取消；非 TV 首次点击、重复点击和切回直播均仅进入频道列表，不读取自动播放历史、不推入播放器。
- `.fvm/flutter_sdk/bin/dart analyze lib/app/router/app_navigation_shell.dart test/live_navigation_resume_test.dart`：无问题。
- 菜单测试检查实际播放器路由参数后立即退出，不启动原生解码；这是主机导航与焦点回归，不是设备播放性能或遥控器验收。本次未构建 APK、未调整版本。

### 2026-09-20 直播媒体兼容参数与真实源抽测

- MPV 增加 `Starflow` 默认 User-Agent（订阅显式值优先），配置 HTTP/HTTPS 网络协议白名单，HLS 分片额外重试一次、关闭持久连接复用；不修改 Exo 的既有默认标识或凭据隔离，不改变频道级恢复预算。三项新增测试覆盖默认值、大小写及空值覆盖、FFmpeg 6 参数/协议边界。
- 本机 curl 对 YanG 同一 CCTV 1 媒体地址的对照：`Starflow / Mozilla/5.0 / mpv/0.40.0` 返回 200，`Lavf/61.7.100` 返回 403。外部新版 FFmpeg 拒绝图片后缀的 HLS 分片，但应用 Android 打包二进制为 FFmpeg 6，核对 n6.0 HLS 实现后确认 HTTP 分片不受该后缀限制；不能把新版探针拒绝推断为应用根因，也不加入新版独有选项。
- 使用 media_kit macOS 插件缓存随附 libmpv（报告 FFmpeg 6.0），以原生 API、null 音视频输出进行有界真实源抽测：新参数下 CCTV 1 为 1920×1080 H.264，约 8s 内推进 4.04s；翡翠台为 3840×2160 HEVC，约 29s 内推进 4.016s；咪视界为 3840×2160 HEVC，30s 内只推进 1.524s，未达目标。默认参数 CCTV 1 对照也有进度（15s、1280×720），且时间戳有跳跃，不能用此样本宣称提速或根因修复。网络/源内容动态变化、软件解码及并发主机构建负载均可能影响结果；不是屏幕首帧、Android 真机或持续流畅性证明。
- 对应配置的 Flutter 3.38.10 执行 `flutter test --no-pub --concurrency=1 --reporter expanded test/live_mpv_options_test.dart test/live_playback_lifecycle_test.dart test/live_exo_bridge_test.dart test/live_review_regression_test.dart` **46 项通过**。改动文件定向 `dart analyze` 无问题，`git diff --check` 通过。初次默认 SDK 与工作区依赖 SDK 不匹配导致 Flutter 框架编译失败，已终止该批次并改用匹配 SDK 重跑，不修改依赖来规避。
- 本任务未使用浏览器、未执行发布预设，未验证电视安装包。原始媒体 URL/分片凭据不写入仓库或公开记录。源端空响应、卡顿或失效仍不能靠客户端保证消除。

### 2026-09-20 直播频道列表定位与分栏

- 后续 TV 页头精简复测：下述两文件 18 项再次通过，新增断言验证 TV 频道列表无关闭按钮／标题行、两列首项向上不丢焦点、返回恢复画布及非 TV 保留关闭按钮；定向静态检查无问题。重新查看 1280px 截图，两列从面板顶部开始，右上角网速无重叠。此结果不额外累加测试数量，未做真机验证。
- `flutter test --dart-define=LIVE_TV_REVIEW=true test/live_tv_page_test.dart test/live_channel_picker_test.dart`：2 文件共 18 项通过。新增选择器 5 项覆盖当前频道在长列表中的滚动与首焦点、320/390/560px 分栏、跨列返回、连续上下导航、重新打开、浏览不换台、长分组列表、缺失与空频道回退以及触摸选择。
- `dart analyze lib/features/live_tv/presentation/live_channel_picker.dart lib/features/live_tv/presentation/live_player_page.dart test/live_channel_picker_test.dart test/live_tv_page_test.dart`：无问题。独立重跑选择器 5 项通过，与上述集合重叠、不累加。
- 人工查看 `build/live-tv-review/channels-390.png` 与 `channels-1280.png`，分组在左、频道在右，正在播放项保持强调色及白色 TV 焦点框，网速与面板内容未重叠。
- 此处为主机 widget/fake engine 验证，不是实际媒体解码、TV 遥控器或设备性能测量；未构建发布 APK，未修改版本。

### 2026-09-20 直播播放故障诊断

- 用户 16:06 导出日志含 16:03:20 / 16:04:02 的订阅刷新成功及其他刷新失败，无 `live.playback` 成功或具体失败事件。不能据此判断媒体流失效或播放器界面故障；本次补充播放页请求、打开尝试、固定失败类别与重试决策记录，不视为用户故障已经修复。
- `flutter test --no-pub --concurrency=1 --reporter expanded test/live_playback_lifecycle_test.dart test/live_tv_page_test.dart test/live_review_regression_test.dart` **48 项通过**，包含打开超时/进度超时/内核错误类别及手动重试清空旧故障断言；三处改动的生产文件及生命周期测试定向 `dart analyze` 无问题。
- 未做浏览器测试、真实媒体解码、真机验证或发布构建。尚需设备、所选内核与失败界面信息，订阅下载成功不等于其中每条媒体线路可播放。

### 2026-09-20 直播右上角网速

- `flutter test test/live_network_speed_label_test.dart test/live_exo_bridge_test.dart test/live_tv_page_test.dart test/live_playback_lifecycle_test.dart`：41 项主机测试通过。覆盖网速刷新／零值／异常、换台迟到采样、隐藏后停止轮询、加载时保留标签、控制栏自动隐藏和生命周期回归；指定实现与测试文件 `dart analyze` 无问题。
- Android 在 `android/` 执行 `./gradlew :app:testDebugUnitTest -x :app:compileFlutterBuildDebug -Pandroid-skip-build-dependency-validation=true --tests '*LiveTvNetworkSpeedTest' --tests '*LiveTvViewTest' --console=plain`：6 项 JVM 测试通过，无失败／跳过；覆盖字节累计、空闲归零、每秒任务采样、换台隔离、后台与释放。Kotlin 实际编译，跳过 Flutter 打包，不作为 APK 或真实下载证据。
- `LIVE_TV_REVIEW=true` 截图检查了 390/1280 播放器控制栏、缓冲及频道／节目单叠层，网速未与标题和操作重叠。该截图模式整组运行未全绿：订阅编辑 320px 测试未找到 `SwitchListTile`；普通模式最终 41 项通过，不将截图模式宣称为整组通过。
- 以上为 Flutter fake engine／mock 通道和主机布局，不是实际媒体下载速率、解码或真机测量；未构建 APK、未递增版本。

### 2026-09-20 TV 直播备份扫码

- 直播备份与恢复的 TV 入口改为手机扫码下载/上传，复用共享二维码与会话清理；非 TV 本地文件流程保留。上传限制 32 MiB，校验版本后仍需电视确认合并/替换；普通应用配置 JSON 不可恢复直播库。
- 指定七文件 **79 项通过**：`live_backup_transfer_page_test.dart`、`live_backup_page_test.dart`、`live_playlist_transfer_service_test.dart`、`live_playlist_transfer_page_test.dart`、`live_review_regression_test.dart`、`live_tv_data_test.dart`、`features/settings/presentation/lan_transfer_qr_address_card_test.dart`。包括实际本机 HTTP 的鉴权、端点隔离、备份字节一致性、单次下载、无效文件及声明/累计大小限制；组件测试覆盖合并/替换确认、取消和后台丢弃，真实仓库回归覆盖原子恢复。
- 随后增加 320/1280 宽度用例，组合执行发现恢复方式下拉框在 320 宽度溢出；修复为按可用宽度展开后，备份扫码组件文件 **5 项独立复测通过**，与前述集合重叠，不累加。最初新测试有括号语法错误，修复后才计上述通过结果。
- 最终 `dart analyze lib/features/live_tv test/live_backup_transfer_page_test.dart test/live_backup_page_test.dart test/live_playlist_transfer_service_test.dart test/live_playlist_transfer_page_test.dart` 无问题。未使用浏览器，未做手机到电视跨设备、真实遥控器或下载文件管理验收；未构建发布 APK或递增版本。

### 2026-09-20 APTV 频道表误判修复

- 用户报告“没有频道”，提供的日志在 15:40:59、15:41:12 仅记录订阅刷新失败，无具体阶段。对用户提供的频道目录执行一次主机 HTTP 下载，返回 200、111207 字节；旧解析器遇到 APTV 的两个 `#EXT-X-APTV-*` 扩展便将整个频道表误判为 HLS 媒体清单，已用下载快照复现。
- 改为识别实际 HLS 标签；客户端扩展注释不再触发误拒绝。修复后同一快照解析为 418 个频道、430 条线路、8 个分组，并发现 EPG 地址。真实目录未作为测试 fixture 入库，不记录其中的线路 token；未访问媒体流或验证节目单下载，也不代表 TV 网络或播放成功。
- 指定四文件 **65 项通过**：`live_tv_test.dart`、`live_tv_data_test.dart`、`live_playlist_transfer_service_test.dart`、`live_review_regression_test.dart`。新增三项覆盖 APTV 解析、混合真实 HLS 标签仍拒绝，以及网络刷新/本地导入后频道可见。定向 `dart analyze` 无问题；未使用浏览器、未构建发布 APK。

### 2026-09-20 手机输入收键盘

- 应用入口为 Android / iOS 非 TV 接入输入框外点击取消焦点；不接管提交、下一项、多行换行或 TV 返回规则。
- `flutter test --no-pub test/core/widgets/mobile_text_input_dismissal_test.dart test/features/settings/presentation/settings_text_input_field_test.dart test/features/search/presentation/search_page_focus_test.dart test/core/widgets/tv_dialog_back_focus_test.dart` **45 项通过**，包含新增 Android / iOS 两种平台下共 16 项输入组件测试：空白触摸、保留文本、完成／搜索提交、输入框切换、多行换行、按钮操作、弹窗和 TV 行为隔离。新增测试首轮因焦点刷新时序及平台覆盖清理失败，改用平台测试 variant 并刷新焦点后重跑通过。
- `flutter analyze --no-pub lib/core/widgets/mobile_text_input_dismissal.dart lib/app/app.dart test/core/widgets/mobile_text_input_dismissal_test.dart` 无问题。这是主机模拟键盘／焦点验证，不是 Android / iOS 真实输入法验收；未构建安装包、递增版本或执行全量测试。

### 2026-09-20 直播强调色统一

- 收藏星标、静音开启态、当前频道／节目和直播下拉选中项接入 `AppActionColors`；列表淡底约 9% 不透明度，白色焦点框与中性普通状态不变。不修改播放、重连、音轨或存储接口。
- `flutter test --no-pub test/live_tv_page_test.dart test/live_backup_page_test.dart test/live_playlist_transfer_page_test.dart test/live_accent_test.dart test/app_theme_test.dart` **37 项通过**。八色、手机／TV 的选中／未选中／禁用色及固定尺寸分别验证，播放页在共享清理队列的同一测试中循环验证八色双模式、静音、两条线路切换、频道与节目选中态；另覆盖 320/390/1280 布局、收藏、备份和扫码导入。定向 `flutter analyze --no-pub lib/features/live_tv/presentation test/live_tv_page_test.dart test/live_accent_test.dart test/live_backup_page_test.dart` 无问题。
- `flutter test --no-pub --dart-define=LIVE_TV_REVIEW=true test/live_tv_page_test.dart` **7 项通过**，与上述集合重叠、不累加。组件截图位于 `build/live-tv-review/`，抽查 1280 频道叠层、320 频道页与 390 播放页：强调色状态与白色焦点独立，线路换行无重叠。部分旧按钮标签受测试字体缺字影响，截图不作为完整字体或真机视觉验收；假引擎的黑色画布不是视频解码证据。
- 初次运行因测试波纹着色器资源格式不兼容失败，相关测试主题改用 `NoSplash` 后重跑通过；应用主题不变。另一次命令误引用不存在的导入测试文件，已以实际 `live_playlist_transfer_page_test.dart` 重跑，失败运行不计通过。没有发布 APK、递增版本或执行真实直播源／设备测量。

### 2026-09-20 选集强调色接入

- MPV 选集列表／网格从主题 `AppActionColors` 取色；Android 原生选集接收 Flutter 启动参数 `episodeAccentColor`，播放文字、图标、当前集淡底和进度线共用该颜色。白色焦点框与已看完的中性标记不变。
- `flutter test --no-pub test/player_episode_picker_dialog_test.dart test/app_theme_test.dart test/player_menu_style_test.dart` **66 项通过**，覆盖八种强调色、手机／TV、列表／网格状态配色及既有选集交互。上述选集组件、原生启动器及选集测试的定向 `flutter analyze --no-pub` 无问题。
- Android 在 `android/` 执行 `./gradlew :app:testDebugUnitTest -x :app:compileFlutterBuildDebug -Pandroid-skip-build-dependency-validation=true --tests '*NativePlaybackSettingsAppearanceTest' --tests '*NativeEpisodePickerNavigationTest' --console=plain`，debug Kotlin 编译及 **11 项 JVM 测试通过，0 失败／错误／跳过**。颜色传递与原生控件取色使用源码契约断言，导航使用索引策略测试，不运行真实 Android View。
- 本轮仅为定向主机回归，不是全量测试、Android 6／TV 真机视觉或设备性能验收；未构建发布 APK、递增版本或修改播放解析策略。

### 2026-09-20 十项审查收尾

代码改动、定向回归和发布核验统一记录在 [十项审查收尾](reviews/review-closure-2026-09-20.md)。该记录区分合成网络/存储故障、Flutter 组件、Android JVM、Swift 主机策略与完整 APK 静态检查；不把任一主机通过结果计为 Android 6、TV 遥控器、NAS 转码或 AVPlayer 真机验收。以下同日早期批次保留为各自执行时快照，不自动覆盖收尾后的代码。

### 2026-09-20 选集到选季焦点回归

- TV 选集首集／网格首行上移优先进入可用选季入口；选季上移到模式按钮，两个模式按钮下移经过选季，选季下移返回原剧集。单季跳过禁用入口，原有跨段和底部定位导航不变。
- 主机指定 3 文件 **52 项通过**，包含新增列表／网格四列的选季往返、取消选季弹窗后的恢复，以及单季跳过测试；同时覆盖原有首帧定位、跨段导航、加载结果失效、手机布局和播放器小弹窗。不与此前 50 项重复累计。
- 选集组件及测试的定向 `flutter analyze --no-pub` 无问题。本轮首次运行曾被工作区缓存代码的类型错误阻断，另一处更新后重跑通过；中断的重复运行不作为通过证据。
- Android 已同步修改选集 View 的方向处理并补充首行边界 JVM 用例；停止前已完成 debug Kotlin 编译和 `NativeEpisodePickerNavigationTest` 5 项测试（0 失败／错误／跳过），仅验证索引策略，不运行原生 View。随后按用户要求终止 Gradle，release Kotlin 编译未完成，不记为通过。
- 以上为模拟按键与组件焦点验证，不是物理遥控器、Android 原生 View 或设备性能验收。没有发布 APK、递增版本或修改播放解析链路。

```sh
flutter test --no-pub --concurrency=1 test/player_episode_picker_dialog_test.dart test/player_small_dialog_focus_test.dart test/player_tv_playback_widgets_test.dart
flutter analyze --no-pub lib/features/playback/presentation/widgets/player_episode_picker_dialog.dart test/player_episode_picker_dialog_test.dart
```

### 2026-09-20 TV 直播扫码导入

- TV 文件入口改为手机扫码，复用配置/日志传输的二维码组件。文件接收后只进入编辑草稿，仍需电视确认保存；非 TV 保留本地文件选择。
- 主机指定 9 文件 **87 项通过**，其中新增接收服务 8 项、界面 7 项；其余包含原有直播解析/仓库/生命周期/页面/Exo 通道及共享二维码、日志导出回归。与下方历史 132 项有重叠，不累加，不代表全仓测试。
- 接收服务使用本机真实 HTTP 测试，覆盖令牌/Host/Origin、原始 GBK 字节、无效文件重试、声明/分块超限、30s 期限策略、单次/并发接收、取消和会话过期。界面使用 fake session/repository，覆盖 320/1280 宽度、草稿确认、返回/后台清理、迟到启动与失败；真实仓库由原有数据测试覆盖。
- 定向 `dart analyze` 无问题，`git diff --check` 通过。早期界面夹具因 FakeAsync 与实际存储/isolate 等待中止，已分离为界面和数据测试；以最终 87 项为本轮结果。
- 按用户要求停止浏览器测试。此前仅打开页面、选择文件并检查了 390 宽度布局，上传提交前测试服务过期，未完成成功上传验收；临时浏览器验证入口已移除。手机到电视的跨设备扫码、真实遥控器与 API23 设备仍未测，没有发布 APK 或递增版本。

```sh
flutter test --no-pub --concurrency=1 --reporter expanded test/live_playlist_transfer_service_test.dart test/live_playlist_transfer_page_test.dart test/live_tv_test.dart test/live_tv_data_test.dart test/live_playback_lifecycle_test.dart test/live_tv_page_test.dart test/live_exo_bridge_test.dart test/features/settings/presentation/lan_transfer_qr_address_card_test.dart test/features/settings/presentation/log_export_page_test.dart
dart analyze lib/features/live_tv test/live_playlist_transfer_service_test.dart test/live_playlist_transfer_page_test.dart
```

### 2026-09-20 直播前置验证快照

以下保留前置快照，并补充五任务合并后的主任务验证。所有结果只覆盖列出的主机测试，不代表全仓全绿或设备解码验收。

| 批次／检查 | 已确认结果 | 证据边界 |
| --- | --- | --- |
| 五任务开始前直播及集成集合 | 指定 7 文件、79 项通过 | 执行早于五任务后续修改，不代表当前 live 全套或全仓全绿 |
| Android `:app:compileDebugKotlin` | 2026-09-20 成功 | 仅该次 Kotlin 编译；不是 APK 发布、ARM 解码、原生视图运行或后续修改复编译通过 |
| 后续导航集成补充 | 3 文件、48 项通过 | 新增旧菜单不强制插入直播及旧分支索引不移动用例；与前置集合重叠，不与 79 相加，也不是最终全量 |
| 后续播放任务专项 | 新增生命周期 19 项、当前 Exo 通道 6 项通过 | 主任务转述的该次专项结果，不并入 79/48，不代表最终 live 全套或真实原生视图运行 |
| 后续数据任务专项 | `test/live_tv_test.dart`、`test/live_tv_data_test.dart` 共 38 项通过 | 主任务确认的数据收尾结果，与前置/其他专项可能重叠，不相加为最终总数 |
| `adb devices` | 无已连接设备 | 真实源和真机均未测，没有双内核首帧、换台或长播结果 |
| 合并后直播及导航/设置集成集合 | 9 文件、132 项通过，0 失败 | 包含生命周期 19、页面 7、Exo 通道 6、数据/控制器 38 和导航/设置 62；合成数据与 fake engine/mock 通道，不播放真实媒体 |
| 核心独立复测 | 生命周期、页面、Exo 通道 3 文件、32 项通过 | 与 132 项重叠，不累加；上轮组合执行曾 131 通过/1 失败，后续完整及核心复测未复现，未将其推断为已定位修复 |
| 合并后 Android 检查 | Gradle 编译及直播 JVM 目标成功；17 项、0 失败/错误/跳过 | LiveTvPolicyTest 11、LiveTvHttpTransportTest 6；收尾 Gradle 检查命中 UP-TO-DATE，报告为该源码的专项结果，不称为重新执行全部 Android 测试 |
| 定向静态分析及布局 | `dart analyze` 无问题；320/390/1280 宽度组件布局和截图已检查 | 14 张截图位于 `build/live-tv-review/`，播放背景来自 fake engine；不作为 TextureView、解码或真实台标网络证据 |

前置 7 文件范围，均相对仓库根目录：

- `test/live_tv_test.dart`
- `test/live_tv_page_test.dart`
- `test/live_exo_bridge_test.dart`
- `test/app_navigation_shell_tv_focus_test.dart`
- `test/app/router/app_routes_test.dart`
- `test/app_settings_test.dart`
- `test/features/settings/presentation/settings_hierarchy_navigation_test.dart`

后续 48 项仅为 `test/app_settings_test.dart`、`test/app/router/app_routes_test.dart`、`test/app_navigation_shell_tv_focus_test.dart`。这些是两次执行快照，不相加、不冒称互不重叠；本页其他点播 Flutter/JVM/Swift 批次也不自动覆盖直播模块。

主任务合并后已执行的完整集合及复测命令：

```sh
flutter test --no-pub --concurrency=1 --reporter expanded test/live_tv_test.dart test/live_tv_data_test.dart test/live_playback_lifecycle_test.dart test/live_tv_page_test.dart test/live_exo_bridge_test.dart test/app_navigation_shell_tv_focus_test.dart test/app/router/app_routes_test.dart test/app_settings_test.dart test/features/settings/presentation/settings_hierarchy_navigation_test.dart
flutter test --no-pub --concurrency=1 --reporter expanded test/live_playback_lifecycle_test.dart test/live_tv_page_test.dart test/live_exo_bridge_test.dart
dart analyze lib/features/live_tv lib/app/router/app_routes.dart lib/app/router/app_router.dart lib/app/router/app_navigation_shell.dart lib/features/settings/domain/app_settings.dart lib/features/settings/presentation/settings_page.dart test/live_tv_test.dart test/live_tv_data_test.dart test/live_tv_page_test.dart test/live_playback_lifecycle_test.dart test/live_exo_bridge_test.dart
# 在 android/ 目录执行；成功，Kotlin/JVM 目标为 UP-TO-DATE。
./gradlew :app:compileDebugKotlin :app:testDebugUnitTest --tests 'com.example.starflow.LiveTv*' --console=plain
```

解析/时区/事务缓存/迟到刷新与播放恢复可用合成数据、内存库和 fake engine 测试；布局/遥控器组件测试不执行解码，Exo MethodChannel mock 仅验证参数及事件契约，不创建真实 `LiveTvView`。本机原生编译也不能证明 Media3 标准 renderer 的真实格式支持、音轨切换、TextureView 像素或 TV 焦点。

直播的 `live.playback` started 记录首次 `progress` 或 `frame`，耗时从合并窗口后进入开流队列任务开始，不含最初用户按键到该任务执行的全部等待。MPV position 前进不是像素首帧；Exo 也可能先由 progress 记忆频道，不能把所有 started 记录当 `onRenderedFirstFrame`。直播目前没有接入点播完整的 `playback.performance` 会话摘要、掉帧/带宽/decoder 汇总，跨内核首帧、换台 p50/p95 需外部一致测量，见 [设备对比清单](performance-device.md#直播双内核对比验收2026-09-20)。

本轮未运行发布预设、未递增发布版本或交付 APK；保留既有文档及其他任务改动。真实订阅鉴权/重定向、台标、长播、断流、低内存设备及物理遥控器尚无本轮验收数据。Gradle 仍提示已有弃用特性，不据此宣称 Gradle 9 兼容。

修复前播放任务边界快照：当时 15s 开流等待只计时并触发失败，`LiveEngine` 没有取消接口，旧 open 未 settle 仍阻塞串行清理。后续生产适配器已加入取消确认协议，当前已调整为 5s 开流／无进展等待，行为见 [直播文档](live-tv.md)。这里的 19 项生命周期及 6 项通道测试不作为新取消协议或 5s 强制中止媒体网络的验证证据。

数据任务收尾边界：10000 频道/每频道 64 线路/全表 50000 线路上限；generation 刷新合并和删除/禁用/同 ID 重建后的旧结果失效；EPG 失败保留节目与台标；手动排序后新频道追加；来源日志 ID 哈希、偏好来源归属。38 项是该次合成数据/仓库回归，不是大规模真实订阅、设备内存或网络吞吐测量。

### 2026-09-20 MPV 跳过与切集边界修复

- 本轮五项修复已集成：自动切集请求取消 / 手动优先、全部 Player seek 入口的手动保护、启动期片头越界纠正、真实位置与显式完成标记分离，以及预解析缓存 / 在途请求复用。Android 原生实现未在本轮修改。
- 最终主机 Flutter 选择范围 **217 项通过，0 失败**，命令为 `flutter test --no-pub --concurrency 2 --reporter expanded test/features/playback/application test/player_auto_skip_interactions_test.dart test/playback_memory_repository_test.dart test/player_adaptive_controls_layout_test.dart test/player_startup_cancellation_test.dart test/player_episode_picker_dialog_test.dart test/playback_seek_coalescer_test.dart test/playback_system_session_test.dart test/perf/player_open_smoke_test.dart`。
- 新增策略回归覆盖取消后迟到结果、手动请求取代自动请求、旧 finally、一次前台期限、定时器执行前的截止时间检查、手动失败重试、短集 / 未知时长 / 迟到 seek / 取消、完成状态与实际进度。`player_auto_skip_interactions_test.dart` 使用真实 Android / iOS / Windows Adaptive 控件和假后端，验证进度条命令在后端事件前撤销自动意图并清除完成标记；该测试不是设备解码或触屏实测。
- 定向 `dart analyze` 检查新增五个模块、仓库、播放页与修改的 part 文件及相关测试，无问题；`git diff --check` 通过。早期新测试夹具的控件显隐 / 鼠标悬停问题和缓存空值编译问题已修正，最终结果以上述 217 项为准。
- 没有运行发布预设、递增版本或交付 APK，没有新增真机性能数据。需按 `performance-device.md` 的跳过边界与短集场景验证实际出帧、网络解析请求量和远程播放时序；不要把本轮主机耗时解释为播放性能收益。

### 2026-09-20 播放器流畅度修复

对应 [播放器审查处理状态](reviews/player-smoothness-review-2026-09-20.md)。以下均为主机执行结果，不是 TV/iPhone 掉帧或首帧测量；没有运行发布预设、改变版本或交付 APK。

- Flutter 播放应用层、取消、字幕绑定、历史、外部播放列表及新增 seek 集合 **91 项通过**。补充轨道守卫、seek、飞牛服务、服务端选轨、字幕管线、启动 scope、生命周期集合 **50 项通过**；其中 seek 的 5 项重叠，不能直接相加。新增测试覆盖 2/5/10 秒长按、定位在途合并、取消及自动字幕迟到/手动选择/失败隔离。守卫测试不等同于真实 decoder 下的完整 UI 选轨验收。
- Android 4 类 JVM **56 项通过，0 失败/错误/跳过**：MemoryStore 15、RuntimeController 9、BufferPolicy 9、RemoteController 23。新并发用例阻塞首个写入，确认调用线程不执行持久化、周期更新合并且强制保存先于后续 tick；现有历史/字幕/跳过偏好及外部原文失效用例保留。验证过程中另有任务执行 Android 构建，计时不作为性能基线。
- `scripts/test_native_playback_storage.swift` 优化编译后通过：延迟队列保留空 URL 元数据、前后集索引、进度队列最终顺序、字幕偏好、裁剪与外部失效。`scripts/test_native_playback_startup.swift` 优化编译后通过：重复 KVO 只有一个 preroll、成功/失败/取消/迟到回调及 VOD/显式直播 HLS 策略；不播放网络媒体。
- iOS 无签名 arm64、部署目标 iOS 13.0 的 Xcode Debug 构建成功；全部 Runner Swift 使用 iPhoneOS SDK 的独立类型检查通过。已有 Pod OpenGLES 弃用、图标未分配资源等构建警告保留；未执行 RunnerTests/XCTest、模拟器 UI 或真机切集/后台联调。
- `dart tool/generate_playback_policy.dart --check` 通过；播放目录及新增测试定向分析无问题，编辑文件空白检查通过。收尾 seek/轨道守卫/启动取消/外部文件四文件复测 **14 项通过**，与前两组重叠，不累加。之前审查的 148 Flutter/80 JVM 是更早快照，不作为本次修复用例计数。

主要命令：

```sh
flutter test --no-pub --concurrency 2 test/playback_seek_coalescer_test.dart test/features/playback/application test/player_startup_cancellation_test.dart test/player_startup_overlay_test.dart test/mpv_subtitle_render_binding_test.dart test/features/playback/data test/playback_memory_repository_test.dart
flutter test --no-pub --concurrency 2 test/playback_seek_coalescer_test.dart test/playback_track_guard_test.dart test/native_fntv_service_test.dart test/playback_server_track_resolver_test.dart test/subtitle_pipeline_regression_test.dart test/mpv_startup_scope_test.dart test/app_runtime_recovery_boundary_test.dart
swiftc -O ios/Runner/NativePlaybackStartupGate.swift ios/Runner/NativePlaybackBufferingTuning.swift scripts/test_native_playback_startup.swift -o /tmp/starflow-startup-check
/tmp/starflow-startup-check
swiftc -O ios/Runner/NativePlaybackModels.swift ios/Runner/NativePlaybackMemoryStore.swift ios/Runner/PlaybackMemoryPolicy.swift ios/Runner/PlaybackPolicyValues.swift scripts/test_native_playback_storage.swift -o /tmp/starflow-storage-check
/tmp/starflow-storage-check
```

Android 在 `android/` 执行 `./gradlew :app:testDebugUnitTest -x :app:compileFlutterBuildDebug -Pandroid-skip-build-dependency-validation=true --console=plain`，用 `--tests` 限定上述四类。Xcode 使用 `-workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`，独立 derived data 位于 `/tmp/starflow-player-build`。这不是发布安装包。

尚无优化后同规模保存耗时或设备改善百分比。同步最新历史查询仍可能等待后台队列。2026-09-20 后续修复把移动端 Flutter 读改写接入原生共享串行队列，以 compare-and-set 拒绝旧快照并重试；历史上仅靠各自队列、存在跨运行时覆盖竞争的描述属于修复前快照。该协议不是跨进程数据库事务；iOS 有限后台时间、Android 后台 commit 均不能承诺强杀瞬间未完成写入持久化。真机验收仍按 performance-device 执行。

### 2026-09-20 音频五项再审修复

- 五个并行子任务的最终实现接入 Session 后，将全部 Android 主 Kotlin 与 JVM 测试源码复制到独立目录，用缓存的 Kotlin 2.2.20 编译器、JVM 17 目标和冻结的 Android/Media3 测试依赖重新编译；JUnit 全量 **418 项通过**。结束后比对当前全部 Kotlin 源码与已验证副本一致。共享 Gradle 构建输出受到其他并行任务影响，因此本次使用隔离编译，不称为完整 Gradle/APK 构建通过。
- 新增覆盖高精度 `getMinBufferSize` 明确拒绝的类型化异常、默认缓冲区策略一致性、原异常和声道能力透传、缺少 renderer Format 的源轨/DRM 防护、倍速临时精度历史、AudioTrack 复用与旧释放、FFmpeg AC-3 排除。集成用例运行真实 Media3 `DefaultAudioSink` 和 provider，注入平台拒绝结果后验证原始 Format 传到单次 PCM16 回退；Android 硬件 API 使用测试替身。
- LPCM 可选样本通过 `STARFLOW_LPCM_PACKETS=/tmp/starflow-lpcm24-packets.bin`、`STARFLOW_LPCM_REFERENCE=/tmp/starflow-lpcm24-reference.bin` 启用，包含 stereo/96 kHz/24-bit 合成样本与 FFmpeg PCM24 逐字节对比。隔离执行脚本为本机临时文件 `/tmp/starflow-audio-reaudit/verify.rb --all`，不是仓库构建入口；无并行构建冲突时可在 `android/` 以相同样本环境变量运行 `./gradlew :app:testDebugUnitTest --offline` 复验。
- `git diff --check` 通过，`adb devices` 仍无已连接设备。本批没有重建 AAR、运行发布预设、修改版本或生成 APK，也未重跑 Flutter 全集。没有新增 ARM decoder、HDMI、真实 AudioTrack、CPU/GC、A/V 同步或 bit-perfect 测量；418 是本次源码快照的 JVM 结果，不覆盖后续并行编辑。

### 2026-09-20 音频输出状态与倍速补强

- 前一批 Android JVM 全量 **368 项通过，0 失败、0 跳过**。在 `android` 目录运行 `STARFLOW_LPCM_PACKETS=/tmp/starflow-lpcm24-packets.bin STARFLOW_LPCM_REFERENCE=/tmp/starflow-lpcm24-reference.bin ./gradlew :app:testDebugUnitTest --offline`，未排除 Flutter 编译或 MPV 依赖任务；这是该批工作区快照，不覆盖上方五项再审修复或后续并行修改。
- 新增覆盖普通 PCM16 原地调速、直通改速及恢复、速度/音调与所有输出模式组合、可读编码标签、失败前捕获 sink Format、压缩输入但 float 输出故障、实际 AudioSink 异常格式优先于缓存、PCM16 不误回退、DRM/视频排除、独立恢复预算和释放后输出状态隔离。仍包含上一批 LPCM 低位保留、Media3 转换器及 stereo/96 kHz/24-bit 合成样本与 FFmpeg PCM24 逐字节对照。
- `git diff --check` 通过。`adb devices` 无已连接设备；没有新增 ARM decoder、HDMI、AudioTrack、CPU/GC、A/V 同步或 bit-perfect 实测。本批未运行 Flutter 测试全集、重建 AAR 或执行 APK 发布预设。

### 2026-09-20 LPCM 保位深与输出策略

- 前一批 Android JVM 全量 **357 项通过，0 失败、0 跳过**。命令为 `STARFLOW_LPCM_PACKETS=/tmp/starflow-lpcm24-packets.bin STARFLOW_LPCM_REFERENCE=/tmp/starflow-lpcm24-reference.bin ./gradlew :app:testDebugUnitTest --offline`（在 android 目录）；没有排除 Flutter 编译或 MPV 依赖任务。这是该批代码快照结果，不覆盖之后的并行修改或上方输出状态补强。
- 前置 71 项音频专项回归包含已有 stereo/48 kHz/16-bit 实样字节对比。全量中的可选 LPCM 对比改用 FFmpeg 生成的 stereo/96 kHz/24-bit 合成 Blu-ray TS，与 FFmpeg PCM24 参考输出逐字节一致；临时媒体未加入仓库。
- 新测试覆盖 20/24-bit 完整低位、同采样率位深变化、192 kHz/7.1 缓冲边界、上游 float 转换器的最低有效位、PCM16 兼容转换、速度/音调策略、倍速恢复状态和 raw PCM 输出单次回退。
- `git diff --check` 通过。未重建 AAR、运行发布预设或修改版本；没有运行本轮 Flutter 测试全集，也没有新真机 AudioTrack、HDMI、CPU/GC 或 bit-perfect 测量。兼容输出复用 Media3 默认整数转换，不将该降位深路径称为无损或带 dither。

### 2026-09-20 冗余代码与条件诊断清理

- 删除 189 处普通静默 trace 调用及四类旧 trace helper、`DebugTraceOnce`；错误路径改用结构化 `appLogError`，本地日志与原生退出捕获不关闭。清理日志专用空分支、参数、尺寸订阅及未使用的 IMDb 预览 API。
- 帧统计仅在记录 info 时收集、排序；warning 独立扫描长帧。MPV 收尾不记录 info 时只读取功能需要的 `cache-speed`，少读 11 项诊断属性，带宽缓存与会话收尾保留。
- IMDb 评分共享下载和后台索引构建，保留 TSV 与行偏移并二分查询；缓存有界，失败可重试，旧请求不得覆盖清空后的新缓存。下载、展开、行数和行长均设上限；这不是零内存开销或真机峰值测量。
- Flutter 运行资源排除两张设计源图与性能视频，保留实际 Logo 和 bootstrap。排除文件原始合计 2,037,702 字节（约 1.94 MiB），不代表 APK 压缩后体积差；移除未使用的 `cupertino_icons` 依赖。
- 主机扩展回归 **256 项通过**，覆盖元数据、详情、字幕、播放解析/启动/应用服务、首页、NAS、日志、IMDb 边界和运行资源清单。此前专项 22 项包含在本次集合内，不重复相加。
- `dart analyze lib test` 无问题，`git diff --check` 通过。验证针对当次工作区快照，不作为其他并行任务后续修改的验收结果。
- 本轮未执行完整测试全集、发布构建或 Android/iOS 真机性能测量；没有新增首帧、内存峰值、CPU 或 APK 体积的实测收益结论。

### 2026-09-20 播放器流畅度审查

范围与待处理问题见 [播放器流畅度审查](reviews/player-smoothness-review-2026-09-20.md)。本轮只读审查播放器实现，新增文档和索引，不修改画质、缓冲、字幕、持久化或版本。以下主机结果不是设备播放验收，也不是同日其他任务后续修改的全绿证明。

- Flutter 播放启动、策略、恢复、生命周期、系统会话、字幕绑定、播放记忆和 smoke 集合 **123 项通过**；补充飞牛、服务端选轨、字幕管线和外部 M3U 集合 **25 项通过**。两组测试文件不重叠，合计 148 项。
- Android `:app:testDebugUnitTest` 选择 8 类 **80 项通过，0 失败/错误/跳过**：BufferPolicy 9、MemoryStore 14、RuntimeController 9、RemoteController 23、Session 7、PerformanceTracker 1、SubtitleOutput 13、DualSubtitleTrackPolicy 4。使用 `-x :app:compileFlutterBuildDebug -Pandroid-skip-build-dependency-validation=true --console=plain`，原生代码和测试实际编译，不是完整 APK 构建。
- `dart analyze lib/features/playback lib/core/platform/playback_system_session.dart` 无问题；`dart tool/generate_playback_policy.dart --check` 通过。`scripts/test_native_playback_storage.swift` 与对应模型/存储/策略优化编译后运行通过；不等于运行 RunnerTests/XCTest 或 AVPlayer 设备播放。
- 临时 Swift 预热探针使用 ready 状态 AVPlayerItem 子类和只计数、不完成回调的 AVPlayer.preroll 覆盖，调用现有 StartupGate，再通过 KVO 发出两次缓冲属性通知：preroll 调用数从 1 变成 3，确认在途阶段缺少防重入。编译仍有 StartupGate 的 MainActor/Sendable 回调隔离警告，未修复或隐藏。
- 临时 Swift HLS 策略探针使用 `https://example.test/vod/movie.m3u8`，不访问网络；默认推断 isLiveStream=true、前向偏好 8 秒，显式 VOD 为 24 秒。仅证明格式推断分支，不证明设备缓冲量或收益。

Swift 历史保存探针环境：Intel Core i5-8257U 1.40GHz、macOS 15.7.9、Swift 6.2.4、`swiftc -O`。用独立临时 UserDefaults suite 写入合成 series JSON，以现有 MemoryStore 预热快照；同一当前集连续保存 8 次，剔除首个样本，统计后 7 次调用的墙钟时间。包含时间戳扫描、JSON 校验/编码和 UserDefaults.set 调用，不等待异步磁盘同步；结束后清理 suite，不读取用户播放记录。

| series 条目数 | 种子 JSON 字节数 | 7 次暖保存耗时 ms | 中位数 ms |
| --- | --- | --- | --- |
| 20 | 7,253 | 12.47, 11.56, 10.66, 10.54, 10.56, 10.42, 10.40 | 10.56 |
| 200 | 72,893 | 88.69, 87.46, 89.41, 89.11, 88.44, 89.42, 92.54 | 89.11 |
| 1000 | 365,693 | 433.52, 433.20, 438.77, 433.30, 471.77, 437.84, 435.04 | 435.04 |

这些是合成规模下的主机同步工作量快照，不是实际库规模、iPhone 帧时、TV 闪存耗时或优化后收益。原文/解析缓存已经存在；当前被测成本不能再描述成每次完整 JSON 冷解码。临时探针不纳入正式回归，实施前需将对应场景变成可持续的测试/基线。

Flutter 主要集合命令：

```sh
flutter test --no-pub --concurrency 2 --reporter expanded test/features/playback/application test/playback_mpv_policy_test.dart test/mpv_tuning_policy_aggressive_downgrade_test.dart test/mpv_stall_watchdog_test.dart test/mpv_network_recovery_policy_test.dart test/mpv_startup_scope_test.dart test/player_startup_cancellation_test.dart test/player_startup_overlay_test.dart test/mpv_subtitle_render_binding_test.dart test/playback_memory_repository_test.dart test/perf/player_open_smoke_test.dart
flutter test --no-pub --concurrency 2 --reporter expanded test/native_fntv_service_test.dart test/playback_server_track_resolver_test.dart test/subtitle_pipeline_regression_test.dart test/features/playback/data/external_playback_playlist_test.dart
```

`adb devices -l` 无设备；未运行发布预设、未生成交付安装包、未重跑全仓测试或 iOS App 链接构建。其他任务正在修改详情、选集及文档，收尾时还出现播放器日志/诊断与飞牛选轨修改；已重新核对相关热点，但上述测试完成于这些新增修改之前，不是最新工作区全绿证明。本轮审查没有改变这些实现。

### 2026-09-20 选集整行定位

- Flutter / MPV 选集自动定位改为按 72dp 行边界停靠；底部补不足一行的滚动余量，避免为展示最后一行而在顶部露出半行空白。手动拖动不强制吸附。
- `flutter test --no-pub --reporter expanded test/player_episode_picker_dialog_test.dart test/player_small_dialog_focus_test.dart`：42 项通过。新增用例先在旧定位算法下复现未对齐，再验证手机横竖屏、TV、列表/网格、首帧位置稳定、分段/模式切换、定位当前集、末集完整显示与触屏自由滑动。
- 两个本轮修改的 Dart 文件定向 `dart analyze` 无问题；目视检查 320dp 手机列表/网格及 1280dp TV 列表组件截图。仅为主机组件回归，不是设备播放或性能验收；未修改 Android 原生定位、未运行发布预设或生成安装包。

### 2026-09-20 移除选集定位按钮

- MPV 与 Android 原生选集移除右上角“定位当前集”按钮及其导航逻辑；保留列表／网格切换，重新打开仍自动定位播放集。网格按钮按下进入可用范围入口，范围按上回网格、按下回原剧集；无范围时网格按下仍经过可用选季入口。底部停留不变。
- `.fvm/flutter_sdk/bin/flutter test --no-pub --concurrency=1 --reporter expanded test/player_episode_picker_dialog_test.dart test/player_small_dialog_focus_test.dart test/core/widgets/tv_dialog_back_focus_test.dart`：**76 项通过**。覆盖按钮不存在、范围键盘入口与返回、重新打开定位、切季加载／重试／关闭后的迟到结果，以及既有末尾停留和跨段导航。两个修改的 Dart 文件定向分析无问题。
- Android 在 `android/` 执行 `./gradlew :app:testDebugUnitTest -x :app:compileFlutterBuildDebug -Pandroid-skip-build-dependency-validation=true --tests '*NativeEpisodePickerNavigationTest' --tests '*NativePlaybackSettingsAppearanceTest' --console=plain`：Kotlin 编译成功，**13 项 JVM 测试通过，0 失败／错误／跳过**。原生 View 接线为源码断言，导航为索引策略，不替代真机遥控器验收。
- 未运行发布预设、未修改版本号或生成交付 APK。下方涉及定位按钮的同日记录为移除前历史快照，不作为当前按钮验收。

### 2026-09-20 选集底部停留

- MPV 与 Android 原生选集在本季末集／网格末行继续按下时保持当前焦点和滚动位置，不再回到顶部定位按钮；跨段和首行向上导航不变。
- 使用 `.fvm/flutter_sdk` 锁定的 Flutter `3.38.10` 执行 `flutter test --no-pub --concurrency=1 --reporter expanded test/player_episode_picker_dialog_test.dart test/player_small_dialog_focus_test.dart test/core/widgets/tv_dialog_back_focus_test.dart`：**76 项通过**。末尾用例覆盖连续按下、单集、30／64／65 集、列表与网格；两个修改的 Dart 文件定向 `dart analyze` 无问题。
- Android 在 `android/` 执行 `./gradlew :app:testDebugUnitTest -x :app:compileFlutterBuildDebug -Pandroid-skip-build-dependency-validation=true --tests '*NativeEpisodePickerNavigationTest' --tests '*NativePlaybackSettingsAppearanceTest' --console=plain`：debug Kotlin 编译成功，**13 项 JVM 测试通过，0 失败／错误／跳过**。导航策略覆盖网格末行每一列及缺列夹紧，View 接线为源码契约断言，不是真机遥控器验证。
- 本次仅为主机定向回归；未运行发布预设、未修改版本号、未生成交付 APK，未作真实设备验收。

### 2026-09-20 选集顶部导航

- 历史快照：本节末尾按下进入顶部定位的行为及对应断言，后续已由“选集底部停留”变更替换，不作为当前底部行为验收。
- MPV 与 Android 原生选集取消底栏，定位移至标题栏，超过 30 集的范围菜单移至第二行；非 TV 左上角返回箭头只关闭面板。本季末尾按下进入顶部定位，按上返回原剧集，确认才定位播放集。
- 使用项目锁定 Flutter `3.38.10` 执行 `flutter test --no-pub --concurrency=1 --reporter expanded test/player_episode_picker_dialog_test.dart test/player_small_dialog_focus_test.dart test/core/widgets/tv_dialog_back_focus_test.dart`：3 文件共 **76 项通过**。覆盖列表／网格末尾焦点往返、单集／整段／缺列边界、范围确认与取消、首帧整行定位、手机横竖屏返回及加载迟到结果。
- 两个修改的 Dart 文件定向 `dart analyze` 无问题；中文字体和 Material 图标的组件截图已检查 320dp 手机列表与 1280dp TV 网格。此前一次拖动测试只有越过触摸阈值的单次移动，改为越过阈值后继续移动再验证自由滚动；未改变触屏滚动实现。
- Android 在 `android/` 执行 `./gradlew :app:testDebugUnitTest -x :app:compileFlutterBuildDebug -Pandroid-skip-build-dependency-validation=true --tests '*NativeEpisodePickerNavigationTest' --tests '*NativePlaybackSettingsAppearanceTest' --console=plain`：2 类 **13 项通过，无失败／跳过**。Kotlin 实际编译；测试覆盖导航索引策略及布局源码契约，不运行真实 Android View／遥控器，也不是 APK 发布验证。
- SDK 故障修复后，终端、编辑器、依赖索引与 Android 配置统一指向长期目录中的 `3.38.10`，普通 `flutter test` 不再出现 framework／engine 语义 API 混用。此前 SDK 混用编译失败与并行 `flutter clean` 导致的 Android `R.jar` 消失不计为业务断言结果。本节仅记录主机定向回归，不代表真机播放、全仓测试或发布包验收。

### 2026-09-20 手机选集关闭入口

- 历史快照：下列记录对应旧版左下角关闭 X，后续由“选集顶部导航”变更替换为左上角返回箭头，不作为新版位置验收。
- 非 TV 的 Flutter / MPV 选集面板左下角新增关闭按钮，TV 焦点布局保持不变。
- `flutter test --no-pub --reporter expanded test/player_episode_picker_dialog_test.dart test/player_small_dialog_focus_test.dart`：35 项通过。覆盖手机横竖屏、列表/网格的左下角位置与取消返回值、加载中关闭及迟到成功/失败结果，以及原有 TV 焦点回归；另目视检查 320dp 列表/网格组件截图。
- 两个本轮修改的 Dart 文件定向 `dart analyze` 无问题。这些是主机组件验证，不是真机播放验收；未运行发布预设或生成安装包。

### 2026-09-20 组件重构回归

详情、搜索与转存、缓存、MPV 与 iOS 宿主的四组重构验证单独记在 [组件重构记录](reviews/review-closure-2026-09-20.md#组件边界重构)。主任务的跨模块集成集合 105 项通过，`dart analyze lib test` 无问题；各子任务的定向集合与它有重叠，不能直接累加。本轮是组件职责和行为回归，不是新一次全仓/发布构建或设备性能采样。其他并行任务的性能改动保持原记录边界。

补充主任务新增组件集合 67 项、缓存/焦点/UI 集合 64 项通过；iOS 模型/存储 runner 和既有记忆/字幕契约通过，无签名 arm64、iOS 13.0 目标的 Xcode Debug 构建成功。RunnerTests 仅类型检查，未执行 XCTest 或真机后台/字幕/遥控器验收；既有主线程隔离与图标资源警告保留。

### 2026-09-20 性能审计后实施

逐项状态见 [审计处理表](reviews/performance-audit-2026-09-20.md)，具体请求/缓存/日志契约见 architecture 与 development-network。本轮不覆盖历史 smoke 数据，不修改画质/缓冲策略、不裁剪历史，不将代码复杂度下降解释为设备测速结果。

- 性能、图片、日志、搜索和 NAS 定向回归 112 项通过；补充夸克取消、动态并发池、搜索迁移和缓存拆分后的回归 59 项通过。这两组有重叠，不能相加作为独立用例总数。
- 最终 `flutter test --no-pub --concurrency 2 --reporter expanded`：**1681 项全部通过**，包含同工作区完成的搜索/存储/播放组件拆分；实际运行约 7 分钟，受到同机并行构建影响，仅作功能回归，不作速度基线。前一轮 1639 通过/1 失败的空索引取消问题已在本轮通过。
- 机制断言覆盖：图片慢正文超时/累计字节中止、共享消费者取消、隐藏超过 UI 租期后释放传输；16ms 跨事件写合并/clear/dispose 顺序；评分人数只写两个变化 shard；12 个冷历史读取只读一次；160 个 NAS 剧集的并发冷读只加载一次；预览跳过超大残行；日志批量/关键 flush/清理及队列背压。
- 完整回归中发现空 NAS 缓存于容器销毁后读取设置的取消异常，已改为空索引直接返回并通过相关回归。期间搜索/存储/iOS 同工作区拆分曾造成暂态编译错误，不回退其他任务的改动；验证以最后结果为准。
- `flutter analyze --no-pub` 无问题；Kotlin `:app:compileDebugKotlin` 通过（最终增量跳过 Flutter assemble 单独核对原生代码）；拆分后的 AppDelegate/NativePlaybackMemoryStore/NativePlaybackModels/NativePlaybackViewController/SettingsDocumentExporter 通过 `swiftc -frontend -parse`，这不是 iOS 链接构建或设备运行验证。
- `NativeAppLoggerTest` JVM 专项 1 项通过，验证调用返回时尚未触碰磁盘、后台单线程按序写入、满容量轮转保持完整 JSON 尾行及最新记录；未等同验证 Android 厂商闪存耗时或崩溃现场。
- 未连接 TV，未运行发布预设或交付 APK。blur、buffer、解码、首帧及 ARM32/ARM64 峰值内存仍按 performance-device 执行，不声称这些测量项已完成。

### 2026-09-20 逻辑统一回归

本轮在持续有其他任务修改的同一工作区执行，不能把某次通过当成所有后续修改的证明。未运行发布预设、未递增版本、未生成交付 APK，也未做设备性能采样。

- 14 个受影响测试文件的定向回归：150 项通过，覆盖首页 / 详情缓存、WebDAV / Quark NFO、播放记忆、版本工具、设置引用与两种网盘转存交互。
- 最后一次播放记忆、资源身份兼容、版本工具复测：24 项通过；版本 CLI 只修改临时 pubspec，覆盖固定批次版本、CRLF 和非法月份拒绝。
- Android 全量 JVM：337 项，336 通过、0 失败、1 跳过；包含共享播放记忆 fixture、时间戳排序裁剪和原生选集共享调色板。使用 `-x :app:compileFlutterBuildDebug` 复用已有 Flutter 输出，原生 Kotlin 和 JVM 测试正常编译，不代表完整发布构建。
- Swift 播放记忆契约：10 个阈值用例及 UTC / 时区 / 微秒旧时间戳归一化通过；`AppDelegate.swift` 与新策略文件通过语法解析，Xcode 工程通过 `plutil -lint`，未做 AVPlayer 真机续播验收。
- 策略生成 `--check`、两个 Bash 发布入口 `bash -n`、`git diff --check` 通过。本机无 PowerShell，未执行 PowerShell 发布入口。
- 最后一次 `flutter analyze --no-pub`：`No issues found`。整仓 Flutter 复跑未完成：机器负载超过 400 并发生大量内存交换，已停止本任务的重复重型验证。中断前记录到两项 `app_network_image_test.dart` 的 TV 图片加载失败，以及 `nas_media_indexer_test.dart` 新增冷加载并发合并用例失败（期望一次读取、实际六次）；这几处属于运行期间并行修改的工作区，不能把本次定向通过结果扩展成整仓全绿。SIGTERM 造成的收尾错误不计为业务断言失败。
- 最新增加的微秒 fixture 在 Dart / Swift 已通过；Android 全量通过后追加的 fixture 复跑因同机 Gradle 争用中断，不冒充再次通过。此前 JVM 已覆盖毫秒、时区、排序、裁剪及单调时间戳。

下方记录是本轮统一之前的历史快照，选集调色板失败已经在上面的 JVM 复跑修复；不要把两个时点合并计数。

2026-09-20，在包含既有未提交修改的 macOS 工作区执行。以下是**执行当时的快照**，不是后续继续编辑的工作区全绿声明：

| 检查 | 结果 | 边界 |
| --- | --- | --- |
| `flutter analyze --no-pub` | 无问题 | 静态分析，不是所有平台构建 |
| `flutter test --no-pub --reporter expanded` | 1580 项通过 | 主机单元 / 组件回归，不是设备播放 |
| `dart tool/generate_playback_policy.dart --check` | 通过 | Dart / Kotlin 生成策略与 JSON 一致 |
| Android `:app:testDebugUnitTest` | 318 项：316 通过、1 失败、1 跳过 | 失败为选集外观源码断言；跳过为需要外部 LPCM 样本的可选测试 |
| Android `:app:compileReleaseKotlin` | 单独执行通过 | 有弃用警告；没有生成或交付 APK |
| Swift 字幕语言契约 | 16 项通过 | 只编译语言策略与 fixture runner |

Android 失败位于 `android/app/src/test/kotlin/com/example/starflow/NativePlaybackSettingsAppearanceTest.kt:101`，检查选集面板源码是否包含指定调色板引用；本次未修改 UI 或测试绕过此失败。Gradle 的测试失败会使同一命令后续任务不再执行，因此本次另行运行了 release Kotlin 编译并通过。JVM 报告通常生成在 `build/app/reports/tests/testDebugUnitTest/index.html`，后续构建或清理会覆盖 / 删除，不能作为永久证据链接。

Flutter 全量运行于本地时间约 00:22 完成；文档收尾期间又出现公共组件、位图字幕解析、设置引用协调和发布版本工具等代码改动。本文已补充这些文件的职责，但没有把它们冒充为前面测试覆盖的内容，也没有启动发布预设来验证。需要针对最终稳定工作区重新运行回归。

本次未重新运行五场景性能采样、未运行发布预设，也没有新增真机性能数据。仓库现有 [perf_baselines.json](../tool/perf/perf_baselines.json) 生成于 **2026-04-11**，每场景只有 1 次采样：startup 2931ms、home 2568ms、detail 2988ms、player 2773ms、index 2635ms。它只是一份历史 smoke 记录，不是当前版本基线，本次保留原文件未覆盖。

### 位图字幕专项（2026-09-20）

本次 PGS/VobSub/DVB 加固及 MPV 绑定改动的专项检查，与前面的全量快照分开记录：

| 检查 | 结果 | 边界 |
| --- | --- | --- |
| Flutter 字幕五文件回归 | 34 项通过 | 新增绑定测试，以及 pipeline、server track resolver、FNTV、session preference |
| Android 字幕及相邻提取器/会话专项 | 86 项通过，无失败或跳过 | 含 11 项有界位图测试、真实 TextRenderer 时钟测试、作用域隔离；Bitmap 是 JVM mock |
| 本次涉及的 10 个 Dart 源码/测试文件定向分析 | 无问题 | 不代表并行修改文件的状态 |
| 最新全项目 `flutter analyze --no-pub` | 2 条 info | `persistent_image_cache_impl_io.dart:46`、`online_subtitle_repository_io.dart:149` 的大括号样式，属于并行修改文件 |

Flutter 命令：`flutter test --no-pub test/mpv_subtitle_render_binding_test.dart test/subtitle_pipeline_regression_test.dart test/playback_server_track_resolver_test.dart test/native_fntv_service_test.dart test/playback_subtitle_session_preference_test.dart`。

Android 在 `android/` 运行 `./gradlew :app:testDebugUnitTest -x :app:compileFlutterBuildDebug -Pandroid-skip-build-dependency-validation=true --console=plain`，使用 `--tests` 选择 `*BoundedBitmapSubtitleTest`、`*PgsReaderTest`、`*NativeSubtitle*Test`、`*NativeDualSubtitleTrackPolicyTest`、`*NativePlaybackSubtitleStyleControllerTest`、`*NativePlaybackExtractorsFactoryTest`、`*NativeTsH264SeekTest`、`*NativePlaybackSessionTest`。跳过 Flutter 打包任务是为了隔离运行期间其他任务的 Dart 改动，Kotlin/Java 和 JVM 测试实际编译；不是 APK 构建证据。报告目录可能被并行测试覆盖，以上只统计选择范围。

过程中曾遇到并行生成策略字段及日志模块编译暂态错误；未改动这些无关文件，恢复后字幕 Flutter 集重新通过。本轮未运行发布预设、未修改版本或交付 APK，也没有真机显示/峰值内存测量。资源上限和回归样本只证明边界行为，不证明低内存 TV 的实际播放效果。

### TV 焦点回归（2026-09-20）

同日约 00:55–01:01 的独立焦点检查，不能与上方较早的全量结果合并成当前工作区全绿结论。覆盖清单与页面职责见 [TV 焦点清单](tv-focus.md)。

| 检查 | 结果 | 边界 |
| --- | --- | --- |
| Flutter 焦点及相邻页面回归 | 352 项通过 | 公共控件、侧栏、首页、详情、设置、媒体库、搜索、字幕与播放器弹窗 |
| `tv_press_only_shortcuts_test.dart` 单项补跑 | 1 项通过 | 验证重复事件拦截器保留快捷键触发键及调试描述；与上行合计 353 项 |
| Android 六个焦点／遥控器测试类 | 50 项通过，无失败或跳过 | JVM 策略与 mock 验证，不运行 ARM 播放器或系统输入法 |
| 本轮涉及的 Dart 源码与测试静态检查 | 无问题 | 定向检查，不代表全仓库无告警 |
| `dart analyze lib test` | 2 个 warning、2 个 info | 位于并行改动文件，未在焦点任务中修改 |

原生运行使用 `:app:testDebugUnitTest`、`-Pandroid-skip-build-dependency-validation=true`，以 `--tests` 限定 `NativePlayerTvFocusPolicyTest`（4）、`NativePlayerTvSeekPolicyTest`（4）、`NativePlaybackRemoteControllerTest`（23）、`NativePlaybackControllerViewTest`（9）、`NativeEpisodePickerNavigationTest`（4）和 `NativePlaybackNumberPickerTest`（6）。本轮没有改原生焦点实现，也没有重复运行前述全部原生测试。

全仓库静态检查的 warning 是 `home_controller.dart`、`library_cached_items.dart` 中未使用的评分工具导入；info 是 `nfo_metadata.dart`、`playback_memory_policy.dart` 的条件分支括号风格。另一次包含转存流程的运行发现 `search_page_save_progress_test.dart` 的 `CloudSaveDrive.quark strm failure closes progress` 失败：STRM 失败后刷新次数期望为 0，实际为 1；该测试显式使用非 TV 模式，与并行的转存后处理整合有关，未调整其业务行为或测试断言。

快捷键单项补跑最初在编译阶段遇到磁盘 `errno = 28`，空间恢复后重试通过。未清理其他任务文件；没有生成 APK、修改发布版本或进行设备性能测量，`adb devices` 无连接设备。

## 比较条件与策略背景

以下保留自 2026-08-27 起的架构 / 性能检查事项，并按当前实现核对。代码边界变化不能单独证明性能改善：
The latest architecture pass moved several hot paths out of single large files:

* Home presentation is now split between `home_page.dart`, `home_page_hero.dart`, and `home_page_sections.dart`.
* Home application wiring is now split between `home_controller.dart`, `home_controller_models.dart`, and `home_feed_repository.dart`.
* Playback presentation is now split between `player_page.dart` and `presentation/widgets/player_page_*.part.dart` plus shared overlay/dialog widgets.
* Playback network-speed labels reuse existing player telemetry: Exo is event-driven through its `DefaultBandwidthMeter`, while non-Web MPV reads the local `cache-speed` property once per second. Neither path launches an additional network probe; include the visible control chrome when comparing playback UI frame cost.
* NAS indexing is now split across `nas_media_indexer.dart` and the `nas_media_indexer_*` part files (`grouping`, `refresh_flow`, `storage_access`, `indexing`, `refresh_support`).
* Recent playback ordering now depends on the monotonic `updatedAt` behavior in `playback_memory_repository.dart`, which matters most on Windows where multiple saves can happen in the same millisecond.
* Home source loading and metadata prefetching retain separate schedulers but share one persisted maximum-concurrency value with Emby and NAS/WebDAV work. Record that value, initial batch sizes, continuation delays, and foreground resume delay with every comparable baseline.
* A single Home navigation tap is the explicit soft-recovery boundary: it removes scheduler-owned batch/quiet waits and cancels background library refreshes without zeroing active counters or duplicating in-flight requests. The TV exit dialog only holds new metadata prefetch starts while visible and resumes them immediately when cancelled.
* Lifecycle and memory-pressure admission are lease-based and stack safely. Backgrounding pauses new Home and metadata work; foreground resume waits for the first frame plus 400 ms. Memory pressure adds a separate two-second quiet window and cancels background library refreshes without clearing persistent caches or active counters.
* Queue diagnostics warn once per continuous queue period after 5 seconds for Home/metadata and 4 seconds for TV raster images. Compare `oldestWaitMs`, active/pending counts, pause holds, and the configured maximum before treating a long wall-clock wait as a performance regression.
* Explicit user refreshes may consume one half-open probe per currently open Douban/metadata host circuit. Automated baseline startup does not arm probes, so keep manual refreshes outside a comparable run.
* The default shared maximum is `2`; Home starts `2` modules in the first batch with a `350ms` continuation delay, while metadata starts `12` items with a `300ms` continuation delay. Scrolling, focus movement, and page transitions defer new metadata starts for `400ms` by default.
* NAS/WebDAV source, collection, and enrichment-item budgets all read the shared maximum, with internal caps of `2` sources and `4` collections/items. Every online enrichment item additionally passes through the global metadata limiter.
* Structure-inferred episodes resolve online series metadata with the parent series title. Provider in-flight/result caches are therefore shared across a season instead of issuing one title search per episode filename; optional episode still requests remain separate.
* NAS/WebDAV series and season hierarchies are materialized into the source cache once and indexed per section. Detail child reads therefore avoid regrouping the full source for every series open or season switch.
* Large episode rows remain lazily built. TV artwork uses a shared four-request raster-load gate whose permits carry an eight-second self-healing lease, so an offstage widget cannot permanently stall Hero and poster loading. Image HTTP work times out after 15 seconds and retries after 1, 4, and 12 seconds. Already displayed detail sections remain mounted when covered by the player; page visibility and TickerMode gate the series-provider subscription.
* Detail series browsing starts after local source restoration without waiting for online metadata refresh. History and season reads run concurrently; series completion rebuilds only its Consumer region, and progress badges select their displayed text. Single-season content uses 292 logical pixels; only multi-season content adds the 68-pixel season selector. Errors use their natural height and empty series remain hidden. Validate cold/warm history, slow metadata, season switching and error states on TV; host smoke timings are not device frame measurements.
* Emby section refreshes enter the same global limiter as NAS metadata items. Maintenance sections have priority, so a large Emby library no longer launches every section request alongside NAS enrichment.
* Emby library persistence uses the current small manifest plus a source summary and source/section shards. Root-library and collection-only reads share a newest-400-item summary, section-scoped Home loads decode only the requested shard, and full-library matching decodes at most two shards concurrently. Identical snapshot and shard reads share in-flight work. Fallback payloads exclude items already represented by section shards, and large JSON work runs on a background isolate. Loads slower than `500ms` emit an info-level `storage.emby-cache` record. Legacy single-payload caches are not read or migrated.
* Detail-cache saves use a 16 ms timer window across event-loop turns, followed by serialized mutation. Clear queues behind accepted writes and disposal flushes accepted batches. Byte-identical payloads skip writes; rating updates persist only changed shards. These are write-count reductions, not physical fsync or device latency measurements.
* NAS/WebDAV section reads now apply `sourceId + sectionId` in the Sembast finder instead of loading a whole source into Dart before filtering.
* Bootstrap and the navigation shell share cold-start refresh completion state, so a baseline should contain at most one automatic Home refresh cycle.
* Structured logging and the frame monitor are active by default. Keep the same recorded log levels across comparison runs because trace-heavy diagnostics add some I/O.
* Successful metadata cache hits, joins of already in-flight requests, and empty sidecar contexts no longer emit one `TRACE` record per item. Keep comparing warning/error counts, but do not treat the lower trace volume as missing work.
* Movie version-folder recognition and the migration fingerprint run locally during NAS/WebDAV indexing. The library emits one representative movie while retaining the real files for detail playback choices, so compare both `media_index` duration and final record/card counts after this change.
* Detail source selection and playback-version selection are now separate derived views over the same retained candidate state. The source selector deduplicates providers, while the Hero-adjacent version selector only builds the selected source's playable files; include a multi-source, multi-version detail sample when investigating `detail_first_screen` or interaction regressions.

### When to run
* After modifying performance-sensitive controllers such as `HomePageController`, `HomeFeedRepository`, playback startup coordinators/resolvers, or retained async controllers that were part of the P0/P1 efforts.
* After touching `home_page.dart`, `home_page_hero.dart`, or `home_page_sections.dart`, because they directly affect the `home_first_screen` baseline.
* After touching detail presentation hot paths such as `detail_page_providers.dart`, `detail_resource_info_section.dart`, or `media_detail_page.dart`, because they directly affect `detail_first_screen` and detail interaction regressions.
* After touching `player_page.dart`, `presentation/widgets/player_page_*.part.dart`, `player_network_speed_label.dart`, `player_playback_options_dialog.dart`, or playback startup routing/execution, because they directly affect `player_open`.
* After touching `nas_media_indexer.dart` or any `nas_media_indexer_*` part file, because those changes can shift both `index_refresh` and any home/detail path that depends on index freshness.
* After changing `playback_memory_repository.dart`, because recent playback ordering changes can indirectly affect home feed stability and smoke expectations.
* After changing `home_feed_load_scheduler.dart`, `metadata_prefetch_concurrency_limiter.dart`, network guards, startup refresh settings, or structured logging.
* Before merging large refactors that could affect the timeline between user interaction and the first frame.

### Post-save directory refresh

Post-save WebDAV discovery uses the existing incremental refresh path and its normal scan, cache and concurrency policies. OpenList/AList STRM directories are supported when exposed through a WebDAV `/dav/...` path; no management `/api/...` request or server refresh call is made. Compare the existing `index_refresh` smoke separately; no server refresh API or periodic worker is part of this change.

### Exo TV directional-hold verification

The September 10 change coalesces directional repeats into one absolute seek per 250 ms window, with immediate first-press and key-up commits. Acceleration remains 10/30/60/120 seconds per input. Pending work is cancelled when focus, playback session, or the active interaction changes. The native memory store reuses unchanged decoded history, and Android media-session updates reuse the sampled display icon and skip unchanged metadata/notifications. These are code-level work reductions, not measured device frame-rate improvements.

* Run `./gradlew :app:testDebugUnitTest :app:compileReleaseKotlin -Pandroid-skip-build-dependency-validation=true` from `android` for hold timing, release, reversal, cancellation, seek bounds, snapshot invalidation and media-publication regressions.
* On a connected TV, compare short taps and 2/5/10-second holds in both directions, with the controller initially hidden and visible, and while paused or buffering. Include a low-memory/API 23 device and both a local sample and the same remote high-bitrate sample.
* Record controller frame timing separately from decoded-video dropped frames, audio underruns and key-up-to-playback recovery. Use existing `playback.performance` session summaries and Android device traces; seek buffering is not evidence of a rendering regression by itself.
* Check direction changes, start/end bounds, Back/Menu/confirm during a hold, focus loss and an episode switch with pending input. Confirm the controller does not flash closed or steal focus, no old callback seeks the next episode, and playback metadata/buttons update after a title, duration, pause or queue-boundary change.
* Host smoke timings and JVM mock-call counts cannot certify these device results. No TV device measurement is recorded for this change yet.

### Audio conversion verification (updated 2026-09-20)

LPCM now reuses a 24-byte sample-frame buffer, a 46,080-byte output buffer and
one ParsableByteArray. The JVM batching test feeds 1,200 four-byte fragments
(25 ms, stereo/48 kHz) and expects three metadata submissions, not 1,200.
This is a deterministic work-count assertion, not a measured CPU/GC improvement.

For a local, legally available Blu-ray LPCM TS sample, compare the reader with
an independent FFmpeg decode without committing media into the repository:

```bash
ffmpeg -i sample.ts -map 0:a:0 -c:a copy -f data /tmp/lpcm-packets.bin
ffmpeg -i sample.ts -map 0:a:0 -c:a pcm_s16le -f s16le /tmp/lpcm-reference.bin
cd android
STARFLOW_LPCM_PACKETS=/tmp/lpcm-packets.bin STARFLOW_LPCM_REFERENCE=/tmp/lpcm-reference.bin ./gradlew :app:testDebugUnitTest --tests '*PcmBluRayReaderTest'
```

The optional fixture test is skipped when the two environment variables are
absent. The local stereo 48 kHz/16-bit TS sample matched byte-for-byte; synthetic
tests cover mono padding, 5.1/7.1 order, all fragment splits, preservation of 20/24-bit samples,
seek, missing PTS and sample-rate changes. Real multichannel/high-bit-depth
samples and ARM32/ARM64 decoder execution still require device validation.

The example reference command is for 16-bit input; for 24-bit use
`-c:a pcm_s24le -f s24le`. Precision tests execute the actual Media3 float and
integer audio processors on the JVM, including the lowest 24-bit sample bit.
Policy tests cover normal speed, pitch/speed changes, explicit PCM compatibility
and one-shot AudioTrack failure fallback. These are not AudioTrack device tests.

On API 23 TV and modern HDMI devices, test AC-3/E-AC-3/JOC, TrueHD, DTS/DTS-HD,
MP1/MP2/MP3 and supported LPCM layouts with missing metadata, mixed audio tracks,
output-mode changes, seek, speed, pause and episode changes. Capture actual
`playback.audio` decoder/output logs, underruns, CPU/GC and A/V sync. Confirm an
audio fallback happens at most once and never changes the video decode policy.
No connected-device audio performance result is recorded by this change.

## 运行命令

在仓库根目录执行，确保 `flutter` 在 PATH。先完成依赖安装和功能回归；对比期间不要同时运行 Flutter 构建、Gradle 或 iOS 发布脚本，避免共享输出目录争用。

```bash
dart tool/perf/run_perf_baselines.dart --runs 5 --output tool/perf/perf_baselines.local.json
```

Common variants:

```bash
dart tool/perf/run_perf_baselines.dart --runs 3 --output /tmp/starflow-perf.json
dart tool/perf/run_perf_baselines.dart --scenario player_open --runs 1 --output /tmp/starflow-player-perf.json
dart tool/perf/run_perf_baselines.dart --scenario startup,home_first_screen --runs 5 --output /tmp/starflow-startup-perf.json
```

`/tmp` 示例用于 macOS / Linux；Windows 可使用仓库内输出路径。脚本当前默认路径用 Windows 反斜杠拼接，所以跨平台调用必须显式提供 `--output`，避免在 POSIX 上生成错误位置的文件。这里记录现有限制，没有修改脚本。默认不覆盖历史基线；明确需要建立新基线时再指定 `tool/perf/perf_baselines.json`，同时记录机器、SDK、缓存和样本数。

### Output and validation
Review the generated report for regressions in the five baseline IDs: `startup`, `home_first_screen`, `detail_first_screen`, `player_open`, and `index_refresh`. The JSON contains `generatedAt`, `runsPerScenario`, and a `results` array with `runsMs`, `p50Ms`, and `p95Ms` for each scenario. If runtime shifts significantly, capture the new numbers together with the relevant diff and scenario id.

场景失败时脚本提前退出，不会写本轮完整报告；旧路径上的 JSON 可能仍在，必须同时检查退出码与 `generatedAt`。报告不自动收集设备、系统负载、SDK 版本或缓存状态，这些应随测量记录保存。

## 2026-09-20 TV 统一扫码文本输入

本机定向验证：以下 4 文件共 51 项通过，覆盖真实本机 HTTP、空文本/空白/多行原样传输、密码页面遮罩、标题转义、鉴权、64 KiB 声明与流式限制、超时/取消/到期、单次接收，以及 TV 弹窗内入口、输入格式、确认/取消、迟到会话和直播草稿回填。直播回填 widget 覆盖 320×640 与 1280×720；这不是手机到电视跨设备验收，也不代表实际扫码识别、系统输入法或浏览器兼容性已验证。

```sh
flutter test test/text_input_transfer_service_test.dart test/features/settings/presentation/settings_text_input_field_test.dart test/live_playlist_transfer_page_test.dart test/live_playlist_transfer_service_test.dart
```

不运行 APK 发布预设，不递增版本或重建二进制；本轮不提供真机性能数字。该集合含其他直播文件/备份回归，与历史集合重叠，不累加为全量通过数。

同日扩大回归 `flutter test test/features/settings/presentation test/live_tv_page_test.dart test/live_backup_page_test.dart` 共 91 项通过；补充方向键切换到扫码按钮并以确认键打开后，独立重跑 `settings_text_input_field_test.dart` 15 项通过。上述集合重叠，不相加。涉及输入服务、弹窗、直播入口及测试的定向 `dart analyze` 无问题，`git diff --check` 通过。曾扩大到整个直播目录时发现并行变动中的 `live_channel_picker.dart` 存在 `listEquals` 未定义问题，因此本条不声明全目录静态检查通过。

## 全量功能回归

仓库根目录：

```sh
flutter analyze --no-pub
flutter test --no-pub
dart tool/generate_playback_policy.dart --check
```

Android 目录分别执行，避免单元测试失败遮蔽编译检查：

```sh
./gradlew :app:testDebugUnitTest -Pandroid-skip-build-dependency-validation=true
./gradlew :app:compileReleaseKotlin -Pandroid-skip-build-dependency-validation=true
```

JVM mocks、源码断言与 Swift 纯策略测试不执行 ARM decoder，不验证系统字幕、HDMI、锁屏或 PiP。字幕的 Swift 命令见 [字幕链路](subtitles.md)，AAR 来源和重建见 [音频依赖](../android/app/libs/README.md)。

### Suggested focused verification
For this repo, the perf baseline run is usually paired with a few focused checks so we can tell whether a regression is functional, orchestration-related, or purely performance-related:

```bash
dart analyze lib/features/home/application/home_controller.dart lib/features/home/application/home_controller_models.dart lib/features/home/application/home_feed_repository.dart
flutter test test/home_controller_test.dart test/home_settings_slices_test.dart

dart analyze lib/features/playback/presentation/player_page.dart lib/features/playback/presentation/widgets lib/features/playback/data/playback_memory_repository.dart
flutter test test/playback_memory_repository_test.dart test/features/playback/application/playback_startup_routing_test.dart test/playback_target_resolver_test.dart test/playback_mpv_policy_test.dart

dart analyze lib/features/library/data/nas_media_indexer.dart lib/features/library/data/nas_media_indexer_grouping.dart lib/features/library/data/nas_media_indexer_refresh_flow.dart lib/features/library/data/nas_media_indexer_refresh_support.dart
flutter test test/nas_media_indexer_test.dart

dart analyze lib/core/network lib/core/logging lib/features/home/application/home_feed_load_scheduler.dart lib/features/metadata/application/metadata_prefetch_concurrency_limiter.dart
flutter test test/network_failure_test.dart test/network_request_guard_test.dart test/starflow_http_client_test.dart test/metadata_prefetch_concurrency_limiter_test.dart
```

### Tips
* Run under the same system load you plan to ship under so the numbers stay comparable.
* Re-run the script after applying the fix if the regression was real; this rewrites the baseline JSON, which you can commit alongside the change when the new numbers are expected.
* If a baseline regresses right after a file split, verify the focused tests first. In this codebase, regressions after refactors are often caused by wiring/state-order changes rather than the split itself.
* Keep the independent visual/playback switches, both startup refresh switches, the shared concurrency value, scheduler batch/delay values, and log levels identical when comparing two runs. TV-fixed protections are platform rules rather than comparison-time switches.
## 2026-09-20 直播无底栏与分层返回验证

本轮使用 `.fvm/flutter_sdk` 固定 Flutter 3.38.10，执行：

```sh
.fvm/flutter_sdk/bin/flutter test --no-pub --reporter expanded --dart-define=LIVE_TV_REVIEW=true test/live_tv_page_test.dart test/live_channel_picker_test.dart test/live_playback_lifecycle_test.dart test/live_network_speed_label_test.dart test/live_navigation_resume_test.dart
.fvm/flutter_sdk/bin/dart analyze lib/features/live_tv/presentation/live_player_page.dart test/live_tv_page_test.dart
```

5 文件共 50 项测试通过，定向分析无问题。页面测试中的新增场景覆盖手机／TV、320×640／1280×720、2 倍系统字号、节目单异步加载前后 112dp 固定栏高、无底栏、按需全屏设置，以及设置／频道／节目单各自的系统返回、Escape、Go Back 和直接 `Navigator.pop`。断言关闭局部界面不停止、重建或释放播放内核，恢复画布焦点；音轨弹窗与线路下拉先关闭自身，再返回播放器，最后退出才释放。既有内核切换、强调色、菜单历史恢复、生命周期及网速测试一并通过。

`build/live-tv-review/` 输出 390／1280px 播放器与设置等主机截图，人工检查无底部按钮、设置无遮挡。使用 fake engine，黑色画布不是实际解码截图；未做真实源／电视遥控器验收，本任务未运行发布预设或交付 APK。与本文其他历史批次不累加。

## 2026-09-20 直播失败详情与日志验证

用户 17:31 导出的修复前日志包含 5 个频道共 12 次 Exo `engineError`，每条 `errorType=null`，另有两次订阅刷新失败。日志没有 HTTP 状态、解码错误或媒体地址，不能确定这些频道的根因。此轮补齐原生到 Flutter 的白名单错误摘要及频道列表/节目单刷新阶段，不改变重试、网络鉴权、代理或解码配置。

固定 `.fvm/flutter_sdk` 的 Flutter 3.38.10，以下 9 文件共 **107 项通过**：

```sh
.fvm/flutter_sdk/bin/flutter test --no-pub --reporter expanded test/live_playback_error_test.dart test/live_failure_logging_test.dart test/live_failure_page_test.dart test/live_exo_bridge_test.dart test/live_playback_lifecycle_test.dart test/live_tv_test.dart test/live_tv_data_test.dart test/live_review_regression_test.dart test/live_tv_page_test.dart
.fvm/flutter_sdk/bin/dart analyze lib/features/live_tv/application/live_playback_error.dart lib/features/live_tv/application/live_playback_controller.dart lib/features/live_tv/data/live_repository.dart lib/features/live_tv/presentation/live_player_page.dart test/live_playback_error_test.dart test/live_failure_logging_test.dart test/live_failure_page_test.dart test/live_exo_bridge_test.dart
```

定向分析无问题。新增覆盖 HTTP/网络/格式/解码分类、缺失及恶意通道字段过滤、旧代次隔离、停止后保留当前失败摘要、重试清除摘要、真实本地日志导出不含地址/凭据、频道/节目单 HTTP 失败保留缓存，以及 320×640 和 1280×720 的失败提示与手动重试。页面验证使用 mock MethodChannel，不代表真实解码。

Android 在 `android/` 运行 `./gradlew :app:testDebugUnitTest -x :app:compileFlutterBuildDebug -Pandroid-skip-build-dependency-validation=true --tests '*LiveTv*Test' --console=plain --quiet`，5 类 **31 项通过、0 失败/跳过**。包括 PlaybackError 4、View 7、Policy 13、HttpTransport 6、NetworkSpeed 1；Kotlin/JVM 测试实际编译，排除 Flutter 打包，不是 APK 构建。初次新增 JVM 测试缺少系统时钟 stub、页面两个独立 fake-clock 用例共享清理队列导致失败，补齐测试环境并将双尺寸放入同一时钟用例后重跑通过，未因此改动生产生命周期策略。

`adb devices -l` 无设备，未验证故障源、真机首帧或实际恢复效果；未运行发布预设、未递增版本或交付 APK。上述主机集合与本文历史批次重叠，不累加为全仓通过数。

## 2026-09-20 直播节目单右侧布局

节目单面板改为靠右，频道列表保持靠左；节目单所有宽度共用标题行网速，避免右上角独立标签遮挡面板。保留 440dp 宽屏面板、窄于 480dp 全宽显示及系统安全区。

```sh
.fvm/flutter_sdk/bin/flutter pub get
.fvm/flutter_sdk/bin/flutter test --no-pub --reporter expanded --dart-define=LIVE_TV_REVIEW=true test/live_tv_page_test.dart test/live_channel_picker_test.dart test/live_network_speed_label_test.dart test/live_current_programme_test.dart
.fvm/flutter_sdk/bin/dart analyze lib/features/live_tv/presentation/live_player_page.dart test/live_tv_page_test.dart
```

固定 Flutter 3.38.10 下，4 文件共 27 项主机测试通过，定向分析无问题。执行前发现生成的依赖配置指向 Flutter 3.41.6，先由固定 SDK 重新解析依赖并同步锁文件，未手动修改 package_config。页面回归检查 320／390／1280 宽度、24dp 右侧安全区、两倍字号下的返回流程、左右面板位置、节目单内仅一份网速，以及节目详情／分层返回不换台、不停止或重建会话。

已检查 `build/live-tv-review/guide-390.png` 与 `guide-1280.png`：窄屏全宽、宽屏右侧显示，标题与网速无重叠。使用 fake engine 黑底截图，不代表真实视频、设备性能或遥控器验收；未运行发布预设、递增版本或交付 APK。与其他历史测试批次重叠，不累加。

## 2026-09-20 直播背景不透明度调整

顶部控制栏背景改为 20% 不透明（alpha 0.2），设置／频道列表／节目单背景改为 70% 不透明（alpha 0.7）。只修改背景色 alpha，文字、图标、焦点框及节目单右侧布局不变。

```sh
.fvm/flutter_sdk/bin/flutter test --no-pub --reporter expanded --dart-define=LIVE_TV_REVIEW=true test/live_tv_page_test.dart test/live_channel_picker_test.dart
.fvm/flutter_sdk/bin/dart analyze lib/features/live_tv/presentation/live_player_page.dart test/live_tv_page_test.dart
```

固定 Flutter 3.38.10 下，两文件共 21 项主机测试通过，定向静态分析无问题。页面测试直接断言顶栏／三类菜单背景 alpha，并检查菜单无重复 Material 底色或整层 Opacity；覆盖 TV／非 TV、320／1280 宽度、焦点、返回和播放保留。已检查生成的 1280px 节目单与 390px 设置截图，未见内容遮挡；fake engine 黑底截图不证明真实视频透出效果。未进行真机验收、发布构建或版本递增，与历史测试批次不累加。

## 2026-09-23 WebDAV 目录归并回归

以下为 v16 阶段历史快照；当前验证见下一节，测试数量不累加。

使用项目锁定 Flutter 3.38.10 完成 WebDAV 客户端、真实命名结构、NAS 索引、文件名识别、目录缓存、特殊集、索引作用域、目录路径、夸克共享索引及删除链路共 12 个测试文件，210 项主机回归全部通过；修改代码及测试的定向静态分析无问题。新增《重启人生》三套各 10 集正片与 9 个番外的分类/季集断言、同一一级目录内 30 个电影或混合类型资源只生成一个入口且资源不丢失的断言，以及同名不同实际目录的分组隔离。

使用保存配置只读连接真实 WebDAV，85 个 STRM 资源（包含歌曲）经独立内存索引最终生成 1 个《重启人生》剧集入口。没有远端修改、线上元数据请求或设备索引写入。本记录不是播放、设备性能、TV 真机验收或全量测试通过声明；既有 `test/tmp_reboot_structure_test.dart` 缺少 `debugPrint` 导入，单独运行无法编译，未修改该既有临时文件。

## 2026-09-24 WebDAV 结构流水线回归

项目锁定 Flutter 3.38.10 下，同一组 12 个测试文件共 223 项主机测试通过；并行结构证据扩展合入工作区后再次运行该批测试仍为 223 项通过，相关 20 个源码、测试与诊断文件的定向静态分析无问题，`git diff --check` 通过。覆盖不完整及空扫描保留旧记录、强制重建不覆盖旧分类、深度截断标记、完整增量本地结构写回及 JSON 恢复、episode NFO 覆盖推断并跨刷新保留、平铺电影版本、音频 STRM 过滤、花絮不改变主体类型或抢占默认资源、局部浏览归属及目录祖先校验。

只读使用保存配置复测《重启人生》：39 个视频 STRM，最终 1 个剧集入口，正片第 1 季 10 集且每集 3 个播放版本，第 0 季 9 集番外且各 1 个资源。诊断脚本关闭 sidecar/在线/播放地址补全，避免离线替身触发后台资源检查；仅执行远端目录读取和内存索引。历史 85 个 STRM 中的 46 个音频 STRM 不进入本轮视频索引。

本次不包含设备性能测量、TV 真机播放、发布包构建或版本递增，也不表示全仓测试通过；既有临时测试不在本轮范围内。并行工作区后续改动需独立复验，不能从本节推导其他任务已通过。

## 直播补充验证快照

2026-09-24 从直播功能说明归并的原始记录，以下日期为原执行日期，本次未重跑。各批次有重叠，不累加为全仓通过数。

2026-09-20 开关验证：固定 Flutter 3.38.10，`live_navigation_resume_test.dart`、`interface_accent_test.dart`、`performance_settings_navigation_test.dart`、`app_settings_test.dart`、`app_navigation_shell_tv_focus_test.dart` 共 69 项主机测试通过，相关 6 个 Dart 文件定向静态检查无问题。覆盖默认值、当前配置、JSON 往返、触摸／TV 确认键保存、关闭后首次／重复／切回菜单不自动播放及原有导航回归；该记录不包含本次旧配置清理后的重跑，不代表真机或实际解码验收，未构建 APK。

2026-09-23 旧配置与旧缓存清理验证：固定 Flutter 3.38.10，完整 Flutter 测试集 2860 项通过，`flutter analyze --no-pub` 无问题；Android `NativePlaybackMemoryStoreTest / PlaybackMemoryPolicyTest` 编译并通过。未构建 APK，未做真机或实际直播源验收。

2026-09-22 分组整理主机验证：固定 Flutter 3.38.10，新增分组隐藏/排序、刷新保留、备份替换恢复、备份合并边界和隐藏分组检测过滤测试通过；`live_tv_data_test.dart`、`live_home_layout_test.dart`、`live_channel_probe_controller_test.dart` 以及频道选择器、直播页面、备份页面和直播回归测试共 100 项扩展回归通过，定向分析无问题。仅为主机证据，未做真机、实际直播源或 APK 验证。

2026-09-20 主机验证：`test/live_sources_layout_test.dart` 的 4 项 widget 测试通过，覆盖 360×480 视口、手机／TV 模式及 0／34 逻辑像素底部安全区，检查列表末项、添加与编辑页保存按钮及其下方留白；相关页面与测试静态检查通过。当时扫码页面测试因测试替身缺少接口新增的 `backupBytes` 参数未通过编译；后续扫码备份任务补齐签名并重跑通过，见 [扫码备份验证](performance.md#2026-09-20-tv-直播备份扫码)。未做真实设备验证或发布构建。

2026-09-20 菜单历史播放前置快照（限制为仅 TV 前）：`flutter test test/live_navigation_resume_test.dart test/app_navigation_shell_tv_focus_test.dart test/live_tv_page_test.dart test/live_playback_lifecycle_test.dart` 当时共 68 项主机测试通过。原新增 12 项覆盖手机／TV 菜单触发、返回后不重开、再次点击、无记录／频道删除／隐藏／来源停用／空线路、读取失败、切换菜单／后台／销毁取消，以及连续点击的迟到响应隔离；其中手机自动播放的旧预期已被仅 TV 规则取代，不作为现行行为。菜单测试检查实际播放器路由参数并立即退出，不启动原生解码；现有页面与控制器回归使用测试内核。返回仍按原流程停止并释放播放器，露出保留的频道列表与菜单栏。不是实际直播源或真机验收，未构建发布包。

2026-09-20 订阅列表开关：`live_source_enabled_test.dart`、`live_sources_layout_test.dart`、`live_tv_data_test.dart` 共 32 项主机测试通过，`live_tv_page_test.dart` 与 `live_review_regression_test.dart` 共 29 项通过。覆盖列表直接切换、TV 确认键、320 宽度长名称、保存中重复操作、失败保持原状态、缓存与收藏保留、删除后不重建、编辑保留停用状态及底部留白；定向静态检查无问题。本次没有真机验收或发布构建。

2026-09-20 顶部留白修复：`flutter test test/live_tv_page_test.dart` 共 13 项主机组件测试通过，其中新增 6 项覆盖 0/24/59 逻辑像素顶部安全区及带／不带返回按钮的频道页，断言标题行仅偏移一份安全区高度；对页面与该测试文件的定向 `dart analyze` 无问题。这不是设备截图或真机验收，与下列集合不累加。
