# 开发网络配置

项目已经为 Android Gradle 插件和常见 Maven 依赖接入了阿里云镜像。

## Gradle 代理

如果当前网络环境必须走代理，可以把下面这些配置加到 `android/local.properties`。这个文件已经被忽略，不会提交到仓库。

```properties
sdk.dir=C:\\Users\\yourname\\AppData\\Local\\Android\\sdk
flutter.sdk=C:\\dev\\flutter

systemProp.http.proxyHost=127.0.0.1
systemProp.http.proxyPort=7890
systemProp.https.proxyHost=127.0.0.1
systemProp.https.proxyPort=7890
systemProp.http.nonProxyHosts=localhost|127.*|10.*|192.168.*|*.local
```

`settings.gradle.kts` 会在初始化阶段把这些 `systemProp.*` 自动转成 JVM/Gradle 系统属性，这样插件解析和依赖下载都会生效。

## Flutter 镜像

在 PowerShell 里用包装脚本运行 Flutter 命令：

```powershell
.\scripts\flutter_with_mirror.ps1 pub get
.\scripts\flutter_with_mirror.ps1 run -d windows
.\scripts\flutter_with_mirror.ps1 -UseOfficialSource pub get
.\scripts\flutter_with_mirror.ps1 -ProxyUrl http://127.0.0.1:7890 pub get
```

脚本会优先从 `android/local.properties` 的 `flutter.sdk` 查找本机 Flutter，再回退到常见路径或 `PATH`。

默认会临时设置：

```text
PUB_HOSTED_URL=https://pub.flutter-io.cn
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

如果你更想全局生效，也可以把同样两个环境变量配到自己的终端或系统环境里。
