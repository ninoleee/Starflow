# 开发网络配置

仓库已经内置了一些面向国内网络环境和本地代理的辅助方案，主要集中在 `scripts/` 和 Android Gradle 初始化配置里。

## 0. 2026-04 文档同步

截至 `2026-04-11`，这轮架构/性能优化里和“请求行为”最相关的补充点是：

- 首页已经拆成 seed 抓取层 + 详情缓存装饰层；详情缓存 revision 更新时只会重做本地合并，不会把整轮来源 / 豆瓣抓取一起重新触发
- 首页 presentation 现在也拆成 `home_page.dart`、`home_page_hero.dart`、`home_page_sections.dart`；这次拆分只影响本地 widget/焦点/装配边界，不新增任何网络协议或额外请求源
- 首页 application 现在也拆成 `home_controller.dart`、`home_controller_models.dart`、`home_feed_repository.dart`；这同样只是本地职责收口，不引入新的网络请求
- 首页与媒体库的详情缓存合并已统一走批量读取接口；同一批 seed target 会复用一次本地 payload 读取，重点减少卡片装配阶段的重复本地 `I/O`
- 页面级异步状态统一到 `RetainedAsyncController / retained_async_value` 后，详情、媒体库、人物作品等页在失活或回前台时更倾向复用已有稳定结果
- 详情页、媒体库、人物作品页和搜索页在 inactive 时现在优先取消当前会话或刷新任务，不再无条件失效成功 provider；返回页面时会明显减少重复请求
- 搜索页空关键词会直接短路；多来源结果会先聚合，再按短节流批量提交 UI，不再每个来源返回就触发一次全量排序和整页刷新
- 持久化图片缓存 identity 已升级成 `URL + headers`，并增加磁盘 metadata、`30` 天过期和 stale fallback；这会减少不同鉴权图片串 cache，也减少短期失败时的重复拉图
- “空库自动重建”已经转到后台调度器；当前读链路不再同步等待一次重建任务完成
- 播放启动链已经收口到 `PlaybackStartupCoordinator / PlaybackTargetResolver / PlaybackEngineRouter / PlaybackStartupExecutor`；播放器打开前会先读取本地续播 / 跳过规则并做路线判断；这只调整本地准备顺序，不引入新的网络协议
- 播放页 presentation 现在继续拆到 `player_page.dart` + `player_page_*.part.dart` + 独立 overlay/dialog widgets；这属于本地代码组织与重建范围收口，不改变任何线上请求协议
- 进入播放器时会更早切到“播放优先”模式；从网络侧看，首页 Hero 补数、详情页自动补全和隐藏页图片加载会更快被压住
- `MPV` 的远程流调优、质量预设自动降档和 `ISO` 设备源判断已经收口到本地策略层；这些都只改变本地打开方式和缓冲参数，不引入新的网络协议
- 应用内置 trace / log 当前已统一静音；设置页里保留的 trace 开关仅用于兼容已有设置字段，不再产生运行时输出
- `NasMediaIndexer` 当前已经拆成 `refresh_flow / storage_access / indexing / grouping / refresh_support` 多段 `part` 文件；这次拆分只是在本地把刷新编排、索引计算、分组和缓存访问解耦，不新增任何新的网络协议或请求源
- `PlaybackMemoryRepository` 新增的单调时间戳策略只影响本地“最近播放”排序稳定性，尤其是 Windows 下的同毫秒写入场景；它不涉及任何网络请求

补充说明：

- 当前仓库内置的 `WebDAV / metadata / subtitle / playback / detail resource switch` trace helper 都已静音；默认不再输出扫描、索引、匹配或播放链路日志
- `WebDAV / NAS` 标题识别会在本地剥离 `{tmdbid-...}`、`{tvdbid-...}`、`{imdbid-...}`、`{doubanid-...}` 这类嵌入式外部 ID 标签；这一步只影响本地展示标题和搜索词，不新增网络请求
- `NasMediaIndexer` 主文件压回约 `1k` 行并拆出多个 helper 后，`index_refresh` 相关请求扇出仍然和之前一致；后续如果要排查刷新请求行为，需要把这些 `nas_media_indexer*.dart` 文件视为同一条链路来看
- 如果条目后续已经刮削过或手动关联过详情信息，首页、媒体库和详情页展示时会优先使用缓存里的更新后标题；这同样只是本地缓存合并优先级调整，不增加新的网络请求
- `WebDAV / NAS` 识别里新增的包装目录 / 版本说明忽略，例如 `分段版 / 特效中字 / 会员版 / 导演剪辑版 / 清晰度 / 音轨 / 字幕`，也完全发生在本地，不增加新的网络请求
- `WebDAV / Quark` 媒体源现在还支持“顶层推断目录”：只在目录结构推断里，识别到剧文件或季目录后向上推断剧名时生效；命中这里填写的顶层目录名会立刻停止继续向上，改用下一级已推断目录，没有目录时退回文件名，同样不会增加新的网络请求
- 新增的“剧集只按剧名层级搜刮”只会改变结构推断剧集条目的在线 metadata 查询词；开启后会只用目录剧名查询，并跳过按单集继续请求剧照，整体上会减少这类请求，不会引入新的服务端协议
- 新增的综艺/节目文件名轻量识别，例如 `第X期`、`01 会员版` 这类“集号 + 版本说明”形式，同样只在本地解析，不新增网络请求
- 目录名里如果能识别出明确季号，例如 `Season 1`、`S02`、`第2季`、`Stranger.Things.S02.2160p.BluRay.REMUX`，就会在本地结构推断里直接把这一层当作季目录，不新增网络请求
- 对 `2.巴以 / 5.美国 / 9.韩国` 这类“数字 + 标题”的专题目录，会额外要求同级里存在多个同类兄弟目录；这一步同样只发生在本地结构推断阶段，不会为了重新判季额外发网络请求
- 一旦当前层被识别为季目录，就会把上一级当剧名；像 `怪奇物语/Season 1/Season 2`、`怪奇物语/Stranger.Things.S02.2160p.BluRay.REMUX` 都会把 `怪奇物语` 作为剧名，这同样只是本地结构层级判断，不新增网络请求
- 图片请求如果遇到单张 `404`，展示层会自动尝试备用 artwork，这种情况通常不需要再额外打开网络日志
- 持久化图片缓存当前按 `URL + headers` 区分 identity，避免不同鉴权头误共用同一份缓存；远端失败但本地还有旧字节时，也会优先回退到 stale bytes
- 首页现在拆成 seed 抓取层和详情缓存装饰层；详情缓存变化只会重做本地 merge，不会重新跑一轮来源或豆瓣请求
- 详情页、媒体库、人物作品页和搜索页在页面失活时，只会取消当前会话、刷新或搜索任务，不会顺手把稳定结果一起失效掉
- 搜索页空关键词会直接短路；多来源结果会先聚合，再按短节流批量提交 UI，避免每个来源返回都触发一次排序和布局刷新
- `TV` 模式除了现有详情、搜索、播放和图片请求链路外，配置管理还会临时启用一个局域网 HTTP 传输入口，供手机上传或下载配置 JSON
- Web 端的配置管理直接走浏览器下载和本地文件选择器，不依赖应用私有目录，也不会额外启用局域网传输服务
- iOS / iPadOS 的配置导出现在改成系统文件导出器，只会弹出原生保存面板，不会额外引入新的网络请求
- `TV` 模式里新增的“焦点尽量保持在屏幕中部、页面随焦点滚动”也只是本地交互改进，不增加新的网络请求
- `TV` 详情页里 `Hero` 主操作、季标签和剧集卡片新增的显式方向焦点链，也只是本地焦点规则调整，不增加新的网络请求
- 首页分类海报流、详情页剧集横排和剧照横排新增的桌面端左右翻页按钮也只是本地滚动容器封装，不增加新的网络请求
- 搜索页顶部来源按钮、媒体库筛选按钮统一到同一套 `chip` 规格，以及页头回顶/方向焦点边界，也都只是本地布局与焦点调整，不增加新的网络请求
- `TV` 设置编辑页里把文本输入改成“条目入口 + 弹窗编辑”同样属于本地交互调整，不引入额外接口
- 当前设置区统一页面骨架、统一按钮和统一选择条目，也只是本地 UI 收敛，不增加新的网络请求
- 剧集页里“单集简介区进入单集详情”同样只是本地路由与焦点拆分；进入后复用既有详情页资源匹配、元数据补全和字幕关联链路，不新增新的服务端协议
- 高性能模式额外关闭的启动页动画、导航切换动画、菜单栏自动隐藏、Hero 全屏背景图、首页 Hero 缓动、通用面板阴影和 TV 焦点缩放/阴影，以及新增的 Hero 静态单卡/海报/无阴影、详情页顶部大图区瘦身，都只是本地视觉层简化，不增加新的网络请求
- 设置页里被高性能模式接管的子开关会直接禁用，这也是本地 UI 联动，不增加新的网络请求
- 网络存储里的“STRM 触发等待时间”和“索引刷新等待时间”只是客户端本地延时调度，不新增新的服务端接口
- 网络存储里的夸克目录管理复用同一套夸克云盘接口；浏览、单条删除和清空当前目录都依赖有效 Cookie
- 新增的 `Quark` 媒体源也复用这套夸克 `Cookie + 目录列举 + 下载直链` 接口；不会引入额外的专用媒体服务器协议
- 如果开启了“同步删除夸克目录”，并配置了监听的 `WebDAV` 目录，删除命中这些目录下的文件或文件夹时，也会复用同一套夸克目录接口，到当前保存目录里删除匹配到的影片或剧集目录
- `App 内原生播放器` 与新增的解码模式设置也不引入新的网络协议，仍然复用同一条播放地址和请求头链路
- 非 `TV` 内嵌 `MPV` 改为 Starflow 自己的轻量播放叠层，也只是本地播放器 UI 收敛；首层现在只保留返回 / 播放 / 进度 / 全屏 / 更多，音量、字幕、音轨、外挂字幕、在线字幕与字幕偏移仍然复用现有播放链路，不新增新的服务端接口
- Windows `MPV` 在下一次打开前先串行等待上一实例完成 `pause -> stop -> dispose`，关闭后台播放、退出播放器和打开新片源也会复用同一套本地清理流程，不新增网络请求
- `lib/core/utils/playback_trace.dart`、`lib/core/utils/subtitle_search_trace.dart`、`lib/core/utils/metadata_search_trace.dart`、`lib/core/utils/detail_resource_switch_trace.dart` 当前都已静音；保留这些 helper 主要是为了兼容已有调用点和设置字段
- 非 `TV` 叠层里的 fullscreen 状态透传、窗口态 click-only 唤醒、auto-hide 定时器取消、播放设置弹窗 Material 化和 dispose 保护也都属于本地 widget 生命周期修正，不涉及新的网络协议
- `TV` 播放器新增的“首层极简 + 二层高级”交互，同样只是本地遥控器焦点与播放器控件拆分，不新增新的服务端接口
- 详情页、独立字幕搜索页与播放器页的在线字幕搜索现在都走应用内实现，不依赖外部浏览器；是否真的发起请求由 `设置 -> 播放 -> 字幕` 里的在线字幕配置控制，当前来源统一为 `ASSRT / OpenSubtitles / SubDL`
- 详情页和独立字幕搜索页都不再在进入时自动搜索字幕；只有手动点击搜索时才会发起请求。结构化字幕源会先在应用内下载并验证，只有可直接挂载的结果才会返回；`ASSRT` 未填写 Token 时会直接走网页搜索，填写 Token 后优先走官方 API，并可按设置决定是否在 API 没有可用结果时回退网页链路
- 首页“最近播放”模块直接读取本地播放记忆与详情缓存，不引入新的网络请求
- 最近播放从“具体单集记录”切到“剧集总名 + 单集副标题”的展示规则，也只是本地展示层映射调整，不增加新的网络请求
- `WebDAV` 文件删除虽然仍然只用标准 `DELETE`，但客户端现在会在成功后再次检查父目录，确认远端文件真的已经消失；如果远端仍存在，就不会继续当作本地删除成功
- 进入播放器后，播放会话本身就会把首页 `Hero` 补数、详情页自动补元数据 / 自动本地匹配、隐藏页网络图片加载压住；从网络侧看，播放期间不应继续新增这几类后台请求
- 内置 `MPV` 新增的启动期缓存、回看缓冲、`demuxer thread` 和 `fast profile` 调优也都发生在本地播放器参数层，不会引入新的网络协议；它们只是在已有播放地址上改变本地缓冲和解码策略
- 本地 `ISO` 走 `dvd-device / bluray-device`、远程 `ISO` 回退普通直开，也只是既有播放地址上的本地打开方式切换，不会引入新的服务端协议
- 详情页资源信息区切换播放器只会把本地默认播放器设置写回 `SettingsController`，不引入新的网络请求
- 从详情页进入的 `/detail-search` 只是复用现有搜索页并补上返回工具栏与无转场，本身不新增新的搜索接口
- 人物作品卡片右上角的题材/类型标签来自 `TMDB` 人物作品结果里的 `genre_ids` 本地映射，不额外请求详情接口
- 页面级 `RetainedAsync` 会优先复用最近一次已完成的详情 / 人物作品结果，因此切页返回或播放结束回到页面时，不会因为保留态本身新增一次元数据请求

## 1. Android Gradle 代理

如果当前网络必须经过代理，可以把下面这些配置放到 `android/local.properties`。这个文件已被忽略，不会提交到仓库。

```properties
sdk.dir=C:\\Users\\yourname\\AppData\\Local\\Android\\sdk
flutter.sdk=C:\\dev\\flutter

systemProp.http.proxyHost=127.0.0.1
systemProp.http.proxyPort=7890
systemProp.https.proxyHost=127.0.0.1
systemProp.https.proxyPort=7890
systemProp.http.nonProxyHosts=localhost|127.*|10.*|192.168.*|*.local
```

`android/settings.gradle.kts` 会在初始化阶段把这些 `systemProp.*` 转成 JVM / Gradle 系统属性，这样插件解析和依赖下载都能吃到代理。

## 2. Flutter 镜像脚本

PowerShell 下推荐使用包装脚本运行 Flutter：

```powershell
.\scripts\flutter_with_mirror.ps1 pub get
.\scripts\flutter_with_mirror.ps1 run -d windows
.\scripts\flutter_with_mirror.ps1 -UseOfficialSource pub get
.\scripts\flutter_with_mirror.ps1 -ProxyUrl http://127.0.0.1:7890 pub get
```

脚本行为：

- 优先从 `android/local.properties` 的 `flutter.sdk` 查找本机 Flutter
- 再回退到常见路径或 `PATH`
- 默认临时设置：
  - `PUB_HOSTED_URL=https://pub.flutter-io.cn`
  - `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`
- 会把 `NO_PROXY` 设为 `localhost,127.0.0.1`
- 传入 `-ProxyUrl` 时会同时设置 `HTTP_PROXY / HTTPS_PROXY`

如果你更希望全局生效，也可以把上面两个 Flutter 镜像环境变量直接配到自己的终端或系统环境里。

## 3. MuMu 模拟器连接

如果 MuMu 已经启动，但 `flutter devices` 里看不到它，先运行：

```powershell
.\scripts\connect_mumu.ps1
```

脚本行为：

- 自动扫描 MuMu 安装目录下 `vms/**/vm_config.json`
- 优先尝试桥接模式暴露的 `guest_ip:5555`
- 再回退到 `127.0.0.1:host_port`
- 成功后会直接输出 `adb devices` 结果，随后再运行 `flutter devices` 或 `flutter run -d <device-id>`

如果 MuMu 不在默认目录，也可以显式传入根目录：

```powershell
.\scripts\connect_mumu.ps1 -MuMuRoot "D:\Program Files\Netease\MuMu"
```

## 4. Web 开发代理

仓库里还带了一个 Web 调试脚本：

```powershell
.\scripts\run_web_with_proxy.ps1
```

这个脚本会：

- 启动 `tool/web_dev_proxy.dart`
- 默认在 `8787` 端口提供本地代理
- 用 `flutter run -d edge` 启动 Web
- 通过 `--dart-define=STARFLOW_WEB_PROXY_BASE=http://127.0.0.1:8787` 把代理地址注入应用
- 当前脚本内置了本机 `Flutter` 与 `JAVA_HOME` 路径，换机器时通常需要先按自己的环境调整

适合本地 Web 调试时统一转发部分请求。

## 5. Android 命令行环境补齐

如果你在类 Unix 环境里补 Android 命令行工具，可以用：

```bash
./scripts/complete_android_setup.sh
```

脚本会：

- 检查 `JAVA_HOME`
- 接受 Android SDK licenses
- 安装 `platform-tools`
- 安装 `platforms;android-35`

执行完成后，按脚本提示继续跑 `flutter doctor` 和 `flutter build apk --release` 即可。

## 6. 实用建议

- Android 构建优先先确认 `android/local.properties` 里的 `sdk.dir` 和 `flutter.sdk`
- 如果 `flutter test` 或 `flutter pub get` 很慢，优先先试镜像脚本
- 如果 MuMu 已经开着但 `flutter devices` 仍然看不到模拟器，先运行 `.\scripts\connect_mumu.ps1`
- Web 调试需要代理时，优先用 `scripts/run_web_with_proxy.ps1`
- 需要切回官方源时，用 `-UseOfficialSource`
- TV 安装包默认用 `.\scripts\build_tv_apk.ps1` 生成，并直接输出到桌面
- `build_tv_apk.ps1` 内部固定使用 `flutter build apk --release --android-skip-build-dependency-validation`，因为当前 TV 分支仍明确保留 `Android 6.0 / API 23` 兼容目标
- `build_tv_apk.ps1` 只会在显式传入 `-SettingsJsonPath` 时临时嵌入配置 JSON
- 当前 TV 显示版本号只保留标准三段式 `主版本.月份.序号`
- 当前 Release APK 启用了 `v1 + v2` 签名，兼容老一些的电视安装器
- 如果 TV 端覆盖安装失败，优先检查设备里是否已经装过其他签名的旧版 `com.example.starflow`；当前包仍使用本机 debug keystore 签名，这种情况通常需要先卸载旧包再安装
- Windows 安装器默认用 `.\scripts\build_windows_installer.ps1` 生成，并直接输出到桌面
- 这条脚本会先执行 `flutter build windows`，再调用 Inno Setup 生成单个安装器
- 当前脚本会优先在 `E:\Program Files (x86)\Inno Setup 6\ISCC.exe`、`E:\Program Files\Inno Setup 6\ISCC.exe`、`C:\Program Files (x86)\Inno Setup 6\ISCC.exe`、`C:\Program Files\Inno Setup 6\ISCC.exe` 查找 Inno Setup
- Android TV 的 `设置 -> 配置管理` 已切换为局域网传输模式，不再依赖系统目录 / 文件选择器
- 打开后电视会显示访问码、端口和本机地址，手机连同一网络即可直接上传或下载配置
- 关闭传输弹窗后，临时传输服务会立刻停止
- Web 端的 `设置 -> 配置管理` 会直接下载当前配置 JSON，或选择本地 JSON 立即导入覆盖，不需要额外的目录权限或应用私有路径
- iPhone / iPad 的 `设置 -> 配置管理 -> 导出当前配置` 会直接打开系统文件导出器，可保存到“文件 / iCloud / 本机其他位置”
- iPhone / iPad 的配置导入继续走系统文件选择器，不需要手填应用私有目录路径
- 如果要管理夸克当前保存目录或删除目录内文件，先确认夸克 Cookie 仍然有效
- 当前目录删除走夸克回收站语义，不是应用侧永久粉碎
- 如果启用了“同步删除夸克目录”，命中已选 `WebDAV` 监听目录的删除成功后还会继续请求一次夸克目录删除接口；同样走回收站语义
- 如果 `WebDAV` 删除在服务端回了 `2xx`，但父目录复查仍能看到目标文件，应用会把它当作删除失败处理，避免只删本地索引或只清本地缓存

## 7. 在线元数据相关请求

当前仓库除了依赖下载，还会在运行期访问这些在线元数据 / 图片服务：

- `TMDB`：标题匹配、人物作品、`poster / backdrop / still / profile / logo` 图片与 `TMDB` 评分
- 其中人物头像使用 `profile`，详情页公司 Logo 使用 `production_companies.logo_path`；当前不再把 `networks` 当作公司 Logo 展示
- `WMDB`：中文资料、豆瓣 / IMDb 评分标签与外部 ID 补全
- 豆瓣：兴趣、推荐、片单、轮播等发现内容

`TV` 模式下新增的这些交互也会继续命中同一批网络能力：

- 首页 `Hero` 和详情页会根据屏幕横竖方向切换横版 / 竖版 artwork
- 首页 `Hero` 对信息不全且没有已刷新成功 / 失败标记的条目，会在启动后的后台做一次 best-effort 元数据刷新；刷新结果和状态会写回本地详情缓存，避免应用每次启动重复请求
- 详情页人物关联影片页会访问 `TMDB` 人物作品接口
- 人物作品卡片右上角的类型角标直接复用同一批作品结果里的 `genre_ids`，不会为了标签再额外请求作品详情
- 人物作品页里的排序与类别筛选都基于已经拿到的人物作品结果在本地完成，不额外追加请求
- 搜索页最近搜索词和来源记忆保存在本地，不新增服务端依赖
- 搜索页顶部来源按钮现在只是统一了本地容器高度与通用按钮样式，不涉及新的搜索接口或筛选协议
- 页面焦点居中滚动属于本地滚动与焦点管理，不依赖额外接口
- 设置编辑页的 TV 文本弹窗只在本地写回控制器，不额外请求服务端
- 配置管理页会在局域网内临时开放一个仅当前会话有效的 HTTP 地址，用于配置上传和下载

开发联调时如果这些服务需要代理，除了构建代理外，还要确认应用运行环境本身能访问外网。

如果 TV 端局域网传输页已经弹出，但手机仍然无法访问，优先检查：

- 手机和电视是否连接到同一个局域网，且路由器没有开启 AP 隔离 / 客户端隔离
- 电视端当前显示的 IP 是否是可访问的局域网 IPv4 地址
- 设备或系统是否限制了明文 HTTP 局域网访问
- Android TV 构建是否已经包含 `INTERNET`、`ACCESS_NETWORK_STATE` 与明文流量支持

和元数据最直接相关的本地设置有：

- `设置 -> 元数据与评分 -> TMDB Read Access Token`
- `设置 -> 元数据与评分 -> 启用 TMDB 自动补全影片信息`
- `设置 -> 元数据与评分 -> 启用 WMDB 自动补全影片信息`
- `设置 -> 元数据与评分 -> 详情页自动匹配本地资源`
- `设置 -> 元数据与评分 -> 匹配来源`

如果详情页图片、评分或人物关联影片页为空，优先先检查：

- `TMDB Read Access Token` 是否已填写
- 当前网络或代理是否能访问 `api.themoviedb.org` 与 `image.tmdb.org`
- `WMDB / 豆瓣` 相关站点是否被本机网络策略拦截

和手动元数据更新相关的当前行为：

- 详情页“手动更新信息”会无视当前是否已有标题、简介、图片或外部 ID，直接重新搜索在线元数据
- 只要搜索命中，当前详情缓存就会被命中结果直接覆盖
- 手动索引管理页在应用匹配结果时，也会把 `IMDb ID` 和 `TMDB ID` 一并写回本地索引与详情缓存
- 详情页评分标签会在本地按来源归一去重；`豆瓣 / IMDb / TMDB` 各最多保留一条，这一步只影响缓存合并与展示，不新增网络请求
- “匹配来源”会直接限制详情页本地资源匹配时实际访问的 `Emby / WebDAV / Quark` 来源；如果没有单独勾选，则默认使用全部已启用来源
- 删除某个已匹配 `WebDAV` 资源后，详情缓存只会精确失效这条资源相关的本地匹配关系；影片本身的在线详情信息和其他候选资源不会因为这次删除被整批清空
- 如果详情缓存里恢复到的是剧集下的某个单集或文件资源，页面仍会保留原来的剧集结构上下文；这一步直接复用本地缓存，不需要额外发请求去重建季/集结构

和搜索来源相关的当前行为：

- `设置 -> 搜索服务 -> 搜索来源` 会直接限制搜索页实际参与执行的本地媒体源与在线搜索服务
- 这里的本地媒体源现在包括 `Emby / WebDAV / Quark`；其中 `Quark` 只会在已经选定根目录后参与搜索
- 如果没有单独勾选任何搜索来源，则默认使用全部已启用来源
- 如果保存的来源 ID 已失效，则会自动回退到全部已启用来源
- 搜索页内本地记住的来源勾选只是全局搜索来源范围内的二次筛选，不会额外产生新的请求

## 8. 在线字幕相关请求

当前应用内在线字幕链路的要点：

- 在线字幕来源由 `设置 -> 播放 -> 字幕` 统一控制；当前支持 `ASSRT / OpenSubtitles / SubDL`
- 详情页内联字幕搜索、独立字幕搜索页和播放器页里的“在线查找字幕”复用同一个仓库实现
- 结构化搜索会优先基于本地文件路径、文件哈希、文件大小、`IMDb ID / TMDB ID`、季集号、年份和标题生成查询请求，并在应用内先下载验证；只有可直接挂载的 `SRT / ASS / SSA / VTT` 或可解压 `ZIP` 结果才会回到 UI
- 结构化源当前会按来源分别访问：
  - `ASSRT API`：`https://api.assrt.net/v1/sub/search`、`/detail`
  - `OpenSubtitles`：`https://api.opensubtitles.com/api/v1/login`、`/subtitles`、`/download`
  - `SubDL`：`https://api.subdl.com/api/v1/subtitles`
- `ASSRT` Token 当前保存在设置页；未填写时不会访问 API，而是直接走网页搜索
- `OpenSubtitles` API Key 当前通过 `--dart-define=STARFLOW_OPENSUBTITLES_API_KEY=...` 注入；账号密码保存在设置页
- `SubDL` API Key 当前直接保存在设置页
- `ASSRT` 网页链路当前会在两种情况下访问 `https://assrt.net/sub/`：
  - `ASSRT` 已启用但未填写 Token
  - `ASSRT` 已填写 Token，且设置允许网页回退，同时 API 没有产出可用结果
- `ASSRT` 网页下载当前仍直接请求站点返回的下载地址
- 详情页只有在已经拿到可播放目标且手动点击“搜索字幕 / 刷新字幕”时才会发起搜索，并且最多保留 `10` 条已经验证可自动加载的结果；独立字幕搜索页进入后也只会预填查询词，不会自动发请求
- `ASSRT` 网页查询会按站点自动做短查询 fallback，例如把 `片名 + SxxEyy`、`片名 + 年份` 逐步回退为更短的片名
- `ASSRT` 如果返回站点错误页，会直接按来源失败处理，不再把错误页误判成“0 结果”
- 结构化验证通过后的字幕会缓存到临时目录 `starflow/validated_online_subtitles`
- `ASSRT` 网页下载后的字幕会缓存到应用支持目录下的 `starflow-subtitle-cache`
- 如果某条字幕之前已经验证或下载过，再次选择时会优先复用本地缓存，不再重复下载
- 如果在线字幕来源被全部关闭，则不会发起这类请求
- Android `TV` 从原生播放器进入独立字幕搜索页时，会保留当前 `query / title / input`，因此后续手动搜索会沿用当前片名或剧集搜索词，不会再以空查询打开

## 9. 品牌资源导出

当前品牌资源导出不走 Flutter 构建流程：

```powershell
C:\anaconda3\python.exe tool\generate_brand_assets.py
```

这条命令依赖：

- 本机可用的 Microsoft Edge
- `C:\anaconda3\python.exe`
- `Pillow`

当前脚本会优先使用：

- `assets/branding/starflow_icon_master.svg` 程序化生成外部 App Icon 统一母版
- `build/brand_assets/app_icon_raw_capture.png` 保存从矢量母版直接导出的高倍基准图
- `assets/branding/starflow_launch_logo.png` 作为启动页首帧图标输出目标
  当前输出为透明底主图案，不复用外部 app icon 方形底板
- `android/app/src/main/res/drawable-nodpi/launch_logo.png` 作为 Android 启动页主图输出目标
- `docs/starflow_tv_banner.html` 生成 TV Banner
- `build/brand_assets/starflow_app_icon_master.png` 作为各平台分发缩放前的统一母版

补充说明：

- 这条链路主要依赖本地文件与本机浏览器，不依赖在线元数据服务
- 外部 App Icon 已不再依赖 HTML 截图，当前以 `svg` 母版程序化导出
- Android 启动器小图标与 TV 横幅里的小方形 Logo 共用同一份矢量源
- 小尺寸图标不再额外锐化，避免星星周边出现黑色描边
- TV Banner 仍然依赖本机 Microsoft Edge 无头渲染 `docs/starflow_tv_banner.html`
- Android 启动页主图与 iOS LaunchImage 当前都只保留主图案本身，不再显示方形底板
- 如果后续换了外部 Logo 设计，只需要重新执行一次脚本，不要手工逐个平台替换
- 当“详情页自动匹配本地资源”关闭时，进入详情页不会自动触发本地资源匹配，只能手动点击“重新匹配资源”
- 如果详情页已经恢复到已匹配资源，重新进入时也不会再次自动匹配本地资源
- 本地资源手动匹配采用并发搜索；某个源先返回时会先展示该结果，但其余搜索源仍会继续完成
- 如果一次手动匹配命中多个本地资源，候选列表和当前选中项也会一并写入本地详情缓存
- 如果这些候选里存在多个可播放文件或来源，当前选中的“播放版本”也会一起写入详情缓存；再次进入时优先直接恢复本地选择，不新增额外请求
- 如果这些候选里存在多个可直接播放的文件或来源，详情页会把它们作为“播放版本”展示；`movie` 和单集等叶子项都走这条本地切换路径，不新增额外网络请求
- 外部 ID 强匹配只要求任一已知 ID 命中；详情页展示的命中原因会按实际命中的 `IMDb / TMDB / 豆瓣 / TVDB / Wikidata` 组合输出，不表示必须全部同时命中
- 豆瓣等在线详情如果此前已经缓存过本地资源命中结果，重新进入详情页时会直接复用缓存中的资源状态、播放信息和多候选资源选择状态
- 如果恢复到的本地命中项本身是单集或文件，详情页仍会继续保留剧集结构目标和季/集浏览区；这是本地缓存恢复行为，不新增额外网络请求
- 退出详情页时，当前页的本地资源匹配会话会立刻失效；未启动的后续来源任务不会继续执行
