# iOS 启动图资源

核对日期：2026-09-20。本目录只管理生成的 LaunchImage 资源，不承载运行时页面或日志逻辑。

## 当前使用方式

[LaunchScreen.storyboard](../../Base.lproj/LaunchScreen.storyboard) 仅显示 `#121212` 背景，不引用本目录图片。Logo 在 Flutter 启动页通过仓库根目录下的 `assets/branding/starflow_launch_logo.png` 展示。因此只替换本目录 PNG 不会改变当前原生启动页。

`LaunchImage.png / LaunchImage@2x.png / LaunchImage@3x.png` 分别为 180 / 360 / 540 像素，由统一导出脚本继续生成并保留完整构图。这里的图片不是桌面 App Icon；图标位于相邻的 `AppIcon.appiconset`，iOS 默认和深色图标均导出为无透明通道 RGB。

## 资源来源

- 普通母版：`assets/branding/starflow_logo_source.png`。
- iOS 深色 App Icon 母版：`assets/branding/starflow_ios_dark_icon_source.png`，不替换 LaunchImage 母版。
- 统一导出入口：[tool/generate_brand_assets.py](../../../../tool/generate_brand_assets.py)。旧 Swift 入口只转发到 Python。
- 历史归档说明：[backups/branding/README.md](../../../../backups/branding/README.md)。

以上源码路径相对仓库根目录。不要单独覆盖本目录图片再期待下次生成保留手工修改；应更新母版并统一导出。

在仓库根目录执行，需 Python 3、Pillow，完整导出还需 Microsoft Edge 渲染 TV 横幅：

```sh
python3 tool/generate_brand_assets.py
```

Windows 示例：

```powershell
C:\anaconda3\python.exe tool\generate_brand_assets.py
```

可用 `EDGE_PATH` 指定浏览器。导出后检查 Asset Catalog、完整构图、深色图标和 Flutter 启动首屏；需要改变原生启动布局时，另行检查 storyboard，而不是把运行时 Flutter UI 添加到本资源说明。

检查 Xcode 资源：

```bash
open ios/Runner.xcworkspace
```

本次仅同步说明，没有修改或重新生成任何 PNG、图标或 storyboard。
