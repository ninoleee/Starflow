# iOS 启动图资源

这个目录只用于 `iOS` 启动图资源管理，本身不参与应用内页面逻辑。

补充说明：

- 这里的启动图资源不等同于外部 App Icon
- 启动页首帧当前与 `assets/branding/starflow_launch_logo.png` 保持同源
  这张图是透明底主图案，不带外部 app icon 的圆角方形底板
- `tool/generate_brand_assets.py` 会同步更新这里的 `LaunchImage.png / @2x / @3x`
- 外部 App Icon 当前同样由仓库根目录下的 `tool/generate_brand_assets.py` 统一生成
- 外部 App Icon 当前以 `assets/branding/starflow_icon_master.svg` 为统一矢量源
- 这个目录通常不需要单独维护；应用内详情页、搜索页、播放器等展示改动也不会影响这里
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
