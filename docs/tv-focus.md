# TV 焦点清单

核对日期：2026-09-20。本文记录当前工作区的焦点边界与本轮修复，不代表真实遥控器／输入法验收通过。组件职责以 [架构说明](architecture.md) 为准，网络影响见 [开发网络](development-network.md)。

## 公共规则

- `TvFocusableAction` 统一确认键和菜单键。一次按压执行一次命令，`tvPressOnlyShortcuts` 消费重复事件，不向祖先快捷键穿透；方向导航和左右 seek 仍允许连续输入。
- 普通禁用控件退出寻焦，包括 Flutter `NavigationMode.directional`。只有显式 `focusableWhenDisabled` 的忙碌操作／边界分页保留焦点，`onPressed == null` 时确认无效。
- `TvPageFocusScope`、方向面板与全局安全 Action 共享未布局候选保护。普通寻焦沿用 Flutter；不另建坐标排序、全局焦点缓存或逐帧恢复。
- `scheduleTvFocusRecovery` 只做一次帧末检查并主动安排帧；页面失活、路由被覆盖、目标卸载／禁用或已有可操作焦点时不抢焦点。
- `TvTextInputLauncher` 统一松键后打开编辑器，等待／打开期间拒绝重入，松键前移走焦点则取消。输入框只局部处理上下键离开；返回先到有效操作按钮，再次返回关闭。
- 轻量焦点是绘制与重绘优化，不是全部取消缩放。共享控件自身 State、海报 ValueNotifier 分别更新外观；默认可见性滚动不等同于强制居中。

## 页面边界

| 区域 | 焦点归属与恢复 | 回归入口 |
| --- | --- | --- |
| 一级侧栏 | 可见菜单项上下有界；左边界回当前菜单；隐藏菜单排除焦点 | `app_navigation_shell_tv_focus_test.dart` |
| 首页／Hero | 当前海报优先；首个模块上移回 Hero；异步插入／移除只补缺焦 | `tv_focus_regressions_test.dart`、`home_page_presentation_test.dart` |
| 首页编辑 | 模块／来源稳定节点，重排和删除恢复目标 | `home_editor_tv_reorder_test.dart` |
| 搜索／收藏 | 搜索入口／同步入口首焦点；结果不抢现有焦点；搜索输入复用松键机制 | `search_page_focus_test.dart` |
| 媒体库 | 顶部筛选首焦点；多页分页到边界保焦，确认无效但方向可离开 | `tv_secondary_page_focus_test.dart`、`library_refresh_actions_test.dart` |
| 查看全部／合集／演职员作品 | 常驻页头首焦点，加载／空／失败不依赖海报；迟到结果不竞争首焦点 | `tv_secondary_page_focus_test.dart` |
| 详情／信息管理 | 续播与主操作焦点、剧集恢复不抢主操作；更新忙碌保焦 | `detail_episode_restore_test.dart`、`metadata_index_management_page_focus_test.dart` |
| 设置／目录 | 设置入口和编辑弹窗统一；WebDAV／夸克“选这里／选择”常驻首焦点 | `settings_hierarchy_navigation_test.dart`、`webdav_directory_picker_focus_test.dart`、`quark_folder_picker_focus_test.dart` |
| 在线字幕 | 关键词入口首焦点；搜索／下载忙碌保焦；结果单一焦点目标 | `subtitle_search_page_test.dart` |
| MPV 控件／选集 | 页面命令去重；列表／网格跨段导航与入口恢复保留 | `player_small_dialog_focus_test.dart`、`player_episode_picker_dialog_test.dart` |
| Android Exo | 原有按压身份去重、控制层焦点超时／取消与弹窗恢复；本轮不改原生实现 | `NativePlaybackRemoteControllerTest.kt`、`NativePlaybackControllerViewTest.kt`、`NativeEpisodePickerNavigationTest.kt` |

## 本轮修复

1. 确认／菜单重复事件不再多次执行，也不在移动到另一个共享控件后继续触发。
2. 修正方向导航模式中普通禁用按钮仍可聚焦的问题，保留显式忙碌保焦语义。
3. 设置输入的松键机制提取为公共组件，搜索和在线字幕复用；等待期间转移焦点不再弹出旧编辑器。
4. WebDAV 目录、查看全部、媒体库合集及演职员作品页提供稳定首焦点；目录读取与异步内容更新只补缺焦。
5. 在线字幕消除整条结果和内部按钮的重复焦点，搜索／下载忙碌不丢焦点；媒体库多页翻到边界保焦。
6. 媒体库资源删除确认默认聚焦取消；补齐新抽取弹窗的共享按钮导入。

## 自动化验证

本轮主机验证的结果、范围和未通过的非焦点检查统一记录在 [主机性能与回归验证](performance.md#tv-焦点回归2026-09-20)。页面回归入口见上表；公共规则由 `tv_remote_action_test.dart`、`tv_press_only_shortcuts_test.dart`、`tv_dialog_back_focus_test.dart` 和输入组件测试覆盖。

这些测试覆盖模拟遥控器事件、组件焦点树与原生 JVM 策略，不代表真实系统输入法、物理遥控器或设备帧率验收。本次 `adb devices` 无连接设备。

## 设备复测

- 实际遥控器的确认、Enter、菜单、返回长按与松键，系统返回事件和键盘返回事件分别检查。
- 真实 TV 输入法打开／关闭，输入中按上下／返回；不要将宿主机组件测试视作 IME 验收。
- 首页滚动、媒体库最后一页、慢速目录／字幕请求期间移动焦点，以及离开页面后迟到结果。
- MPV 与 Exo 各自检查选集、字幕、设置弹窗关闭后的焦点，以及后台／前台和窗口失焦后的按键恢复。
- 本轮没有生成 APK，也没有调整版本、ABI、API 23 或发布脚本。
