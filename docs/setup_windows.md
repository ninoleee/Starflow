# Windows 环境配置（Flutter + Android）

本仓库是 Flutter 项目，需要：
1) Flutter SDK + Dart
2) JDK 17
3) Android SDK（含 cmdline-tools / platform-tools / android-35）

以下步骤按从零开始配置。已有组件可跳过对应步骤。

## 1. 安装 Flutter SDK

1) 下载 Flutter SDK（zip）并解压到你喜欢的位置，例如：
`C:\dev\flutter`
2) 把 Flutter 的 `bin` 加入 PATH：
`C:\dev\flutter\bin`
3) 重新打开终端后运行：
```
flutter --version
```

## 2. 安装 JDK 17

建议安装 Temurin 17（OpenJDK）。
1) 安装完成后设置 `JAVA_HOME`（示例路径按你的安装位置调整）：
```
setx JAVA_HOME "C:\Program Files\Eclipse Adoptium\jdk-17.0.x"
```
2) 把 `JAVA_HOME\bin` 加入 PATH：
```
setx PATH "%PATH%;%JAVA_HOME%\bin"
```
3) 重新打开终端后运行：
```
java -version
```

## 3. 安装 Android Studio 或命令行工具

推荐安装 Android Studio（会附带 Android SDK 管理器）。
安装后打开一次 Android Studio，进入 SDK Manager：
- 安装 `Android SDK Platform 35`
- 安装 `Android SDK Platform-Tools`
- 安装 `Android SDK Command-line Tools (latest)`

如果只装命令行工具，需要确保 `sdkmanager` 可用。

## 4. 配置 ANDROID_HOME / ANDROID_SDK_ROOT

假设 Android SDK 安装在：
`C:\Users\<你>\AppData\Local\Android\Sdk`

设置环境变量：
```
setx ANDROID_HOME "C:\Users\<你>\AppData\Local\Android\Sdk"
setx ANDROID_SDK_ROOT "C:\Users\<你>\AppData\Local\Android\Sdk"
```

并把以下路径加入 PATH：
```
setx PATH "%PATH%;%ANDROID_HOME%\platform-tools;%ANDROID_HOME%\cmdline-tools\latest\bin"
```

## 5. 安装 Android 组件并接受许可

仓库已提供 PowerShell 脚本：
```
.\scripts\complete_android_setup.ps1
```

脚本会：
- 接受 SDK 许可
- 安装 `platform-tools` 和 `platforms;android-35`

## 6. 验证 Flutter 与 Android

```
flutter doctor
flutter config --enable-android
flutter doctor --android-licenses
```

看到 Android toolchain 通过即可开始构建：
```
flutter build apk --release
```
