# 开发网络配置

仓库已经内置了一些面向国内网络环境和本地代理的辅助方案，主要集中在 `scripts/` 和 Android Gradle 初始化配置里。

补充说明：

- `WebDAV` 调试日志默认是关闭的，网络排障时如果需要看扫描与索引过程，可临时在 `lib/core/utils/webdav_trace.dart` 打开
- 图片请求如果遇到单张 `404`，展示层会自动尝试备用 artwork，这种情况通常不需要再额外打开网络日志
- `TV` 模式除了现有详情、搜索、播放和图片请求链路外，配置管理还会临时启用一个局域网 HTTP 传输入口，供手机上传或下载配置 JSON
- `TV` 模式里新增的“焦点尽量保持在屏幕中部、页面随焦点滚动”也只是本地交互改进，不增加新的网络请求
- `TV` 设置编辑页里把文本输入改成“条目入口 + 弹窗编辑”同样属于本地交互调整，不引入额外接口
- 当前设置区统一页面骨架、统一按钮和统一选择条目，也只是本地 UI 收敛，不增加新的网络请求
- 剧集页里“单集简介区进入单集详情”同样只是本地路由与焦点拆分；进入后复用既有详情页资源匹配、元数据补全和字幕关联链路，不新增新的服务端协议
- 高性能模式额外关闭的启动页动画、导航切换动画、首页 Hero 缓动、通用面板阴影和 TV 焦点缩放/阴影，也都只是本地视觉层简化，不增加新的网络请求
- 网络存储里的“STRM 触发等待时间”和“索引刷新等待时间”只是客户端本地延时调度，不新增新的服务端接口
- 网络存储里的夸克目录管理复用同一套夸克云盘接口；浏览、单条删除和清空当前目录都依赖有效 Cookie
- 如果开启了“同步删除夸克目录”，并配置了监听的 `WebDAV` 目录，删除命中这些目录下的文件或文件夹时，也会复用同一套夸克目录接口，到当前保存目录里删除匹配到的影片或剧集目录
- `App 内原生播放器` 与新增的解码模式设置也不引入新的网络协议，仍然复用同一条播放地址和请求头链路
- 详情页与播放器页的在线字幕搜索现在都走应用内实现，不依赖外部浏览器；是否真的发起请求由 `设置 -> 播放 -> 字幕 -> 在线字幕来源` 控制
- 详情页在已经拿到可播放资源时会自动搜索最多 `10` 条字幕候选；搜索结果和下载后的字幕文件都会优先复用本地缓存，避免重复请求
- 首页“最近播放”模块直接读取本地播放记忆与详情缓存，不引入新的网络请求
- `WebDAV` 文件删除虽然仍然只用标准 `DELETE`，但客户端现在会在成功后再次检查父目录，确认远端文件真的已经消失；如果远端仍存在，就不会继续当作本地删除成功
- 进入播放器且启用播放性能模式后，首页 `Hero` 补数、详情页自动补元数据 / 自动本地匹配、隐藏页网络图片加载都会被压住；从网络侧看，播放期间不应继续新增这几类后台请求

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

## 3. Web 开发代理

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

## 4. Android 命令行环境补齐

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

## 5. 实用建议

- Android 构建优先先确认 `android/local.properties` 里的 `sdk.dir` 和 `flutter.sdk`
- 如果 `flutter test` 或 `flutter pub get` 很慢，优先先试镜像脚本
- Web 调试需要代理时，优先用 `scripts/run_web_with_proxy.ps1`
- 需要切回官方源时，用 `-UseOfficialSource`
- TV 安装包默认用 `.\scripts\build_tv_apk.ps1` 生成，并直接输出到桌面
- `build_tv_apk.ps1` 只会在显式传入 `-SettingsJsonPath` 时临时嵌入配置 JSON
- Android TV 的 `设置 -> 配置管理` 已切换为局域网传输模式，不再依赖系统目录 / 文件选择器
- 打开后电视会显示访问码、端口和本机地址，手机连同一网络即可直接上传或下载配置
- 关闭传输弹窗后，临时传输服务会立刻停止
- 如果要管理夸克当前保存目录或删除目录内文件，先确认夸克 Cookie 仍然有效
- 当前目录删除走夸克回收站语义，不是应用侧永久粉碎
- 如果启用了“同步删除夸克目录”，命中已选 `WebDAV` 监听目录的删除成功后还会继续请求一次夸克目录删除接口；同样走回收站语义
- 如果 `WebDAV` 删除在服务端回了 `2xx`，但父目录复查仍能看到目标文件，应用会把它当作删除失败处理，避免只删本地索引或只清本地缓存

## 6. 在线元数据相关请求

当前仓库除了依赖下载，还会在运行期访问这些在线元数据 / 图片服务：

- `TMDB`：标题匹配、人物作品、`poster / backdrop / still / profile / logo` 图片与 `TMDB` 评分
- 其中人物头像使用 `profile`，详情页公司 Logo 使用 `production_companies.logo_path`；当前不再把 `networks` 当作公司 Logo 展示
- `WMDB`：中文资料、豆瓣 / IMDb 评分补全
- 豆瓣：兴趣、推荐、片单、轮播等发现内容
- `IMDb`：独立评分兜底

`TV` 模式下新增的这些交互也会继续命中同一批网络能力：

- 首页 `Hero` 和详情页会根据屏幕横竖方向切换横版 / 竖版 artwork
- 详情页人物关联影片页会访问 `TMDB` 人物作品接口
- 搜索页最近搜索词和来源记忆保存在本地，不新增服务端依赖
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
- `WMDB / 豆瓣 / IMDb` 相关站点是否被本机网络策略拦截

和手动元数据更新相关的当前行为：

- 详情页“手动更新信息”会无视当前是否已有标题、简介、图片或外部 ID，直接重新搜索在线元数据
- 只要搜索命中，当前详情缓存就会被命中结果直接覆盖
- 手动索引管理页在应用匹配结果时，也会把 `IMDb ID` 和 `TMDB ID` 一并写回本地索引与详情缓存
- “匹配来源”会直接限制详情页本地资源匹配时实际访问的 `Emby / WebDAV` 来源；如果没有单独勾选，则默认使用全部已启用来源
- 删除某个已匹配 `WebDAV` 资源后，详情缓存只会精确失效这条资源相关的本地匹配关系；影片本身的在线详情信息和其他候选资源不会因为这次删除被整批清空

和搜索来源相关的当前行为：

- `设置 -> 搜索服务 -> 搜索来源` 会直接限制搜索页实际参与执行的本地媒体源与在线搜索服务
- 如果没有单独勾选任何搜索来源，则默认使用全部已启用来源
- 如果保存的来源 ID 已失效，则会自动回退到全部已启用来源
- 搜索页内本地记住的来源勾选只是全局搜索来源范围内的二次筛选，不会额外产生新的请求

## 7. 在线字幕相关请求

当前应用内在线字幕链路的要点：

- 在线字幕来源由 `设置 -> 播放 -> 字幕 -> 在线字幕来源` 统一控制，当前已接入 `ASSRT`
- 详情页内联字幕搜索和播放器页里的“在线查找字幕”复用同一个仓库实现
- 搜索请求当前走 `https://assrt.net/sub/`，下载请求走对应的 `assrt.net` 字幕下载地址
- 详情页只有在已经拿到可播放目标时才会自动搜索，并且最多保留 `10` 条可自动加载的结果
- 下载后的字幕会缓存到应用支持目录下的 `starflow-subtitle-cache`
- 如果某条字幕之前已经下载并解压过，再次选择时会优先复用本地缓存，不再重复下载
- 如果在线字幕来源被全部关闭，则不会发起这类请求

## 8. 品牌资源导出

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
- `docs/starflow_tv_banner.html` 生成 TV Banner
- `build/brand_assets/starflow_app_icon_master.png` 作为各平台分发缩放前的统一母版

补充说明：

- 这条链路主要依赖本地文件与本机浏览器，不依赖在线元数据服务
- 外部 App Icon 已不再依赖 HTML 截图，当前以 `svg` 母版程序化导出
- Android 启动器小图标与 TV 横幅里的小方形 Logo 共用同一份矢量源
- 小尺寸图标不再额外锐化，避免星星周边出现黑色描边
- TV Banner 仍然依赖本机 Microsoft Edge 无头渲染 `docs/starflow_tv_banner.html`
- 如果后续换了外部 Logo 设计，只需要重新执行一次脚本，不要手工逐个平台替换
- 当“详情页自动匹配本地资源”关闭时，进入详情页不会自动触发本地资源匹配，只能手动点击“重新匹配资源”
- 本地资源手动匹配采用并发搜索；某个源先返回时会先展示该结果，但其余搜索源仍会继续完成
- 如果一次手动匹配命中多个本地资源，候选列表和当前选中项也会一并写入本地详情缓存
- 豆瓣等在线详情如果此前已经缓存过本地资源命中结果，重新进入详情页时会直接复用缓存中的资源状态、播放信息和多候选资源选择状态
- 退出详情页时，当前页的本地资源匹配会话会立刻失效；未启动的后续来源任务不会继续执行
