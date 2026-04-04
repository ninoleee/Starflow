# Starflow

`Starflow` 是一个面向个人影音库的跨平台播放入口，目标是把 `Emby`、`NAS`、豆瓣内容发现，以及可配置的在线搜索服务统一到同一个首页里。

当前仓库已经不是纯骨架，而是一版可实际使用的 Flutter 应用：

- 已补齐 `iOS / Android / macOS / Windows / Linux / Web` 平台工程
- 支持 `Emby` 登录、分区读取、深层目录浏览、详情页、应用内播放
- 支持 `Emby PlaybackInfo` 解析播放地址，不再只依赖手拼直链
- 支持 `NAS(WebDAV)` 方式接入资源
- 支持首页模块编辑，可选择显示哪些模块与哪些来源分区
- 支持豆瓣第一阶段模块：`我看 / 随机想看 / 个性化推荐 / 片单 / 首页轮播`
- 支持 PanSou 风格聚合搜索接口，可配置你自己的服务地址与认证方式
- 支持应用内直接播放资源
- 启动页已改为极简预热：`Logo + App 名称 + 进度条`

默认不再内置任何示例影片、示例资源或演示账号；没有资源的地方会直接显示“无”。

## 当前能力

### 首页

- 首页是模块化首页，不是写死的固定布局
- 最底部有一个低调的 `编辑首页` 入口
- 支持添加、删除、启用/停用、拖动排序首页模块
- 支持展示不同来源的不同分区
- 点击模块标题即可进入该模块的完整列表页
- 首页 Hero 与详情页都做了更偏 `Apple TV` 风格的沉浸式展示

### 详情页与播放

- 详情页会展示海报、年份、简介、导演、演员、资源状态
- 如果是剧集，支持按季切换
- 每一季的剧集使用横向滑动轨道展示
- 每集卡片支持显示缩略图、标题、集数、时长、播放进度和简介
- 点单集可直接进入播放器
- Emby 片源点击播放时会先请求 `PlaybackInfo`，再解析真实播放地址
- 播放器当前基于 `video_player`

### 媒体源

- `Emby`
  - 支持账号密码登录
  - 自动保存 `Access Token / User ID / Server ID / Device ID`
  - 支持读取 `Views` 分区
  - 支持从分区递归浏览更深层级目录
  - 支持电影、剧集、季、集的详情与播放
  - 支持读取 Emby 返回的观看进度并展示在剧集卡片上
- `NAS`
  - 当前按 `WebDAV / HTTP` 网关方式接入
  - 适合飞牛 NAS 等可提供 `WebDAV` 的环境
  - 当前不直接走裸 `SMB`

### 豆瓣一期

- `我看`
  - `我想看`
  - `我在看`
  - `我看过`
  - `随机想看`
- `个性化推荐`
  - `电影`
  - `电视`
- `片单`
  - 支持 `doulist`
  - 支持 `subject_collection`
- `首页轮播`

豆瓣条目会自动尝试关联本地或服务器资源。匹配到资源时，点进详情后可直接播放；没匹配到时会显示资源状态为“无”。

### 搜索

- 支持配置多个搜索服务
- 当前已适配 PanSou API 风格接口
- 支持两种认证方式
  - 直接填写 `JWT Token / API Key`
  - 通过 `username + password` 先调登录接口换取 `JWT Token`
- 默认示例搜索服务地址是 `https://so.252035.xyz`

## 环境要求

- `Flutter SDK`
- `Dart SDK`
- `Xcode + CocoaPods`，如果要跑 `iOS`
- `Android SDK`，如果要跑 `Android`

## 快速开始

安装依赖：

```bash
flutter pub get
```

查看设备：

```bash
flutter devices
```

本地运行：

```bash
flutter run -d macos
flutter run -d ios
flutter run -d android
```

也可以直接指定设备：

```bash
flutter run -d <device-id>
```

## Android

调试安装到安卓手机：

```bash
flutter run -d <android-device-id>
```

打包 APK：

```bash
flutter build apk
```

打包 release APK：

```bash
flutter build apk --release
```

如果想把已经编译好的包安装到设备：

```bash
flutter install -d <android-device-id>
```

## iOS 调试说明

`iOS 14+` 上，Flutter 的 `debug` 包不能像普通应用一样从桌面图标直接启动。这是 Flutter 的已知行为，不是本项目特有问题。

你有两种使用方式：

- 调试和热重载：用 `flutter run` 或 Xcode 启动
- 像正常 app 一样从桌面直接打开：安装 `profile` 或 `release`

建议真机体验性能时优先使用：

```bash
flutter run -d <your-device-id> --profile
```

## 使用流程

### 1. 启动应用

应用启动时会先显示极简预热页，只保留 `Logo + Starflow + 进度条`，避免冷启动时长时间空白。

### 2. 配置媒体源

进入 `设置 -> 媒体源`。

`Emby` 推荐填写：

- 名称
- Endpoint
- 用户名
- 密码

填写后可以直接测试登录。成功后会自动保存会话信息，首页、媒体库、详情页和播放器都会复用这套配置。

`NAS(WebDAV)` 推荐填写：

- 名称
- WebDAV Endpoint
- 用户名
- 密码

### 3. 配置豆瓣

进入 `设置 -> 豆瓣`。

字段说明：

- `userId`
  - 用于 `我想看 / 我在看 / 我看过 / 随机想看`
- `sessionCookie`
  - 用于 `个性化推荐`

如果只填了 `userId`，我看类模块可以工作，但个性化推荐可能拿不到数据。

### 4. 编辑首页

进入首页，滚动到最底部，点击那个低调的 `编辑首页` 入口。

你可以在编辑器里：

- 选择是否显示某个模块
- 拖动模块排序
- 删除不需要的模块
- 添加来源分区模块
- 添加豆瓣模块

当前可添加模块包括：

- 最近新增
- 任意已接入来源的任意分区
- 豆瓣我想看
- 豆瓣随机想看
- 豆瓣个性化推荐 `电影`
- 豆瓣个性化推荐 `电视`
- 豆瓣片单
- 豆瓣首页轮播

### 5. 搜索在线资源

进入 `设置 -> 搜索服务` 可以配置你自己的聚合接口。

当前已适配的 PanSou 风格接口支持：

- `/api/search`
- `/api/auth/login`
- `Authorization: Bearer <token>`

如果服务开启认证：

- 可以直接填 `API Key / JWT Token`
- 或填用户名密码，让客户端先登录再搜索

## Emby 行为说明

- 资源浏览优先从 `Views` 分区开始
- 分区如果先返回文件夹分组，会继续下探到真正的媒体内容
- 点击播放时会优先请求 `PlaybackInfo`
- 剧集详情会继续读取 `Season / Episode` 子节点
- 如果 Emby 返回了 `PlayedPercentage` 或 `PlaybackPositionTicks`，剧集卡片会展示播放进度

## 搜索服务兼容说明

当前仓库里的 PanSou 兼容逻辑默认面向 `https://so.252035.xyz` 这一类接口，识别方式包括：

- `parserHint = pansou-api`
- endpoint 包含 `so.252035.xyz`
- endpoint 路径中包含 `/api/search`

如果你有自己的兼容服务，通常只需要把地址改成你的服务端地址即可。

## 目录结构

```text
lib/
  app/                  # 应用入口、路由、主题
  core/                 # 公共组件、种子配置
  features/
    bootstrap/          # 启动动画与预热流程
    details/            # 详情页模型与展示
    discovery/          # 豆瓣数据和发现模块
    home/               # 首页与首页编辑器
    library/            # Emby / NAS 媒体库
    playback/           # 播放器
    search/             # 搜索服务与结果页
    settings/           # 设置与配置持久化
docs/
  architecture.md       # 初始架构规划
```

## 当前边界

- 豆瓣能力依赖移动端接口和 Cookie，可用性可能随上游变化
- `NAS` 当前以 `WebDAV / HTTP` 为主，没做 `SMB` 原生支持
- 播放器当前能播，但还没有把播放进度回写到 Emby
- 搜索结果当前以资源聚合展示为主，还没有和本地媒体库做自动入库或转存

## 下一步建议

- 增加播放进度回写与继续观看同步
- 继续扩展豆瓣模块到更完整的发现体系
- 增强 NAS 扫描与元数据识别
- 把在线搜索结果和一键转存/打开能力接起来
