# iOS 启动图资源

这个目录只用于 `iOS` 启动图资源管理，本身不参与应用内页面逻辑。

补充说明：

- 这份说明已按 `2026-04-11` 的仓库状态同步
- 这里的启动图资源不等同于外部 App Icon
- 启动页首帧当前与 `assets/branding/starflow_launch_logo.png` 保持同源
  这张图是透明底主图案，不带外部 app icon 的圆角方形底板
- `tool/generate_brand_assets.py` 会同步更新这里的 `LaunchImage.png / @2x / @3x`
- 外部 App Icon 当前同样由仓库根目录下的 `tool/generate_brand_assets.py` 统一生成
- 外部 App Icon 当前以 `assets/branding/starflow_icon_master.svg` 为统一矢量源
- 这个目录通常不需要单独维护；应用内详情页、搜索页、播放器等展示改动也不会影响这里
- 首页缓存批量化、settings slice、retained async、播放启动链拆分和空库后台重建都不会影响这里的启动图资源
- 最近新增的 `TV` 详情页显式方向焦点链、MuMu 连接脚本和 iOS 原生播放会话桥接说明，也都不影响这里的启动图资源
- 最近桌面端横向翻页按钮、内置 `MPV` 顶部返回按钮位置调整、播放启动路由拆分、`MPV` 退出清理、`ISO` 支持和本地 trace 默认关闭，也都属于运行时逻辑，不会影响这里的启动图资源
- 最近 `NasMediaIndexer` 拆成多 `part` 文件并把主文件压回约 `1k` 行，也只影响媒体库 / 索引链代码组织，不会影响这里的启动图资源
- 最近首页、播放页和首页控制层的主文件拆分，以及 `PlaybackMemoryRepository` 的最近播放排序稳定化，也都属于运行时/本地存储逻辑，不会影响这里的启动图资源
- 如果你只是要更新桌面、启动器、安装包里看到的 App 图标，不需要改这里

如果你要同步更新启动页视觉，推荐直接运行：

```powershell
C:\anaconda3\python.exe tool\generate_brand_assets.py
```

如果需要替换启动图，可以直接覆盖当前目录下的图片资源，或在 `Xcode` 中打开：

```bash
open ios/Runner.xcworkspace
```

然后在 `Runner/Assets.xcassets` 里替换对应的启动图素材。
