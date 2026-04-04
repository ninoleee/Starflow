#!/usr/bin/env zsh
# 在「本机终端」执行一次：安装 platform-tools 与 Android 35 平台（需能访问 dl.google.com）。
set -euo pipefail
export JAVA_HOME="${JAVA_HOME:-$HOME/.local/jdk/current}"
export ANDROID_HOME="${ANDROID_HOME:-/usr/local/share/android-commandlinetools}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

if [[ ! -x "$JAVA_HOME/bin/java" ]]; then
  echo "未找到 JDK：$JAVA_HOME — 请确认已解压 Temurin 到 ~/.local/jdk/"
  exit 1
fi

echo "接受 SDK 许可…"
yes | sdkmanager --licenses >/dev/null

echo "安装 platform-tools、platforms;android-35…"
sdkmanager --install "platform-tools" "platforms;android-35"

echo "完成。请执行: source ~/.zshrc && flutter doctor && cd $(dirname "$0")/.. && flutter build apk --release"
