#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${MACOS_INSTALLER_DIR:-$HOME/Desktop}"
BUILD_DATE="$(date +%Y-%m-%d)"

if [[ "${1:-}" == "--help" && $# -eq 1 ]]; then
  printf '%s\n' \
    'Build the sandboxed macOS Release app and package a verified DMG.' \
    'Usage: scripts/build_macos_dmg.sh' \
    '  MACOS_INSTALLER_DIR=/path/to/output scripts/build_macos_dmg.sh' \
    '  STARFLOW_RELEASE_VERSION=major.month.sequence scripts/build_macos_dmg.sh' \
    'Uses the pinned .fvmrc Flutter SDK and current pubspec version by default.' \
    'Does not auto-increment or write pubspec.yaml.' \
    'Optional: STARFLOW_CLEAN_BUILD=1, STARFLOW_FORCE_PUB_GET=1.'
  exit 0
fi
if [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--help]" >&2
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: macOS DMG builds require macOS and Xcode." >&2
  exit 1
fi

if [[ -n "${STARFLOW_FLUTTER_SDK:-}" ]]; then
  FLUTTER="$STARFLOW_FLUTTER_SDK/bin/flutter"
else
  FLUTTER="$PROJECT_ROOT/.fvm/flutter_sdk/bin/flutter"
fi
DART="$(dirname "$FLUTTER")/dart"
if [[ ! -x "$FLUTTER" || ! -x "$DART" ]]; then
  echo "Error: pinned Flutter/Dart SDK not found: $(dirname "$(dirname "$FLUTTER")")" >&2
  exit 1
fi
export STARFLOW_FLUTTER_SDK="$(cd "$(dirname "$FLUTTER")/.." && pwd)"
export PATH="$STARFLOW_FLUTTER_SDK/bin:$PATH"

EXPECTED_FLUTTER="$(awk -F '"' '/^[[:space:]]*"flutter"[[:space:]]*:/ {print $4; exit}' "$PROJECT_ROOT/.fvmrc")"
ACTUAL_FLUTTER="$("$FLUTTER" --version | sed -n '1s/^Flutter \([^ ]*\).*/\1/p')"
if [[ -n "$EXPECTED_FLUTTER" && "$ACTUAL_FLUTTER" != "$EXPECTED_FLUTTER" ]]; then
  echo "Error: Flutter $EXPECTED_FLUTTER is pinned, found $ACTUAL_FLUTTER." >&2
  exit 1
fi

if [[ -n "${STARFLOW_RELEASE_VERSION:-}" ]]; then
  if [[ ! "$STARFLOW_RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: STARFLOW_RELEASE_VERSION must be major.month.sequence." >&2
    exit 1
  fi
  VERSION="$STARFLOW_RELEASE_VERSION"
else
  VERSION="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)(\+[0-9]+)?[[:space:]]*$/\1/p' "$PROJECT_ROOT/pubspec.yaml" | head -1)"
fi
if [[ -z "$VERSION" ]]; then
  echo "Error: unable to resolve a three-part app version." >&2
  exit 1
fi

ENTITLEMENTS="$PROJECT_ROOT/macos/Runner/Release.entitlements"
if /usr/libexec/PlistBuddy -c 'Print :keychain-access-groups' "$ENTITLEMENTS" >/dev/null 2>&1; then
  echo "Error: Release entitlement must not request Data Protection Keychain access groups." >&2
  exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$ENTITLEMENTS")" != "true" ]]; then
  echo "Error: App Sandbox must remain enabled." >&2
  exit 1
fi

cd "$PROJECT_ROOT"
if [[ "${STARFLOW_CLEAN_BUILD:-0}" == "1" ]]; then
  "$FLUTTER" clean
fi
BUILD_ARGS=(build macos --release --build-name "$VERSION" --dart-define "STARFLOW_BUILD_DATE=$BUILD_DATE")
if [[ "${STARFLOW_FORCE_PUB_GET:-0}" != "1" && -f "$PROJECT_ROOT/.dart_tool/package_config.json" ]]; then
  BUILD_ARGS+=(--no-pub)
fi
echo "Building Starflow macOS $VERSION with Flutter $ACTUAL_FLUTTER..."
"$FLUTTER" "${BUILD_ARGS[@]}"

APP_BUNDLE="$PROJECT_ROOT/build/macos/Build/Products/Release/Starflow.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Error: app bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
if [[ "$PLIST_VERSION" != "$VERSION" ]]; then
  echo "Error: app version mismatch: expected $VERSION, found $PLIST_VERSION." >&2
  exit 1
fi

# Flutter signs App.framework during assembly; refresh the outer seal after all assets are embedded.
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
SIGNED_ENTITLEMENTS="$(codesign -d --entitlements :- "$APP_BUNDLE" 2>/dev/null)"
if ! /usr/bin/grep -q '<key>com.apple.security.app-sandbox</key><true/>' <<<"$SIGNED_ENTITLEMENTS"; then
  echo "Error: signed app is missing the App Sandbox entitlement." >&2
  exit 1
fi
if /usr/bin/grep -q 'keychain-access-groups' <<<"$SIGNED_ENTITLEMENTS"; then
  echo "Error: signed app unexpectedly requests Keychain access groups." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_PATH="$OUTPUT_DIR/starflow-macos-$VERSION.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/starflow-macos-dmg.XXXXXX")"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT
ditto "$APP_BUNDLE" "$STAGING_DIR/Starflow.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname Starflow -srcfolder "$STAGING_DIR" -ov -format UDZO "$OUTPUT_PATH"
hdiutil verify "$OUTPUT_PATH"

echo "Version=$VERSION"
echo "App=$APP_BUNDLE"
echo "DMG=$OUTPUT_PATH"
echo "SHA256=$(shasum -a 256 "$OUTPUT_PATH" | awk '{print $1}')"
