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
#
# When a settings JSON path is supplied, the APK is named
# starflow-tv-config-<ver>.apk and the settings are embedded; otherwise it
# is named starflow-tv-<ver>.apk with no embedded settings.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ICLOUD_ROOT="${ICLOUD_ROOT:-$HOME/Library/Mobile Documents/com~apple~CloudDocs}"
ICLOUD_APK_DIR="${ICLOUD_APK_DIR:-$ICLOUD_ROOT/APK}"

cd "$PROJECT_ROOT"

if [[ ! -f "pubspec.yaml" ]]; then
  echo "Error: pubspec.yaml not found in project root." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Error: flutter command not found in PATH." >&2
  exit 1
fi

# Mirror the version-stepping logic from build_tv_apk.ps1:
#   keep major; use current month; increment sequence within the month;
#   reset sequence to 0 when the month changes.
update_pubspec_version() {
  local pubspec_path="$1"
  local version_line major current_month current_sequence month next_sequence next_version

  version_line="$(awk '/^version:[[:space:]]*/ {print $0; exit}' "$pubspec_path")"
  if [[ ! "$version_line" =~ ^version:[[:space:]]*([0-9]+)\.([0-9]+)\.([0-9]+)(\+[0-9]+)?[[:space:]]*$ ]]; then
    echo "Error: unable to parse version from $pubspec_path." >&2
    exit 1
  fi

  major="${BASH_REMATCH[1]}"
  current_month="${BASH_REMATCH[2]}"
  current_sequence="${BASH_REMATCH[3]}"
  month="$(date +%-m)"

  if [[ "$current_month" == "$month" ]]; then
    next_sequence=$((10#$current_sequence + 1))
  else
    next_sequence=0
  fi

  next_version="${major}.${month}.${next_sequence}"
  perl -0pi -e "s/^version:\\s*\\d+\\.\\d+\\.\\d+(?:\\+\\d+)?\\s*$/version: ${next_version}/m" "$pubspec_path"
  printf '%s\n' "$next_version"
}

VERSION="$(update_pubspec_version pubspec.yaml)"
BUILD_DATE="$(date +%Y-%m-%d)"

SETTINGS_JSON_PATH="${1:-}"

# Embedded settings handling (mirrors Set-EmbeddedSettings / Remove-EmbeddedSettings)
EMBEDDED_DIR="$PROJECT_ROOT/assets/bootstrap"
EMBEDDED_PATH="$EMBEDDED_DIR/embedded_settings.json"
mkdir -p "$EMBEDDED_DIR"
rm -f "$EMBEDDED_PATH"   # clean start, mirrors the empty-settings branch
trap 'rm -f "$EMBEDDED_PATH"' EXIT

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
  --android-skip-build-dependency-validation \
  --build-name "$VERSION" \
  --dart-define "STARFLOW_BUILD_DATE=$BUILD_DATE"

SOURCE_APK="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -f "$SOURCE_APK" ]]; then
  echo "Error: build output not found: $SOURCE_APK" >&2
  exit 1
fi

TARGET_NAME="${NAME_PREFIX}-${VERSION}.apk"
mkdir -p "$ICLOUD_APK_DIR"
cp -f "$SOURCE_APK" "$ICLOUD_APK_DIR/$TARGET_NAME"

echo "Version=$VERSION"
echo "BuildDate=$BUILD_DATE"
echo "APK=$ICLOUD_APK_DIR/$TARGET_NAME"
