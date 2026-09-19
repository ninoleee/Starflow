#!/usr/bin/env bash
#
# build_tv_apk_to_icloud.sh
#
# macOS / Linux equivalent of scripts/build_tv_apk.ps1.
# Reproduces the preset behavior exactly (per AGENTS.md) but copies the
# produced APK into iCloud Drive instead of the Desktop, mirroring the
# iCloud handling already used by build_ipa_to_icloud.sh.
#
# Usage:
#   ./build_tv_apk_to_icloud.sh [path/to/settings.json]
#   STARFLOW_RELEASE_VERSION=1.9.6 ./build_tv_apk_to_icloud.sh
#
# When a settings JSON path is supplied, the APK is named
# starflow-tv-config-<ver>.apk and the settings are embedded; otherwise it
# is named starflow-tv-<ver>.apk with no embedded settings.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ICLOUD_ROOT="${ICLOUD_ROOT:-$HOME/Library/Mobile Documents/com~apple~CloudDocs}"
ICLOUD_INSTALLER_DIR="${ICLOUD_INSTALLER_DIR:-$ICLOUD_ROOT/Installers}"

cd "$PROJECT_ROOT"

if [[ ! -f "pubspec.yaml" ]]; then
  echo "Error: pubspec.yaml not found in project root." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Error: flutter command not found in PATH." >&2
  exit 1
fi

# Version stepping is shared with the PowerShell presets.

VERSION="$(dart "$PROJECT_ROOT/tool/release_version.dart" pubspec.yaml)"
BUILD_DATE="$(date +%Y-%m-%d)"

SETTINGS_JSON_PATH="${1:-}"

# Embedded settings handling (mirrors Set-EmbeddedSettings / Remove-EmbeddedSettings)
EMBEDDED_DIR="$PROJECT_ROOT/assets/bootstrap"
EMBEDDED_PATH="$EMBEDDED_DIR/embedded_settings.json"
mkdir -p "$EMBEDDED_DIR"
rm -f "$EMBEDDED_PATH"   # clean start, mirrors the empty-settings branch
cleanup() {
  rm -f "$EMBEDDED_PATH"
}
trap cleanup EXIT

NAME_PREFIX="starflow-tv"
if [[ -n "$SETTINGS_JSON_PATH" ]]; then
  if [[ ! -f "$SETTINGS_JSON_PATH" ]]; then
    echo "Error: settings JSON not found: $SETTINGS_JSON_PATH" >&2
    exit 1
  fi
  NAME_PREFIX="starflow-tv-config"
  cp -f "$SETTINGS_JSON_PATH" "$EMBEDDED_PATH"
fi

echo "Building TV APK for starflow ($VERSION, $BUILD_DATE)..."

flutter build apk \
  --release \
  --target-platform android-arm,android-arm64 \
  --android-skip-build-dependency-validation \
  --build-name "$VERSION" \
  --dart-define "STARFLOW_BUILD_DATE=$BUILD_DATE"

SOURCE_APK="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -f "$SOURCE_APK" ]]; then
  echo "Error: build output not found: $SOURCE_APK" >&2
  exit 1
fi

TARGET_NAME="${NAME_PREFIX}-${VERSION}.apk"
mkdir -p "$ICLOUD_INSTALLER_DIR"
cp -f "$SOURCE_APK" "$ICLOUD_INSTALLER_DIR/$TARGET_NAME"

echo "Version=$VERSION"
echo "BuildDate=$BUILD_DATE"
echo "APK=$ICLOUD_INSTALLER_DIR/$TARGET_NAME"
