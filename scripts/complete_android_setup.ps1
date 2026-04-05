Param()

$ErrorActionPreference = "Stop"

function Require-Env([string]$name) {
  $value = [Environment]::GetEnvironmentVariable($name, "Process")
  if (-not $value) {
    $value = [Environment]::GetEnvironmentVariable($name, "User")
  }
  if (-not $value) {
    $value = [Environment]::GetEnvironmentVariable($name, "Machine")
  }
  if (-not $value) {
    throw "未找到环境变量 $name。请先配置 $name。"
  }
  return $value
}

$javaHome = $env:JAVA_HOME
if (-not $javaHome) { $javaHome = Require-Env "JAVA_HOME" }
if (-not (Test-Path (Join-Path $javaHome "bin\java.exe"))) {
  throw "未找到 JDK：$javaHome（缺少 bin\java.exe）"
}

$androidHome = $env:ANDROID_HOME
if (-not $androidHome) { $androidHome = $env:ANDROID_SDK_ROOT }
if (-not $androidHome) { $androidHome = Require-Env "ANDROID_HOME" }

$sdkmanager = Join-Path $androidHome "cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $sdkmanager)) {
  throw "未找到 sdkmanager：$sdkmanager。请先安装 Android SDK Command-line Tools (latest)。"
}

Write-Host "接受 SDK 许可..."
cmd /c "echo y | `"$sdkmanager`" --licenses >nul"

Write-Host "安装 platform-tools、platforms;android-35..."
cmd /c "`"$sdkmanager`" --install `"platform-tools`" `"platforms;android-35`""

Write-Host "完成。请重新打开终端后执行: flutter doctor && flutter build apk --release"
