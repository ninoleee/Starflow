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
#   STARFLOW_FLUTTER_SDK=/path/to/flutter ./build_tv_apk_to_icloud.sh
#
# When a settings JSON path is supplied, the APK is named
# starflow-tv-config-<ver>.apk and the settings are embedded; otherwise it
# is named starflow-tv-<ver>.apk with no embedded settings.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ICLOUD_ROOT="${ICLOUD_ROOT:-$HOME/Library/Mobile Documents/com~apple~CloudDocs}"
ICLOUD_INSTALLER_DIR="${ICLOUD_INSTALLER_DIR:-$ICLOUD_ROOT/Installers}"

SETTINGS_JSON_PATH="${1:-}"
if [[ -n "$SETTINGS_JSON_PATH" ]]; then
  SETTINGS_JSON_PATH="$(cd "$(dirname "$SETTINGS_JSON_PATH")" && pwd)/$(basename "$SETTINGS_JSON_PATH")"
fi
cd "$PROJECT_ROOT"

if [[ ! -f "pubspec.yaml" ]]; then
  echo "Error: pubspec.yaml not found in project root." >&2
  exit 1
fi

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [path/to/settings.json]" >&2
  exit 1
fi

if [[ -z "${STARFLOW_FLUTTER_SDK:-}" && -d "$PROJECT_ROOT/.fvm/flutter_sdk" ]]; then
  STARFLOW_FLUTTER_SDK="$PROJECT_ROOT/.fvm/flutter_sdk"
fi
if [[ -n "${STARFLOW_FLUTTER_SDK:-}" ]]; then
  FLUTTER="$STARFLOW_FLUTTER_SDK/bin/flutter"
else
  FLUTTER="$(command -v flutter)" || { echo "Error: select the pinned Flutter SDK." >&2; exit 1; }
fi
DART="$(dirname "$FLUTTER")/dart"
export STARFLOW_FLUTTER_SDK="$(cd "$(dirname "$FLUTTER")/.." && pwd)"
export PATH="$STARFLOW_FLUTTER_SDK/bin:$PATH"

PREFLIGHT_ARGS=("$PROJECT_ROOT/tool/verify_tv_release.dart" --preflight)
if [[ -n "$SETTINGS_JSON_PATH" ]]; then PREFLIGHT_ARGS+=("$SETTINGS_JSON_PATH"); fi
"$DART" "${PREFLIGHT_ARGS[@]}"

# Preserve local bootstrap data even when a build fails.
EMBEDDED_DIR="$PROJECT_ROOT/assets/bootstrap"
EMBEDDED_PATH="$EMBEDDED_DIR/embedded_settings.json"
STAGING="$(mktemp -d)"
HAD_EMBEDDED=0
BOOTSTRAP_CHANGED=0
cleanup() {
  if [[ "$BOOTSTRAP_CHANGED" == 1 ]]; then
    rm -f "$EMBEDDED_PATH"
    if [[ "$HAD_EMBEDDED" == 1 ]]; then cp -p "$STAGING/original.json" "$EMBEDDED_PATH"; fi
  fi
  rm -rf "$STAGING"
}
trap cleanup EXIT
if [[ -f "$EMBEDDED_PATH" ]]; then
  cp -p "$EMBEDDED_PATH" "$STAGING/original.json"
  HAD_EMBEDDED=1
fi
if [[ -n "$SETTINGS_JSON_PATH" ]]; then
  cp "$SETTINGS_JSON_PATH" "$STAGING/settings.json"
  SETTINGS_JSON_PATH="$STAGING/settings.json"
fi
mkdir -p "$EMBEDDED_DIR"
BOOTSTRAP_CHANGED=1
rm -f "$EMBEDDED_PATH"

NAME_PREFIX="starflow-tv"
if [[ -n "$SETTINGS_JSON_PATH" ]]; then
  if [[ ! -f "$SETTINGS_JSON_PATH" ]]; then
    echo "Error: settings JSON not found: $SETTINGS_JSON_PATH" >&2
    exit 1
  fi
  NAME_PREFIX="starflow-tv-config"
  cp -f "$SETTINGS_JSON_PATH" "$EMBEDDED_PATH"
fi

VERSION="$("$DART" "$PROJECT_ROOT/tool/release_version.dart" pubspec.yaml)"
BUILD_DATE="$(date +%Y-%m-%d)"
echo "Building TV APK for starflow ($VERSION, $BUILD_DATE)..."

"$FLUTTER" build apk \
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
VERIFY_ARGS=("$PROJECT_ROOT/tool/verify_tv_release.dart" "$SOURCE_APK" "$VERSION")
if [[ -n "$SETTINGS_JSON_PATH" ]]; then
  VERIFY_ARGS+=("$SETTINGS_JSON_PATH")
fi
"$DART" "${VERIFY_ARGS[@]}"
mkdir -p "$ICLOUD_INSTALLER_DIR"
cp -f "$SOURCE_APK" "$ICLOUD_INSTALLER_DIR/$TARGET_NAME"

echo "Version=$VERSION"
echo "BuildDate=$BUILD_DATE"
echo "APK=$ICLOUD_INSTALLER_DIR/$TARGET_NAME"
