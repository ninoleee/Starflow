# Starflow 架构规划

## 1. 产品目标

Starflow 不是单纯的视频播放器，而是你的个人媒体中枢：

- 用首页模块把“想看什么”和“能不能马上播放”放在一起。
- 把 `Emby / NAS / 在线搜索 / 豆瓣` 收敛成一套统一体验。
- 从第一天就按跨平台设计，避免后面为了桌面端或 Web 重做。

## 2. 为什么选 Flutter

- 单一代码库覆盖 `iOS / Android / macOS / Windows / Linux / Web`。
- UI 结构统一，适合做首页模块编排与大屏/移动端自适应。
- 网络、状态管理和配置持久化能力成熟，适合先把业务骨架搭起来。

## 3. 分层

### Presentation

- 页面、组件、交互状态。
- 只依赖应用层 provider，不直接写死 Emby 或豆瓣接口。

### Application

- 组装首页模块。
- 处理搜索执行、设置变更、豆瓣条目和本地资源的关联。
- 对外提供 `Riverpod provider`。

### Domain

- 定义 `MediaItem`、`MediaSourceConfig`、`DoubanEntry`、`SearchProviderConfig`、`HomeModuleConfig` 等核心模型。
- 保证 UI 和后端协议解耦。

### Data

- 每个能力单独抽象 repository。
- 当前先落 `Mock` 实现，后续替换成真实数据源。

## 4. 核心能力边界

### 4.1 媒体库

抽象：`MediaRepository`

负责：

- 拉取 Emby / NAS 资源清单。
- 返回可播放条目。
- 给豆瓣条目做标题匹配，判断资源是否已就绪。

建议真实实现：

- `EmbyMediaRepository`  已在当前版本接入第一版真实实现
- `NasIndexRepository`

### 4.2 在线搜索

抽象：`SearchRepository`

负责：

- 读取用户配置的搜索服务。
- 以统一结果模型返回搜索结果。

建议真实实现：

- `TemplateSearchRepository`：适合多数 HTTP 搜索站。
- `BridgeSearchRepository`：适合走你自己的聚合服务。

### 4.3 豆瓣

抽象：`DiscoveryRepository`

负责：

- 获取推荐、想看、收藏等发现内容。
- 不直接关心本地媒体是否存在。

注意：

- 豆瓣客户端直连能力不稳定，建议预留“服务端桥接”方案。
- 第一版建议账号配置放在设置页，支持 `userId + cookie/session` 的可选方式。

### 4.4 播放

当前骨架先定义 `PlaybackTarget`，播放器页先保留集成点。

当前已经接上的能力：

- Emby 用户名密码登录
- Emby 媒体列表拉取
- Emby 直链 URL 生成
- `PlaybackTarget.headers` 中透传 `X-Emby-Token`

建议后续：

- 移动端和桌面端统一接 `media_kit` 一类跨平台播放器。
- `PlaybackTarget` 中保留 headers、字幕轨、转码信息，兼容 Emby 直链和自建网关。

## 5. 首页模块机制

首页不是固定页面，而是模块容器：

- `HomeModuleType` 定义模块类型。
- `HomeModuleConfig` 定义模块标题、启用状态、排序。
- `HomeController` 负责按配置装配模块数据。

第一批内置模块：

- 豆瓣推荐
- 豆瓣想看
- 最近新增
- Emby 媒体库
- NAS 媒体库

这样做的价值：

- 后续加“继续观看”“收藏”“最近搜索”“下载中”等模块时，不需要改首页主框架。
- 不同平台可以复用同一套模块数据，只替换展示样式。

## 6. NAS 接入建议

### 不建议直接依赖裸 SMB 的原因

- 移动端权限、沙箱和后台访问限制多。
- Web 端几乎无法直接处理 SMB。
- 跨平台播放器拿到统一播放地址更重要，而不是直接挂载文件系统。

### 更稳的做法

优先级建议：

1. 直接接 `Emby / Jellyfin` 作为主媒体源。
2. 如果必须直连 NAS，优先用 `WebDAV / HTTP / 自建 Connector` 提供索引与播放 URL。
3. 把 NAS 视为“资源后端”，而不是让客户端自己做文件系统适配。

## 7. 搜索服务配置模型

当前设计允许每个搜索服务拥有：

- 名称
- 类型
- Endpoint
- API Key
- 解析器提示
- 启用状态

后续可以继续扩展：

- 请求模板
- 自定义 header
- Cookie
- 结果解析脚本

## 8. 真实接入顺序

推荐按这个顺序推进：

1. `Emby` 登录、媒体列表、播放直链。
2. 首页模块真实数据接通。
3. 搜索服务模板化配置。
4. 豆瓣桥接服务。
5. NAS connector。
6. 真播放器、字幕、倍速、继续播放。

## 9. 当前骨架里已经落下的点

- 路由、主题、底部导航
- 首页模块编排
- 媒体源与搜索服务设置
- 豆瓣配置与首页关联展示
- 假数据仓库，方便先走 UI 和交互

## 10. 下一步可以怎么继续

如果你愿意，我下一轮可以继续往前做其中一条：

- 直接把 `Emby` API 接上
- 加真实播放器
- 把设置页做成更完整的增删改查
- 做豆瓣条目和本地资源的更强匹配策略
