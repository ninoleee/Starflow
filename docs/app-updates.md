# 应用更新与发布

实现日期：2026-09-26。首版为 Android / Android TV 的手动检查、前台下载、校验及用户确认安装。没有自动后台下载、断点续传、强制更新、静默安装、灰度或自动降级。主机测试结果见 [主机记录](performance.md)，真实设备验收见 [设备清单](performance-device.md)。

## 使用与平台边界

- 设置的“数据与维护 -> 应用更新”和版本页脚进入同一页面；更新页自身的版本文字不再递归打开更新页。
- 检查更新显示当前版本、目标版本、安装包大小及说明；下载可以取消，失败后重新完整下载。首版不支持下载暂停/续传，不能把重试称为续传。
- 页面离开释放检查/下载所有权，应用失去前台时取消下载。播放、启动及其他页面不自动发起更新，也不弹窗打断播放。
- 下载通过后仍需点击安装。Android 8+ 未授权时前往系统设置允许 Starflow 安装应用，返回后再次点击安装；Android 6/7 的全局未知来源控制由系统安装界面处理。
- 系统安装界面已打开不等于安装成功；下次启动读取真实安装版本。系统可能拒绝安装或用户可以取消，应用不能自动卸载旧包解决签名冲突。
- Android 普通手机与 TV 共用现有 ARM32/ARM64 APK；不为 x86/x86_64 设备推荐该包。最低 API 23 不变。
- iOS、桌面和 Web 暂无已配置的正式更新渠道，页面明确提示不支持；没有伪造 App Store/TestFlight 链接。当前未签名 IPA 不能自行覆盖安装。

## 信任与数据

客户端更新地址复用“设置 -> 网络同步”的 WebDAV 地址、同步目录和账号密码；从该目录的 `releases/latest.json` 读取普通 JSON 清单，不再配置清单签名密钥或构建公钥。清单和 APK 仅允许 HTTPS，继续验证服务器证书，使用同一同步配置快照的 Basic 认证；初始地址与每个重定向都必须位于同源（协议/主机/端口一致）的 releases 目录内，最多三次跳转。跨域 CDN、跨目录或降级直接拒绝，不把凭据发到新地址，也不携带媒体源认证头。账号不写入清单、下载 URL 或日志。配置变化使旧更新控制器释放并取消下载。

清单直接包含 schemaVersion、appId、channel、version、versionCode、publishedAt、releaseNotes 和 artifacts，不再使用 payload/signature 包装。schemaVersion 为 1，清单响应上限 256 KiB（发布工具计入末尾换行），只接受 stable 的普通 Android TV 包。发布工具和客户端共用解析规则；旧签名包装不会被静默解包或忽略签名接受。

显示版本继续使用 `major.month.sequence`，比较使用 APK 实际数字 versionCode，不按字符串或三段号判断新旧。月份跨年回到 1 不代表降级；发布工具从 APK 读取数字，不用文档示例手填。清单里的包名必须与已安装应用一致。

下载流式写入应用私有 `updates/` 目录，单包最多 512 MiB，不把完整 APK 装入 Dart 内存；确切长度与 SHA-256 校验通过才改名。失败/取消清理本次临时文件，安装包不放入播放缓存或媒体库。下载遵循应用代理配置；取消与失败不影响已安装应用。

Android 安装桥接在后台复核私有目录、SHA-256、APK 包名、递增 versionCode、当前安装包签名与清单证书摘要，使用专用 FileProvider 只读授权后拉起系统安装器。原生为安装器保留验证副本，磁盘须容纳下载文件和验证副本；它不是静默安装器，也不接受任意本地文件路径。

SHA-256 是完整性检查，不是独立的发布者身份证明。移除清单签名后，清单真实性依赖 HTTPS 和 NAS 的访问控制：有发布目录写权限的人能够改变更新说明、版本与下载元数据，或阻断更新；APK 安装仍独立核对当前已安装应用的签名，不会因修改清单证书摘要而接受其他签名的 APK。Android keystore 必须保留、备份且不得上传发布目录；不能为更新功能改包名或换签名。NAS 的 HTTPS 证书也不属于这次删除范围。

## 首次配置

使用现有 HTTPS WebDAV 同步服务器，填写证书匹配的实际域名、同步目录和账号密码即可。HTTP 同步可以继续用于原配置/收藏功能，但应用更新拒绝明文 HTTP，不关闭 TLS 校验。

两个 TV 预设不再读取 `STARFLOW_UPDATE_PUBLIC_KEY` 或 `STARFLOW_UPDATE_MANIFEST_URL`，无需额外的更新构建配置：

```sh
ICLOUD_INSTALLER_DIR="$HOME/Desktop" ./scripts/build_tv_apk_to_icloud.sh
```

PowerShell 调用 `scripts/build_tv_apk.ps1`。继续固定 `.fvm/flutter_sdk`，release、API 23、ARM 双 ABI、跳过构建依赖验证、按月递增、规范文件名和桌面输出规则全部不变。首次升级模块需要手动安装一次，此前没有该模块的旧包无法凭空获得检查功能。

### 从签名清单版本迁移

2026-09-26 的旧更新模块要求 Ed25519 包装，不能读取新普通 JSON；新模块也明确拒绝旧包装。切换时先手动覆盖安装使用新模块、沿用原 APK 签名的包，再发布普通 JSON 清单。覆盖安装应保留数据，但仍需真机验证。不要在仍需服务旧客户端时直接改写现有 `latest.json`。本次源码修改没有覆盖 NAS 的旧发布文件，也没有删除本机旧 seed；seed 不再被新构建或发布脚本使用，完成旧客户端迁移后再清理。修改源码不代表已有 APK 已更新。

例如同步地址 `https://YOUR_HOST/dav/`、同步目录 `Starflow`，更新清单为 `https://YOUR_HOST/dav/Starflow/releases/latest.json`，APK 为 `https://YOUR_HOST/dav/Starflow/releases/VERSION_CODE/starflow-tv-VERSION.apk`。配置文件 `starflow-sync.json` 和收藏文件仍位于原同步目录，不能当成更新清单。

## 生成与发布

构建和发布分离，以下工具不构建、不递增版本、不联网上传。仅普通 `starflow-tv-VERSION.apk` 可以发布，嵌入设置包拒绝进入公共渠道，防止配置及凭据泄漏。

```sh
.fvm/flutter_sdk/bin/dart tool/generate_update_manifest.dart \
  --apk "$HOME/Desktop/starflow-tv-VERSION.apk" \
  --notes /PRIVATE_PATH/release-notes.txt \
  --artifact-url https://YOUR_HOST/dav/Starflow/releases/VERSION_CODE/starflow-tv-VERSION.apk \
  --stage-dir /LOCAL_STAGING/releases
```

`VERSION`、`VERSION_CODE` 和上述路径是占位符，需替换为 APK 的实际值。更新说明为 UTF-8，每个非空行一条。工具复用既有 TV 静态校验器验证 ABI、API、无内嵌配置和固定 APK 签名，再读取真实包信息并生成普通 JSON；不接受 `--seed` 或 `--seed-format` 参数，也不创建密钥。

本地 staging 写入以实际数字版本命名的不可变 `VERSION_CODE/` 文件夹，避免跨年出现同名 `major.month.sequence` 后覆盖旧文件，APK 文件名保持原发布规范。校验回读后最后原子切换 `latest.json`。`scripts/publish_update_release.sh` 是便捷入口，不是已部署的 CI 或云端发布服务。SMB 共享可挂载为 `/Volumes/apps`，发布落点为 `/Volumes/apps/starflow/releases`；App 中的 HTTPS WebDAV 地址和同步目录必须实际映射到同一目录，不能根据 SMB URL 猜测域名或路径。中断残留 `.publish.lock` 须人工核对现场后处理，不能盲目覆盖同版本文件。

WebDAV 发布步骤：把 staging 的数字版本目录上传到同步目录的 `releases/` 中，校验远端 APK 大小/哈希及清单可读取，再最后上传/替换 `releases/latest.json`。账号必须有这些文件的读取权限，发布账号另需写入权限；设备仅检查和下载，不自动 PUT 安装包，不修改配置/收藏文件。WebDAV 服务需支持直接文件 GET，跨域直链重定向不支持。远端发布仍需实际凭据及明确发布操作，本次源码接入不等于文件已上传。

撤回有问题的版本时可将 latest 指向上一份格式兼容且已校验的清单，阻止尚未升级的用户继续收到它；已安装新版本的设备不会自动降级。修复必须用更高 versionCode 的新版本前进发布。覆盖安装通常保留应用数据，但未来存储结构改动仍须独立迁移、备份与升级路径测试，不能依靠安装器解决数据兼容。
