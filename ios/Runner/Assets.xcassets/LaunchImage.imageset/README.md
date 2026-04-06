# iOS 启动图资源

这个目录只用于 `iOS` 启动图资源管理，本身不参与应用内页面逻辑。

补充说明：

- 这里的启动图资源不等同于外部 App Icon
- 外部 App Icon 当前由仓库根目录下的 `tool/generate_brand_assets.py` 统一生成
- 当前外部 Logo 高倍基准图是 `build/brand_assets/app_icon_raw_capture.png`
- 如果你只是要更新桌面、启动器、安装包里看到的 App 图标，不需要改这里

如果需要替换启动图，可以直接覆盖当前目录下的图片资源，或在 `Xcode` 中打开：

```bash
open ios/Runner.xcworkspace
```

然后在 `Runner/Assets.xcassets` 里替换对应的启动图素材。
