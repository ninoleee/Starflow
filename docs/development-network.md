# 开发网络配置

仓库已经内置了一些面向国内网络环境和本地代理的辅助方案，主要集中在 `scripts/` 和 Android Gradle 初始化配置里。

补充说明：

- `WebDAV` 调试日志默认是关闭的，网络排障时如果需要看扫描与索引过程，可临时在 `lib/core/utils/webdav_trace.dart` 打开
- 图片请求如果遇到单张 `404`，展示层会自动尝试备用 artwork，这种情况通常不需要再额外打开网络日志
- `TV` 模式本身不引入新的网络协议，主要还是复用现有详情、搜索、播放和图片请求链路

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
- 如果在 Android TV 或定制系统上做配置导入 / 导出时无法弹出系统文件选择器，改用 `设置 -> 配置管理` 里的手动路径输入方式

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

开发联调时如果这些服务需要代理，除了构建代理外，还要确认应用运行环境本身能访问外网。

和元数据最直接相关的本地设置有：

- `设置 -> 元数据与评分 -> TMDB Read Access Token`
- `设置 -> 元数据与评分 -> 启用 TMDB 自动补全影片信息`
- `设置 -> 元数据与评分 -> 启用 WMDB 自动补全影片信息`

如果详情页图片、评分或人物关联影片页为空，优先先检查：

- `TMDB Read Access Token` 是否已填写
- 当前网络或代理是否能访问 `api.themoviedb.org` 与 `image.tmdb.org`
- `WMDB / 豆瓣 / IMDb` 相关站点是否被本机网络策略拦截

和手动元数据更新相关的当前行为：

- 详情页“手动更新信息”会无视当前是否已有标题、简介、图片或外部 ID，直接重新搜索在线元数据
- 只要搜索命中，当前详情缓存就会被命中结果直接覆盖
- 手动索引管理页在应用匹配结果时，也会把 `IMDb ID` 和 `TMDB ID` 一并写回本地索引与详情缓存
