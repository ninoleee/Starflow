# Starflow

`Starflow` 是一个已经可运行的跨平台个人影音入口，基于 `Flutter` 同时覆盖 `iOS / Android / macOS / Windows / Linux / Web`。

它把下面几类能力放进同一个应用里：

- 本地媒体源：`Emby`、`WebDAV`、`Quark`
- 内容发现：豆瓣兴趣、推荐、片单、首页轮播
- 聚合搜索：本地资源、`PanSou`、`CloudSaver`
- 播放：内置 `MPV`、App 内原生播放器容器页、系统播放器
- 入库联动：夸克保存、`SmartStrm` Webhook、自动增量刷新索引
- 本地持久化：设置、详情缓存、图片缓存、`WebDAV` 元数据索引

## 当前状态

- 仓库不是原型或纯骨架，主流程已经连通
- App 使用 `Riverpod + GoRouter + media_kit`
- 默认是深色主题
- Android 会识别 `TV` 设备，并切到更适合遥控器焦点操作的导航和设置交互
- `TV` 模式当前已经补齐左侧菜单、默认焦点、焦点记忆、搜索历史、媒体库分页和播放器快捷操作等基础体验
- `TV` 页面里的可聚焦控件会尽量保持在屏幕上下的中间区域，长列表会随焦点自动滚动，减少遥控器连续翻页时的跳跃感
- 搜索、首页、媒体库、详情、设置等主要页面已经补齐统一的 `TV` 焦点边界和“按上回到页头主入口”路径，避免焦点卡在中部列表或横向区块里
- `TV` 详情页的 `Hero` 主操作、季标签和剧集卡片已经补齐显式方向焦点规则：左右默认停留在同一条水平操作带里，剧集卡左右切换时优先停留在上半部分播放区，只有主动按下才会进入下半部分简介/详情区
- 桌面端首页分类海报流、详情页剧集横排和剧照横排已经补齐和 `Hero` 一样的左右翻页按钮，鼠标可以直接点击切换到前一屏或后一屏内容
- `TV` 端配置管理已经改成局域网传输模式，打开后会显示本机地址，手机连同一网络即可直接上传或下载配置 JSON
- iPhone / iPad 上的配置导出已改成系统文件导出器，点击后会直接弹出系统保存面板，可保存到“文件 / iCloud / 本机其他位置”
- Web 端配置管理已支持浏览器直接下载当前配置 JSON，也可以选择本地 JSON 导入并覆盖当前配置
- 设置页已加入“高性能模式”开关，所有客户端开启后都会关闭磨砂/模糊背景、菜单栏自动隐藏、Hero 全屏背景图与通用阴影，把首页 Hero 固定为静态单卡海报样式、导航切换改成静态、详情页大图区进一步瘦身，并继续偏向硬解与轻量字幕/叠层；相关子开关会在设置页直接禁用，避免出现“可改但不生效”
- 设置区的大部分二级页现在已经统一到同一套全屏编辑骨架、工具栏按钮、操作按钮、选择条目、开关条目和展开区块，`TV / 触屏` 不再各自维护两套明显不同的视觉与交互
- 进入播放器后，当前播放会话会直接切到“播放优先”模式，并进一步暂停一部分非播放 UI 工作：
  - 隐藏标签页的 `Ticker / Hero / Pointer` 交互
  - 首页 `Hero` 的后台补数
  - 详情页自动补元数据与本地资源匹配启动
  - 隐藏页面里的网络图片继续发起加载
- 非 `TV` 的内嵌 `MPV` 现在使用更轻的官方式 Material 播放叠层：顶部去掉额外阴影/装饰，底栏只保留 `Material + IconButton + Slider + Text` 这组基础控件；窗口态只允许点击呼出控件，音量/字幕/音轨统一收进“更多”播放设置，支持的平台会继续显示 `PiP / AirPlay` 入口
- Windows 的内置 `MPV` 在打开新会话前会串行等待上一实例完成 `pause -> stop -> dispose`，并把退出页、切新片源、关闭后台播放等入口统一收敛到同一套清理流程，尽量避免叠音、退出后残留后台播放和全屏退出时的销毁异常
- 内置 `MPV` 现在已补上 `ISO` 直开支持：本地文件、`file://` 与局域网路径会优先走 `dvd-device / bluray-device`，远程 `ISO` 则退回普通媒体打开，避免把远程地址误当设备源
- 播放 trace、字幕搜索 trace 默认关闭，内置 `MPV` 日志级别也已压到 `error`

### 近期架构与性能收口（2026-04）

- 首页模块装配现在拆成 `_homeSectionSeedProvider` 抓取层 + `homeSectionProvider` 缓存装饰层；详情缓存 revision 更新时只会重做轻量合并，不会让首页整轮重新抓取来源或豆瓣数据
- 首页普通模块已经改成按 section 独立订阅；`Hero` 当前项、翻页按钮和指示状态也收敛到局部监听，切换时不再带动整页 `setState`
- 首页 `Hero` 的后台补数现在增加了列表快照去重与预取协同；同一批条目在首次进入和前后台切换时不会重复排队补数
- 首页 presentation 已继续拆成页面编排层 + Hero/section 子树；`home_page.dart` 主要保留页面级状态、焦点和 section 装配，`home_page_hero.dart` 收口 Hero / pager / artwork，`home_page_sections.dart` 收口 section slot / shell / carousel / loading 这组通用展示块
- 首页 application 已继续拆成 `HomePageController` 主编排、`home_controller_models.dart` 视图模型和 `HomeFeedRepository` 数据装配层，`home_controller.dart` 主要保留 controller + provider wiring
- 首页与媒体库读取详情缓存时已经统一切到批量读取接口；豆瓣列表、最近播放、普通海报流和轮播都会复用同一条批量缓存合并链路
- 页面级异步状态继续统一到 `RetainedAsyncController / resolveRetainedAsyncValue`；详情、媒体库、人物作品等页在 inactive / 回前台 / 播放让路场景下会优先保留最近一次已解析结果
- 详情页、媒体库、人物作品页与搜索页在页面失活时，现在优先取消当前会话或刷新任务，不再无条件失效成功缓存，返回页面时会减少重复 loading 和重复请求
- 搜索页增加了空关键词短路、批量 UI 提交，以及 `CustomScrollView + SliverList` 结果懒加载；多来源结果仍然并发返回，但不会再每个来源一回来就全量排序并刷新整页
- 详情页“资源信息 / 字幕 / 播放版本”这组高频变化区已经改成局部 `ValueListenableBuilder`，搜索字幕、切换字幕和资源匹配进度不再带动整页重建
- 详情页 presentation 继续拆分成 `detail_page_providers.dart`、`detail_hero_section.dart`、`detail_resource_info_section.dart`、`detail_subtitle_section.dart` 等入口；`media_detail_page.dart` 主要保留页面级会话、回调编排和各 section 装配
- 图片缓存 identity 已升级成 `URL + headers`，并增加磁盘 metadata、`30` 天过期、stale fallback 与双阈值内存淘汰；同一张候选图的解析与尺寸分析现在也会在组件间共享同一条 future，减少同屏重复拉图和重复解码
- 页面背景 glow、桌面横向翻页按钮和海报卡片排版都已收口到更轻的重绘边界；滚动和焦点切换时只刷新真正变化的局部区域
- `AppSettingsPerformanceX` 现在提供统一的 `effective*` 性能派生策略；路由、导航壳、首页 Hero、详情页和播放器都会按同一套有效策略决定是否启用动画、磨砂、自动隐藏和轻量叠层
- 播放启动链已经收口到 `PlaybackStartupCoordinator / PlaybackTargetResolver / PlaybackEngineRouter / PlaybackStartupExecutor`；进入播放器时也会更早切到“播放优先”模式，尽快压住首页 Hero 补数、详情自动补元数据和隐藏页图片加载
- 播放页 presentation 已继续收口：`player_page.dart` 主要保留页面壳、状态字段和顶层装配；`widgets/player_page_platform_session.part.dart`、`player_page_startup_mpv.part.dart`、`player_page_runtime_actions.part.dart`、`player_page_controls.part.dart` 负责平台会话、启动/MPV、运行期动作和播放器控制编排；`player_mpv_controls_overlay.dart`、`player_playback_options_dialog.dart`、`player_playback_overlays.dart`、`player_playback_dialogs.dart`、`player_tv_playback_widgets.dart` 负责播放器 UI 子树
- `TV` 播放页的控制层状态已收口到单一 notifier，减少多层 `StreamBuilder` 套娃造成的重复 rebuild
- `NasMediaIndexer` 已按 `refresh_flow / storage_access / indexing / grouping / refresh_support` 收口成多 `part` 文件；主文件已压到约 `1k` 行以内，便于后续继续推进 isolate 化、增量查询和 source/collection/enrichment 并发预算
- `PlaybackMemoryRepository` 现在使用单调递增的 `updatedAt` 生成策略，避免 Windows 或高频保存场景下“最近播放”因同毫秒写入而出现不稳定排序

## 主导航

当前一级导航是：

- 首页
- 搜索
- 媒体库
- 设置

独立路由页面包括：

- 启动页
- 首页编辑器
- 首页模块完整列表
- 分区内容页
- 详情页
- 人物关联影片页
- 元数据索引管理页
- 播放器页

## 主要能力

### 媒体源

#### Emby

- 登录并保存会话信息
- 选择分区并读取分区内容
- 读取媒体详情和播放信息
- 支持电影、剧集、季、集等层级
- 与首页、搜索、详情、播放链路打通

#### WebDAV

- 选择根目录并读取目录结构
- 以“本地索引优先”的方式服务首页、媒体库和详情页
- `WebDAV` 过程日志默认不开启；需要排查时可临时修改 `lib/core/utils/webdav_trace.dart` 接入输出
- 扫描时支持：
  - 目录结构推断
  - 本地 `NFO / poster / fanart / banner / clearlogo / extrafanart`
  - `streamdetails`
  - 文件名和目录名里的 `IMDb ID`
  - 会从标题里的 `{tmdbid-95903}`、`{tvdbid-...}`、`{imdbid-...}`、`{doubanid-...}` 等嵌入式外部 ID 标签中剥离展示标题与搜索词，避免目录标签进入系列名或分组名
  - 会忽略 `分段版 / 特效中字 / 会员版 / 导演剪辑版 / 清晰度 / 音轨 / 字幕` 这类包装目录或版本说明，避免把它们误识别成剧名
  - 支持单独配置“顶层推断目录”：只在目录结构推断里，识别到剧文件或季目录后向上推断剧名时生效；命中这里填写的顶层目录名后会立刻停止继续向上，改用下一级已推断目录，没有目录时退回文件名
  - 支持单独配置“剧集只按剧名层级搜刮”：仅在目录结构推断开启时生效；开启后，在线搜刮只使用目录推导出的剧名，不再把季名或集名拼进查询，也不再按单集继续请求剧照
  - 综艺/节目文件名会额外识别 `第X期`，以及 `01 会员版` 这类“集号 + 版本说明”形式
  - 文件名轻量媒体信息兜底
- 支持把多集文件聚合为 `剧 -> 季 -> 集`
- 目录名里如果能识别出明确季号，例如 `Season 1`、`S02`、`第2季`、`Stranger.Things.S02.2160p.BluRay.REMUX`，会直接把这一层当作季目录
- 对 `2.巴以 / 5.美国 / 9.韩国` 这类“数字 + 标题”的专题目录，会额外要求同级里存在多个同类兄弟目录，避免把普通数字目录误判成季
- 一旦当前层被识别为季目录，上一级目录就会作为剧名；像 `怪奇物语/Season 1/Season 2`、`怪奇物语/Stranger.Things.S02.2160p.BluRay.REMUX` 都会把 `怪奇物语` 当剧名
- 如果路径里已经确认存在显式季目录，即使当前只有一季，也会继续保留“季”这一层，不再直接拍平成集列表
- 支持排除目录关键字
- 支持增量更新和强制重建索引
- 增量更新会遍历“当前选中的分区范围”来判断变更，不会越过到其他分区
- sidecar / 在线补元数据只会对增量项继续执行，不会对未变化条目重复刮削
- 仅在“当前作用域索引为空”时，才会在后台调度一次自动全量重建；读链路本身不再同步等待这次重建
- 支持从媒体库直接删除 `WebDAV` 文件或目录；删除文件时会优先使用真实资源 `URI` 发起 `DELETE`，成功后还会再确认远端文件已经消失
- 删除成功后，本地只会精确移除当前资源或当前目录作用域相关的索引、详情缓存和匹配关系，不再整源清空
- 网络存储里开启“同步删除夸克目录”并选中监听的 `WebDAV` 目录后，只要删除命中了这些目录下的文件或文件夹，就会到当前夸克保存目录里同步删除匹配到的影片或剧集目录
- 支持从详情页进入 `建立/管理索引`，手动修正搜索词、年份和匹配结果

#### Quark

- 复用 `设置 -> 网络存储 -> 夸克与 STRM` 中保存的全局 `Cookie`
- 选择夸克目录后，可直接把该目录作为本地媒体源接入首页、媒体库、搜索和详情页匹配
- 可继续选择该目录下的子目录作为分区范围
- 索引与在线搜刮链路复用 `WebDAV` 同一套外部存储规则，支持目录结构推断、本地刮削/NFO、顶层推断目录，以及“剧集只按剧名层级搜刮”
- 详情页会在真正播放前按需解析夸克直链，并补齐对应请求头

#### 已选分区作用域

`Emby`、`WebDAV` 与 `Quark` 都围绕“已选分区”工作：

- 媒体库只显示已选分区
- 首页来源分区模块只列出已选分区
- 本地搜索只搜索已选范围
- 手动匹配与刷新也只在已选范围内执行

### 首页与豆瓣

- 首页是模块化装配，不是固定版式
- 支持添加、启用、删除、排序首页模块
- 支持 `Hero` 模块：
  - 开关
  - 数据来源选择
  - `normal / borderless` 展示方式
  - 是否启用全屏背景图
  - 可切换使用 Logo 形态标题
  - 会根据当前屏幕横竖方向和可用素材自动优先选择横版或竖版图片；横屏优先横版，竖屏优先竖版，只有单张图可用时会直接按海报布局展示
  - `Hero` 当前项、翻页按钮和指示状态都已经改成局部监听，切换时不再带动首页整页重建
  - 首次进入首页时，如果 `Hero` 条目信息不全且还没有已刷新成功或失败的标记，会在后台 best-effort 补一次信息
  - 高性能模式开启时，会强制改成静态单卡、无阴影，并关闭翻页按钮、指示点和全屏背景图
- 除 `Hero` 外，首页普通横向海报流在桌面端也会显示统一的左右切换按钮，便于鼠标快速翻到下一屏
- 支持的模块类型：
  - 最近新增
  - 最近播放
  - 指定媒体源分区
  - 豆瓣 `我想看 / 我在看 / 我看过 / 随机想看`
  - 豆瓣个性化推荐
  - 豆瓣片单
  - 豆瓣首页轮播
- 最近播放模块直接读取本地播放记忆：
  - 展示最近播放内容和续播进度
  - 电影会显示电影名；剧集会优先显示剧集总名，单集信息继续放在副标题和续播进度里，不再把具体集名当主标题
  - 会优先尝试从本地详情缓存补海报
- 首页会优先合并本地详情缓存，减少重复补元数据
- 首页模块装配当前分成“seed section 构建 + 批量详情缓存合并”两段；普通海报流、最近播放、豆瓣列表和轮播都会复用同一条缓存合并链路；详情缓存更新时只会重做这一层装饰合并，不会让首页整轮重新抓取
- 首页 presentation 当前也已经拆层：`home_page.dart` 主要保留 retained async、Hero 选择同步、预取和页面级焦点编排；`home_page_hero.dart` 负责 Hero 视觉/分页/焦点；`home_page_sections.dart` 负责 section slot、背景 shell、carousel、loading/empty 和 view-all 这组通用展示块
- 首页 `Hero`、背景图和海报图会按实际显示尺寸传递 decode 尺寸，移动端 `PageController` 也做了边界稳定化，降低首屏切换和大图解码抖动
- 如果条目已经刮削过或已经关联到本地详情缓存，首页 `Hero` 和各类海报卡片会优先显示刮削/关联后的标题；没有时才回退到原始标题或来源标题

### 详情与元数据

- 详情页顶部以背景图为主，不再重复展示海报；Logo、标题、评分、导演、演员、技术信息等在同一视觉区域内组织
- 高性能模式开启时，详情页顶部大图区会进一步压缩高度和信息密度，减少大面积背景叠层
- 详情页会展示背景图、剧照、分集截图、人物头像、公司 Logo 等素材
- 剧集支持选季、横向浏览集列表和直接播放
- 单集卡片的图片区继续直接播放；图片下方的简介区域可进入单集详情页，并查看该集关联资源与关联字幕
- 详情页里的剧集横排和剧照横排在桌面端会显示统一的左右切换按钮，和首页 Hero 的翻页方式保持一致
- `WebDAV` 条目默认优先使用索引期结果，不在详情页重复做在线刮削
- 详情页是否自动匹配本地资源由 `设置 -> 元数据与评分 -> 详情页自动匹配本地资源` 控制，默认关闭；关闭后只会在手动点击“重新匹配资源”时开始匹配
- 详情页本地资源匹配还可通过 `设置 -> 元数据与评分 -> 匹配来源` 限制到指定来源；未单独勾选时默认使用全部已启用的 `Emby / WebDAV / Quark` 来源，已保存来源失效时也会自动回退到全部已启用来源
- 详情页“匹配本地资源”命中 `WebDAV / NAS` 后，会优先采用匹配到的本地资源信息与图片，再用当前详情页已有元数据做补充
- 手动匹配过程中会按搜索源并发执行；只要某个源先命中，详情页就会立即展示结果，但不会打断其他源继续搜索
- 手动匹配命中多个本地资源时，会把整组候选资源和当前选中项一起缓存；再次进入详情页时会恢复资源选择器，不再只剩下一个候选
- 如果剧集详情页恢复到的是某个已匹配单集或文件资源，页面仍会保留剧集结构目标并继续显示“剧集”浏览区，不会因为资源已就绪就整页降成单集详情
- 如果这组候选里存在多个可直接播放的文件或来源，详情页底部会显示“播放版本”；当前不只 `movie`，单集等可播放叶子项也可以在这里切换不同文件
- 如果后续删除了其中某个已匹配本地资源，详情缓存只会剔除这一个候选；其他候选会继续保留
- 如果删除的是当前唯一命中的本地资源，详情页会回退到“无/未匹配”的本地资源状态，但保留影片本身的标题、简介、图片和外部 ID 等详情信息
- 退出详情页时，当前页本地资源匹配会话会立即失效；还没启动的后续来源任务不会继续执行，已经返回的结果也不会再回写当前页面
- 详情页、人物作品页和媒体库页在页面失活时，现在会优先取消当前任务，但不再顺手把成功缓存一起失效；返回页面时会优先复用最近一次结果
- 豆瓣等在线详情页如果已经缓存过本地资源匹配结果，再次进入时会优先复用已缓存的资源状态、来源、播放信息和多候选选择状态，不再退回显示“无”或丢失候选列表
- 详情页、首页和媒体库当前都会优先显示已刮削或已关联后的标题；如果缓存或关联结果里已经有更准确的片名/剧名，就不再继续展示原始文件名、目录名或 seed 标题
- 外部 ID 匹配只要任一可用 ID 命中即可成立；详情页文案会按实际命中的 ID 展示，例如 `IMDb ID / TMDB ID`，不再暗示必须双 ID 同时命中
- 详情页不再在进入时自动搜索字幕；只有已经拿到可播放资源并手动点击资源信息区里的“搜索字幕 / 刷新字幕”时，才会按 `设置 -> 播放 -> 字幕 -> 在线字幕来源` 搜索最多 `10` 条可自动挂载的字幕
- 详情页选中的外挂字幕会和详情缓存一起保存；再次进入详情页时会恢复，后续进入播放时会自动带给内置 `MPV` 与 Android `App 内原生播放器`
- 详情页资源信息区可直接切换播放器，使用和设置页一致的选择列表；修改后会同步写回全局默认播放器
- `WMDB / TMDB / IMDb` 用于补全标题、简介、评分、外部 ID 和 artwork
- 详情页评分标签会按来源归一去重；`豆瓣 / IMDb / TMDB` 各最多保留一条，避免 seed target、本地详情缓存、手动更新信息或自动补全合并后出现两个同来源评分
- `TMDB` 当前已接入 `poster / backdrop / still / profile / logo` 等图片字段；人物头像来自 `profile`，详情页公司 Logo 来自 `production_companies.logo_path`，并展示 `TMDB x.x` 评分；`IMDb` 评分仍由独立补全链路兜底
- 本地 sidecar 信息优先级高于在线补全
- 详情页“手动更新信息”会直接重新搜索在线元数据，并用命中结果覆盖当前详情缓存
- 手动索引管理会直接写回本地索引和详情缓存，不只是一次性页面状态；手动点击搜索并应用结果时，不管本地当前是否已有信息，都会强制搜索并直接替换已命中的字段
- 点击导演或演员头像可打开人物关联影片页，并用与首页一致的海报卡片样式继续浏览；人物作品卡片右上角会显示题材/类型标签，左下角会优先显示 `IMDb / 豆瓣 / TMDB` 等可用评分
- 人物关联影片页支持按年份新到旧 / 旧到新排序，也可以按类别筛选结果
- 图片加载支持候选图回退；`poster / banner / backdrop / extraBackdrop` 其中一张返回 `404` 时，会自动尝试下一张
- 详情页 `TV` 模式会优先把焦点落到主操作按钮，并记住演职员、剧集卡片等上次停留的位置
- 详情页 `TV` 模式下，`Hero` 主操作按钮左右切换会默认留在顶部操作区；剧集浏览区则拆成“季标签一排 / 卡片上半播放区一排 / 卡片下半简介区一排”，左右默认只在当前这一排里移动，不再轻易掉到下方

### 搜索、保存与刷新

- 支持同时搜索：
  - 本地媒体源
  - `PanSou`
  - `CloudSaver`
- 支持多来源并发搜索，结果逐步回填
- 搜索执行范围可通过 `设置 -> 搜索服务 -> 搜索来源` 控制；可分别选择本地媒体源和在线搜索服务，未单独勾选时默认使用全部已启用来源，已保存来源失效时会自动回退到全部已启用来源
- 搜索页顶部的来源按钮、最近搜索按钮与媒体库筛选按钮现在统一复用同一套 `chip` 按钮规格；普通端与 `TV` 端都不会再出现底部被裁掉或高度不一致
- 空关键词会直接短路，不再启动整轮搜索
- 多来源结果会先在页面内聚合，再按短节流批量提交 UI；不会再每个来源一返回就触发一次全量排序和整页刷新
- 支持：
  - 相同链接去重
  - 按网盘类型过滤
  - 过滤词
  - 强匹配
  - 标题长度上限
- 从详情页点“搜索资源”进入时，会复用同一套搜索页，但额外显示返回按钮，并采用无转场切入 / 返回详情页
- 搜索结果可直接打开资源链接
- 夸克资源支持一键保存
- 网络存储页可直接管理当前夸克保存目录
  - 可浏览当前目录和子目录
  - 可单独删除文件或文件夹
  - 可一键清空当前目录
  - 当前删除动作会移动到夸克回收站，不做永久粉碎
  - 可选开启“同步删除夸克目录”：删除命中已选 `WebDAV` 监听目录下的文件或文件夹时，会同步删除当前夸克保存目录里的对应影片或剧集目录
- `TV` 模式会记住上次勾选的搜索来源，并展示最近搜索词，支持遥控器直接重搜；页面内记住的勾选项只会在“设置 -> 搜索来源”允许的范围内生效
- 保存成功后可按配置：
  - 按“STRM 触发等待时间”延迟触发 `SmartStrm` Webhook
  - 按“索引刷新等待时间”延迟自动执行指定媒体源的增量刷新
  - 刷新分区在网络存储里单独选择，默认全选全部可刷新的媒体源

### 播放

- 播放器基于 `media_kit`
- 播放器内核当前支持：
  - 内置 `MPV`
  - App 内原生播放器
  - 系统播放器
- 详情页资源信息区也可直接切换播放器内核，这个选择会和设置页里的全局默认播放器保持同步
- `App 内原生播放器` 现已支持 Android / iOS：
  - Android 使用 App 内原生容器页承载播放，优先追求 TV / 高性能场景下的播放稳定性
  - iOS 使用系统 `AVPlayerViewController` 在 App 内原生全屏播放
- Emby 播放前会补齐真实播放地址和播放源
- Quark 播放前会按需解析真实下载地址，并补齐请求头
- 打开播放时会展示轻量等待态
- 打开播放前会先做一轮轻量启动准备：读取本地续播、按剧跳过规则和启动路由判定，再决定走内置 `MPV`、原生容器页还是系统播放器
- 播放启动链当前已收口到 `PlaybackStartupCoordinator / PlaybackTargetResolver / PlaybackEngineRouter / PlaybackStartupExecutor`，方便把“目标解析 / 启动准备 / 路由判定 / 执行分支”分开测试与演进
- 播放失败最多自动重试 `3` 次
- 可配置最大打开超时时间
- 可配置解码模式：
  - `自动`
  - `硬解优先`
  - `软解优先`
- 可配置默认字幕策略：
  - `跟随片源`：打开视频时按片源默认字幕轨处理
  - `默认关闭`：打开视频时默认不显示字幕
- 播放设置里的字幕相关默认项已收拢到二级页：
  - 默认字幕策略
  - 字幕大小
- 可配置后台播放：
  - 设置中可单独开启或关闭
  - Android 开启后切后台时会进入小窗继续播放
  - iOS 开启后切后台时会继续后台播放音频
  - 关闭后台播放、退出播放器或打开新的内置 `MPV` 片源前，会先清理上一段播放会话；只有明确开启后台播放时才允许继续保留后台音频
- Android 调用系统播放器时优先走原生 `Intent ACTION_VIEW + video/*`
- 桌面端调用系统播放器时会生成临时 `.m3u` 后交给系统默认视频应用
- 内置播放器支持播放内设置：
  - 音量调节
  - 播放速度
  - 音轨切换
  - 字幕轨切换
  - 字幕偏移
  - 加载外部字幕
  - 在线查找字幕
- 非 `TV` 的内置 `MPV` 当前使用 Starflow 自己的轻量播放叠层，而不是 `media_kit` 默认控制条：
  - 首层只保留返回、播放/暂停、进度、全屏和“更多”；音量、字幕、音轨与其他高级播放项统一收进播放设置弹窗
  - 顶部标题栏与底部控制区都收敛成更官方的 Material 轻量样式，去掉额外阴影/装饰；播放设置弹窗也改成 `ListTile / Slider / TextButton`
  - 非全屏 / 窗口态彻底关闭 hover 唤醒，只允许点击显示控件；`PiP / AirPlay` 入口继续按平台能力显示
  - 全屏状态由父级先解析后再以普通 `bool` 传给叠层，避免叠层在销毁阶段反查 inherited fullscreen 状态
  - 竖屏和窗口态仍保持“顶部标题栏 + 底部控制区”的轻量布局，不会把主要控件堆在画面中间
- Windows 的内置 `MPV` 会在下一次打开前串行等待上一实例完成 `pause -> stop -> dispose`，并复用同一套退出清理路径，减少快速切换片源、关闭后台播放或退出全屏时出现叠音与残留后台播放
- Windows 播放链路仍保留 `lib/core/utils/playback_trace.dart` scoped trace，但 `playback trace / subtitle search trace` 默认关闭；需要排查时再临时打开，本地输出也不会上报到服务端
- `TV` 端当前仍保留自定义播放叠层与设置入口：
  - 电视播放分支继续走“首层极简 + 二层高级”的遥控器操作模式
  - 内置 `MPV` 首层只保留播放状态、进度、字幕和音轨快捷入口；菜单键 / 下键进入二层播放设置
  - Android `App 内原生播放器` 首层会隐藏快进快退、外挂字幕、字幕偏移、在线字幕搜索等高级按钮，改由“更多操作”二层菜单承载
  - 原因是当前 `TV` 模式使用 `NoVideoControls`，还没有可直接复用的 `media_kit` 系统式控制条
- `App 内原生播放器` 当前已接入这些能力：
  - 原生控制条和进度条
  - 本地续播记忆
  - 在线查找字幕
  - Android：音轨/字幕轨选择、加载外部字幕、外挂字幕偏移
  - iOS：使用系统原生播放控制，当前不支持字幕偏移
- 播放器页与详情页现在复用同一条应用内字幕搜索/下载链路：
  - 在线字幕来源由设置统一控制，当前已接入 `ASSRT / SubHD / YIFY`
  - 剧集 `SxxEyy` 或电影年份查询在站点命中失败时，会自动回退为更短的片名查询
  - `ASSRT` 如果返回站点错误页，会直接按来源失败上报，不再伪装成“0 结果”
  - `SubHD` 当前只支持应用内搜索结果浏览，不能在应用内直接下载；详情页仍只保留可直接下载且可自动挂载的结果
  - 下载后的字幕会缓存到本地，后续再次选择同一结果时优先复用，不重复下载
- `TV` 模式下，外部字幕选择、在线字幕搜索和部分外部跳转都会优先做失败兜底，避免定制系统或无浏览器环境下直接闪退
- Android `TV` 从 `App 内原生播放器` 进入独立字幕搜索页时，会保留当前搜索词、标题和输入框初值，不再空白打开
- 内置播放器支持按剧绑定的自动跳过：
  - 自动跳过片头
  - 自动跳过片尾
  - 规则只作用于当前剧，其他剧不受影响
- 内置播放器支持本地续播记忆：
  - 电视剧记忆“播到哪一集 + 当前进度”
  - 电影记忆当前进度
  - 最近播放保留 `20` 条
- 首页模块现在也可以直接添加“最近播放”
- 详情页会优先读取本地续播记录，主播放按钮可变成“继续播放”
- 高性能模式开启后，所有客户端都会：
  - 关闭磨砂/模糊背景、Hero 全屏背景图与通用面板阴影
  - 首页 Hero 固定为静态单卡海报样式，关闭翻页按钮、指示点和分页动画
  - 主导航改为静态常驻，不再自动隐藏，也不再做切换/收起动画
  - 详情页顶部大图区会进一步瘦身，减少大面积背景遮罩
  - 压低启动页过渡
  - 更积极偏向硬解，并简化播放器叠层与字幕背景
- 内置 `MPV` 当前还额外做了跨平台统一的启动期性能调优：
  - 按本地 / 远程 / 重码率片源动态调整前向缓冲与回看缓冲
  - 默认开启 `demuxer thread`，并关闭 `interpolation / deband / audio-display` 这类非必要处理
  - 远程流会按 `http/https/ftp` 与 `rtsp/rtmp` 两类场景分别调节 `network-timeout`、`cache-on-disk`、`cache-secs` 与预读参数，降低刚进播放时的抖动
  - 质量预设支持按窗口态 Windows、远程流和重片源做运行期自动降档；只影响当前播放行为，不会反写用户保存的默认设置
  - 高性能模式、`TV` 或重片源 / 高压力场景下会尝试应用更激进的 `MPV fast profile`
  - `TV` 与高性能模式下会进一步简化字幕渲染，降低叠加压力
  - 软解优先且片源较重时，会适度降低解码压力，尽量换取更稳的播放
  - Windows 非全屏轻量叠层已关闭 hover 唤醒，只允许点击显示，并在全屏切换时重置悬浮状态，减少无控件状态下的闪烁
- `ISO` 片源当前对所有内置 `MPV` 打开路径统一生效：本地 `ISO` 优先走设备模式，远程 `ISO` 自动回退直开，避免错误残留 `dvd-device / bluray-device` 选项
- 高性能模式开启后会更积极优先硬解；其中高码率或设备解码压力较大的片源，在 Android TV 上会优先尝试切到 `App 内原生播放器`，再退到系统播放器
- `App 内原生播放器` 目前专注于性能和稳定播放：
  - Android 支持跟随设置选择 `自动 / 硬解优先 / 软解优先`
  - iOS 走系统原生解码链路，当前不提供软硬解切换
  - 两端都不提供完整的应用内高级控制项
- 进入播放页后，会额外做一层“后台工作让路”：
  - 路由层会冻结隐藏分支的动画、Hero 和命中测试
  - 首页与详情页优先只消费已有缓存，不再继续发起这一轮补全任务
  - 隐藏页中的网络图片会停止继续解析和拉取
- 性能模式相关的动画、导航显隐、磨砂效果和轻量播放 UI 现在都由统一的 `effective*` 策略派生，路由层和播放器会按当前有效档位自动切换
- `内置 MPV` 支持跟随设置切换解码模式；`系统播放器` 属于外部应用，解码方式由系统或目标播放器自行决定
- 系统播放器属于外部应用，不能稳定回传播放状态，因此续播记忆仅对内置 `MPV` 和 `App 内原生播放器` 生效
- 自动跳过片头片尾当前仅对内置 `MPV` 生效
- 字幕偏移当前支持：
  - 内置 `MPV`
  - Android `App 内原生播放器` 的外挂字幕
  - iOS `App 内原生播放器` 暂不支持
- `TV` 模式下不再常驻显示右上角遥控器操作文案，菜单键仍可直接打开播放设置

### 设置与运维

- 媒体源管理
  - `WebDAV / Quark` 编辑页支持目录结构推断、本地刮削/NFO、顶层推断目录
  - 可选开启“剧集只按剧名层级搜刮”，让结构推断出来的剧集只按目录剧名在线匹配
- 搜索服务管理
- 搜索来源选择
- 元数据与评分设置
- 本地资源匹配来源选择
- 网络存储设置
  - 夸克默认保存目录
  - 同步删除夸克目录
  - 同步删除夸克目录对应的 `WebDAV` 监听目录
  - 当前夸克保存目录管理与删除
  - `SmartStrm` Webhook、任务名、`STRM 触发等待时间`
  - 自动增量刷新索引的目标媒体源与“索引刷新等待时间”
- 本地存储查看与清理
  - 当前可清理：`WebDAV` 索引、详情缓存、播放记忆、`TV` 搜索历史与来源记忆、图片缓存
- 配置管理支持按平台分支导入 / 导出配置
- Web 端导出会直接触发浏览器下载 JSON；导入会选择本地 JSON 并覆盖当前配置
- iOS / iPadOS 导出会直接打开系统文件导出器，可保存到“文件 / iCloud / 本机其他位置”
- iOS / iPadOS 导入会直接调用系统文件选择器
- 其他支持本地文件访问的 IO 平台继续使用目录 / 文件选择器
- `TV` 模式下改为站内局域网传输
  - 打开 `设置 -> 配置管理 -> 手机传输配置` 后，电视会弹出访问码、端口和局域网地址
  - 手机与电视连接同一网络后，可直接下载当前配置，或上传 JSON 并立即覆盖电视端设置
  - 关闭传输弹窗后，本地临时传输服务会立刻停止
- 播放设置
  - 播放器内核
  - 解码模式
  - 最大打开超时
  - 后台播放
  - 默认倍速
  - 字幕
    - 默认字幕策略
    - 字幕大小
    - 在线字幕来源（当前已接入 `ASSRT / SubHD / YIFY`）
- 首页模块设置
  - `Hero` 当前主要提供来源、`normal / borderless` 展示方式、Logo 标题和背景图这些外显配置
  - 实际横版 / 竖版素材会按屏幕方向和可用图片自动选择；高性能模式开启后，Hero 会固定为静态单卡，并锁定 Hero 背景图等受性能模式接管的子项
- 搜索来源、匹配来源等多选项已统一到同一套复选对话框；`TV / 触屏` 会共用同一套选择逻辑
- `WebDAV` 路径选择页现在带目录结果缓存，减少重复列目录与重复等待
- 可切换透明磨砂效果，降低弱性能设备上的视觉开销
  - 高性能模式开启时会被强制关闭
  - 只有先关闭高性能模式，才可以单独设置这个开关
- 可配置“自动隐藏菜单栏”
  - 普通端关闭后菜单栏会保持常驻；开启后按页面交互自动隐藏
  - `TV` 端开启后，焦点离开左侧菜单栏时会自动收起
  - 高性能模式开启时会被强制关闭，并在设置页里直接禁用
- 首页 Hero 的“全屏背景图”也可单独控制
  - 高性能模式开启时会被强制关闭，并在设置页里直接禁用
- Android TV 模式下，设置首页和部分二级设置页的主要入口与按钮已补齐焦点态，便于遥控器操作
- Android TV 模式下，媒体源、搜索服务、豆瓣账号、网络存储等设置编辑页里的文本项会先以可聚焦条目展示，再进入独立编辑弹窗，避免焦点长期被输入框和系统键盘锁住
- 媒体源、搜索服务、豆瓣账号、网络存储、播放、配置管理等主要设置页，当前都尽量复用同一套页面骨架和按钮类型，减少不同设置页之间的操作差异

## TV 模式

当前 `TV` 模式已经单独做了适配，不只是把触屏页面直接搬到电视上：

- 左侧主导航改成窄栏磨砂透明图标菜单，并支持菜单键随时把焦点拉回侧栏；可按设置决定是否在焦点离开后自动隐藏
- 页面内常用操作统一支持遥控器焦点高亮
- 长页面和长列表里的焦点会尽量保持在视口中线附近，页面会跟随焦点自动滚动
- 顶部主入口、横向列表和底部内容区之间已经补齐统一的上下方向焦点边界；往上可回到页头，往下可继续进入下一个模块
- 首页 `Hero`、搜索结果、媒体库网格、详情页人物 / 剧集卡片支持焦点记忆
- `TV` 焦点记忆不再通过广播式重建传播；焦点视觉态改成更轻量的局部高亮，海报卡的 `outline only` 模式不会再叠加浮动效果
- 详情页 `Hero` 主操作和剧集浏览区额外补了显式方向链：左右优先留在同一水平带里，剧集卡左右切换默认走上半播放区，按下才进入下半详情区
- 搜索页支持最近搜索词和来源记忆
- 媒体库分页按钮支持 `TV` 焦点操作，列表返回后尽量回到上次停留位置
- 播放器保留菜单键直达播放设置等 `TV` 快捷操作，但不再依赖常驻文字提示
- `TV` 播放器可按上临时呼出片名 / 进度叠层，按下或菜单键直达更多播放设置
- 设置编辑页里的文本输入会改走“选择条目 -> 弹窗编辑”流程，避免遥控器焦点被软键盘困住
- 配置管理使用应用内局域网传输，不再依赖系统目录 / 文件选择器
- 多数设置编辑页现在共用同一种标题栏、保存按钮、危险操作按钮和选择条目样式，遥控器在不同设置页之间切换时的学习成本更低

## 本地数据

当前本地持久化大致分成三类：

- `SharedPreferences`
  - 应用设置
  - 详情缓存
    - 当前会缓存详情目标、本地资源匹配候选列表、在线字幕候选列表和当前选中项
    - 首页与媒体库读取详情缓存时会优先走批量读取；同一批 seed target 会复用一次本地 payload 读取，减少重复本地 `I/O`
    - 如果候选里存在多个可播放文件或来源，也会一起缓存当前“播放版本”选择，便于再次进入详情页时恢复到上次选中的版本
    - 对剧集详情页，恢复已缓存的本地资源状态时也会同时保留剧集结构上下文，确保再次进入时还能继续显示季/集浏览
    - 删除 `WebDAV` 资源时只会精确清除当前资源相关的详情缓存关联，不会把整个来源的详情缓存一起清空
  - 播放历史、续播进度、按剧跳过规则
  - `TV` 搜索历史与搜索来源记忆
- 应用支持目录
  - 在线字幕下载缓存 `starflow-subtitle-cache`
  - 详情页与播放器页会复用已下载字幕文件，避免重复下载或重复解压
- `Sembast`
  - `WebDAV` 元数据索引
- 持久化图片缓存
  - 详情页、豆瓣和 `TMDB` 图片复用
  - identity 按 `URL + headers` 区分，避免不同鉴权头误共用缓存
  - 磁盘层带 metadata、`30` 天过期与 stale fallback；内存层按条目数和字节预算双阈值淘汰

`WebDAV` 索引会记录：

- 来源、路径、指纹
- 标题、年份、季集识别结果
- 手动修正后的搜索词和匹配偏好
- `sidecar / WMDB / TMDB / IMDb` 命中结果
- `IMDb / TMDB / 豆瓣` 等外部 ID
- 海报、背景图、Logo、技术信息
- 聚合后的剧集父子关系
- 最终展示用 `MediaItem`
- 如果后续刮削、手动索引管理或详情缓存里已经写入了更新后的标题，首页、媒体库和详情页会优先消费这份标题做展示
- 当前索引实现已拆成多段 helper：`nas_media_indexer.dart` 负责入口与共享小工具，`nas_media_indexer_refresh_flow.dart / nas_media_indexer_storage_access.dart / nas_media_indexer_indexing.dart / nas_media_indexer_grouping.dart / nas_media_indexer_refresh_support.dart` 负责刷新、存储访问、索引计算、分组与并发辅助

## 仓库结构

```text
lib/
  app/        应用壳、路由、主题
  core/       平台、缓存、公共组件、工具
  features/   各业务模块
docs/         架构与开发说明
scripts/      开发脚本
tool/         辅助工具
test/         单元与组件测试
```

`features/` 当前包含：

- `bootstrap`
- `details`
- `discovery`
- `home`
- `library`
- `metadata`
- `playback`
- `search`
- `settings`
- `storage`

## 环境要求

- `Flutter SDK`
- `Dart SDK`
- `Android SDK`
- `Xcode + CocoaPods`，用于 `iOS / macOS`

## 快速开始

安装依赖：

```bash
flutter pub get
```

查看设备：

```bash
flutter devices
```

运行：

```bash
flutter run -d windows
flutter run -d android
flutter run -d ios
flutter run -d macos
```

指定设备：

```bash
flutter run -d <device-id>
```

构建 Android：

```bash
flutter build apk
flutter build apk --release
```

构建 TV 安装包：

```powershell
.\scripts\build_tv_apk.ps1
.\scripts\build_tv_apk.ps1 -SettingsJsonPath "D:\OneDrive\Desktop\starflow-settings.json"
```

构建 Windows 安装器：

```powershell
.\scripts\build_windows_installer.ps1
```

当前 TV 打包规则：

- 默认输出到桌面
- 默认只生成单个 APK
- 不传 `SettingsJsonPath` 时不会嵌入配置
- 传入 `SettingsJsonPath` 时会临时写入 `assets/bootstrap/embedded_settings.json`，打包结束后自动清理
- 内部构建命令会默认附带 `--android-skip-build-dependency-validation`，继续保留 `Android 6.0 / API 23` 的老电视兼容目标
- 文件名为：
  - `starflow-tv-主版本.月份.序号.apk`
  - `starflow-tv-config-主版本.月份.序号.apk`
- 内部版本号会自动递增：
  - 第一段主版本号保留手动控制
  - 第二段是月份
  - 第三段是当月递增序号
  - 每个月第一次打包时第三段自动归 `0`
- 当前显示版本号只保留标准三段式 `主版本.月份.序号`
- 当前 Android TV 构建最低兼容版本为 `Android 6.0 / API 23`
- Release APK 当前启用了 `v1 + v2` 签名，兼容老一些的电视安装器
- 当前 Release APK 仍使用本机 debug keystore 签名；如果电视里装过其他签名的旧版 `com.example.starflow`，覆盖安装会失败，需要先卸载旧版再安装

当前 Windows 安装器打包规则：

- 默认输出到桌面
- 默认只生成单个安装器 `.exe`
- 内部会先执行 `flutter build windows`
- 然后调用 Inno Setup 生成安装器
- 当前会优先在这些位置查找 `ISCC.exe`：
  - `E:\Program Files (x86)\Inno Setup 6\ISCC.exe`
  - `E:\Program Files\Inno Setup 6\ISCC.exe`
  - `C:\Program Files (x86)\Inno Setup 6\ISCC.exe`
  - `C:\Program Files\Inno Setup 6\ISCC.exe`
- 当前安装器文件名为：
  - `starflow-windows-版本号-setup.exe`

## 开发脚本

镜像运行 Flutter：

```powershell
.\scripts\flutter_with_mirror.ps1 pub get
.\scripts\flutter_with_mirror.ps1 run -d windows
.\scripts\flutter_with_mirror.ps1 -UseOfficialSource pub get
.\scripts\flutter_with_mirror.ps1 -ProxyUrl http://127.0.0.1:7890 pub get
```

连接 MuMu 模拟器：

```powershell
.\scripts\connect_mumu.ps1
```

这条脚本会自动扫描 MuMu 的 `vm_config.json`，优先尝试桥接模式下的 `guest_ip:5555`，再回退到 `127.0.0.1:host_port`；成功后可直接再跑 `flutter devices` 或 `flutter run -d <device-id>`。

生成 Windows 安装器：

```powershell
.\scripts\build_windows_installer.ps1
```

这条脚本会先构建 Windows Release，再调用 Inno Setup 输出单个安装器，并复制到桌面。

Web 开发代理：

```powershell
.\scripts\run_web_with_proxy.ps1
```

补齐 Android 命令行环境：

```bash
./scripts/complete_android_setup.sh
```

更多网络相关说明见 [docs/development-network.md](docs/development-network.md)。

## 品牌资源

当前“展示在 App 外部”的品牌图标已经收敛到一套固定流程：

- 设计源：`assets/branding/starflow_icon_master.svg`
- 应用内主 Logo：`assets/branding/starflow_logo_primary.svg`
- 启动页首帧图标：`assets/branding/starflow_launch_logo.png`
  透明底，只保留星星与流线主图案
- 导出脚本：`tool/generate_brand_assets.py`
- 当前外部 Logo 高倍基准图：`build/brand_assets/app_icon_raw_capture.png`
- 当前外部 Logo 统一母版：`build/brand_assets/starflow_app_icon_master.png`

重新生成外部图标资源：

```powershell
C:\anaconda3\python.exe tool\generate_brand_assets.py
```

这条命令会更新这些外部展示资源：

- Android `mipmap-* / drawable-nodpi/icon_preview_sharp.png`
- Android 启动页 `drawable*/launch_background.xml` 与 `drawable-nodpi/launch_logo.png`
- iOS `Runner/Assets.xcassets/AppIcon.appiconset/*`
- iOS `Runner/Assets.xcassets/LaunchImage.imageset/*`
- macOS `Runner/Assets.xcassets/AppIcon.appiconset/*`
- Web `web/favicon.png` 与 `web/icons/*`
- Windows `windows/runner/resources/app_icon.ico`
- Android TV 横幅 `android/app/src/main/res/drawable-nodpi/tv_banner_*.png`

补充说明：

- 外部 App Icon 已不再走 HTML 截图链路，当前是由脚本直接根据 `assets/branding/starflow_icon_master.svg` 程序化生成统一母版
- `build/brand_assets/app_icon_raw_capture.png` 是从矢量母版直接输出的高倍基准图
- `build/brand_assets/starflow_app_icon_master.png` 是用于各平台缩放分发的统一母版
- Android 启动器小图标与 TV 横幅里的小方形 Logo 当前都复用同一份矢量母版
- 小尺寸启动器图标不再额外做锐化，避免星星周边出现黑色描边或暗边
- Android TV Banner 仍然通过 `docs/starflow_tv_banner.html` + 本机 Edge 无头渲染导出
- 启动页第一帧与外部启动器图标不是同一层资源；Android 与 iOS 启动页当前都使用 `assets/branding/starflow_launch_logo.png` 这张透明底主图案资源，不复用外部 app icon 的方形底板

## 测试

当前 `test/` 已覆盖这些核心模块：

- 设置模型与迁移
- 首页装配
- 首页控制器与 settings slice
- 首页详情缓存批量合并
- 本地详情缓存
- 页面级 `RetainedAsync` 状态保留
- Emby / WebDAV 客户端
- `WebDAV` 识别与索引
- `NasMediaIndexer` 分组、增量刷新与并发预算
- 空库自动重建后台调度
- `WMDB / TMDB / IMDb`
- `PanSou / CloudSaver`
- 夸克保存与 `SmartStrm`
- 搜索仓库
- 播放记忆与最近播放排序稳定性
- 播放启动准备与路由判定
- 组件级基础冒烟测试

运行全部测试：

```bash
flutter test
```

## Performance Baselines

`tool/perf/run_perf_baselines.dart` 现在可以按场景精确定义跑 `flutter test` 的组合命令、收集运行次数、算出 p50/p95，并输出到 `tool/perf/perf_baselines.json`，方便把启动、首页、详情、播放器等关键路径的性能变化记录在同一套基线里。

最近这轮对 `home_page.dart`、`home_controller.dart`、`player_page.dart` + `widgets/player_page_*.part.dart`、`nas_media_indexer.dart` 和 `playback_memory_repository.dart` 的收口，都建议至少补跑一次对应 smoke 或 perf baseline。更细的运行建议见 [docs/performance.md](docs/performance.md)。

## Player Open Smoke

新添的 `test/perf/player_open_smoke_test.dart` 从 playback 启动准备、目标解析、路由决策到执行器一条链路穿透，并用内存存储的续播/跳过配置覆盖高码率电视目标，确保 `player_open` 性能场景能真实触发 `PlaybackStartupCoordinator`/`PlaybackTargetResolver`/`PlaybackEngineRouter`/`PlaybackStartupExecutor` 的协作流程。

## 当前优化落地

- 已完成的 `P0` 收口：首页与媒体库批量缓存、settings slice provider、统一 `RetainedAsync` 模式、空库自动重建后台化、首页 Hero/PageController 稳定化、图片 decode 尺寸与结果懒构建。
- 已完成的 `P1` 关键边界：`HomePageController / HomeFeedRepository / HomeHeroPrefetchCoordinator`、`DetailPageController / DetailTargetResolver`、`PlaybackStartupCoordinator / PlaybackTargetResolver / PlaybackEngineRouter / PlaybackStartupExecutor`、`AppMediaQueryService`。
- 已完成的主文件瘦身：首页、播放页和 NAS 索引器都已经沉到更明确的子文件层级；其中 `player_page.dart` 已回到页面壳量级，播放器控制、启动/MPV、运行期动作与 TV chrome/对话框都已拆到 `presentation/widgets/` 下的 widgets 与 `part` 文件。
- 已补的稳定性验证：聚焦 `flutter analyze` 与 `flutter test` 已覆盖首页、播放、索引和播放记忆链路；`PlaybackMemoryRepository` 的时间戳稳定化也已经收口，修复了 Windows 下最近播放排序抖动。
- 持续推进的深水区：`P2` 里的索引逐源增量查询 / upsert、CPU 识别链 isolate 化、更细的刷新并发预算与后台工作分级开关仍是后续重点。

## 常用设置路径

- `设置 -> 媒体源`
- `设置 -> 搜索服务`
- `设置 -> 元数据与评分`
- `设置 -> 网络存储`
- `设置 -> 本地存储`
- `设置 -> 配置管理`
- `设置 -> 播放`
- `设置 -> 首页模块`

## 相关文档

- [docs/architecture.md](docs/architecture.md)
- [docs/performance.md](docs/performance.md)
- [docs/development-network.md](docs/development-network.md)
