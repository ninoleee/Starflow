# Starflow

`Starflow` 是一个为个人影音库设计的跨平台播放入口，目标是把 `Emby`、本地 `NAS`、豆瓣想看/推荐，以及可配置的在线搜索服务统一到一个首页模块化体验里。

当前仓库已经搭好了第一版架构骨架，重点是：

- 首页采用模块编排，支持豆瓣推荐、豆瓣想看、Emby 资源、NAS 资源等模块扩展。
- 媒体源、豆瓣、搜索服务全部通过独立仓库接口抽象，后续接真服务不会推翻页面层。
- 设置页支持维护媒体源、搜索服务、豆瓣账号和首页模块顺序。
- Emby 已接入登录、媒体列表拉取和播放直链生成。
- 整体按跨平台 Flutter 工程组织，适合后续补齐 `iOS / Android / macOS / Windows / Linux / Web`。

## 当前状态

这个环境里没有安装 `flutter` 命令，所以本次先直接写入了 Flutter 项目骨架与业务代码；平台目录还没有生成。

初始化完整 Flutter 工程时执行：

```bash
flutter create . --platforms=ios,android,macos,windows,linux,web
flutter pub get
flutter run -d macos
```

如果你只想先跑手机端，也可以只生成对应平台：

```bash
flutter create . --platforms=ios,android
```

## 目录

```text
lib/
  app/                  # 应用入口、路由、主题
  core/                 # 通用组件与假数据
  features/
    discovery/          # 豆瓣推荐/想看
    home/               # 首页模块编排
    library/            # Emby/NAS 媒体库
    playback/           # 播放目标与播放器占位页
    search/             # 在线资源搜索
    settings/           # 媒体源/搜索服务/豆瓣/首页模块配置
docs/
  architecture.md       # 架构规划与真实服务接入建议
```

## 接下来建议

1. 先用现在的假数据 UI 把产品流转走通。
2. 先在设置页把你的 Emby 地址、用户名和密码跑通，验证真实媒体列表能拉出来。
3. NAS 不建议第一版直接走裸 `SMB`，更适合通过 `WebDAV / HTTP` 或轻量 connector 服务统一成可跨平台的资源接口。
4. 豆瓣建议做成可选能力，优先接你自己的账号 cookie 或中转服务，避免让客户端直接承载脆弱的抓取逻辑。

## Emby 使用方式

1. 打开设置页，编辑或新增一个 `Emby` 类型的媒体源。
2. 填写 `Endpoint`、`Emby 用户名`、`Emby 密码`。
3. 点击 `测试登录`，成功后会自动保存 `Access Token / User ID / Device ID`。
4. 返回首页或媒体库，Emby 内容会直接从真实服务器拉取。

说明：

- 如果你的 Emby 地址没有显式带 `/emby`，客户端会自动尝试补一个官方默认路径。
- 播放目标会生成直链，并同时附带 `X-Emby-Token` header，方便后面接真播放器。
