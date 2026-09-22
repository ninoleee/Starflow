#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ICLOUD_ROOT="${ICLOUD_ROOT:-$HOME/Library/Mobile Documents/com~apple~CloudDocs}"
ICLOUD_INSTALLER_DIR="${ICLOUD_INSTALLER_DIR:-$ICLOUD_ROOT/Installers}"

cd "$PROJECT_ROOT"

if [[ ! -f "pubspec.yaml" ]]; then
  echo "Error: pubspec.yaml not found in project root."
  exit 1
fi

if [[ -z "${STARFLOW_FLUTTER_SDK:-}" && -d "$PROJECT_ROOT/.fvm/flutter_sdk" ]]; then
  STARFLOW_FLUTTER_SDK="$PROJECT_ROOT/.fvm/flutter_sdk"
fi
if [[ -n "${STARFLOW_FLUTTER_SDK:-}" ]]; then
  FLUTTER="$STARFLOW_FLUTTER_SDK/bin/flutter"
  DART="$STARFLOW_FLUTTER_SDK/bin/dart"
  if [[ ! -x "$FLUTTER" || ! -x "$DART" ]]; then
    echo "Error: Flutter SDK not found: $STARFLOW_FLUTTER_SDK" >&2
    exit 1
  fi
  export STARFLOW_FLUTTER_SDK="$(cd "$(dirname "$FLUTTER")/.." && pwd)"
  export PATH="$STARFLOW_FLUTTER_SDK/bin:$PATH"
else
  FLUTTER="$(command -v flutter)" || {
    echo "Error: flutter command not found in PATH."
    exit 1
  }
  DART="$(dirname "$FLUTTER")/dart"
fi


APP_NAME="$(awk '/^name:[[:space:]]*/ {print $2; exit}' pubspec.yaml)"

if [[ -z "${APP_NAME:-}" ]]; then
  echo "Error: failed to read app name from pubspec.yaml."
  exit 1
fi

VERSION="$("$DART" "$PROJECT_ROOT/tool/release_version.dart" pubspec.yaml)"
BUILD_NUMBER="$VERSION"
BUILD_DATE="$(date +%Y-%m-%d)"
OUTPUT_NAME="${APP_NAME}_v${VERSION}_unsigned.ipa"
FAST_IPA_DIR="build/ios/ipa_fast"
BUILD_ARGS=(
  "$FLUTTER"
  build
  ios
)
if [[ "${STARFLOW_CLEAN_BUILD:-0}" != "1" &&
      "${STARFLOW_FORCE_PUB_GET:-0}" != "1" &&
      -f "$PROJECT_ROOT/.dart_tool/package_config.json" ]]; then
  BUILD_ARGS+=(--no-pub)
  echo "Skipping dependency resolution; use STARFLOW_FORCE_PUB_GET=1 after dependency changes."
fi

echo "Building unsigned IPA for $APP_NAME ($VERSION+$BUILD_NUMBER, $BUILD_DATE)..."
if [[ "${STARFLOW_CLEAN_BUILD:-0}" == "1" ]]; then
  echo "Cleaning cached Flutter and iOS Native Assets..."
  "$FLUTTER" clean
else
  echo "Using incremental Flutter and iOS build caches."
fi

BUILD_ARGS+=(
  --release
  --no-codesign
  --build-name "$VERSION"
  --build-number "$BUILD_NUMBER"
  --dart-define "STARFLOW_BUILD_DATE=$BUILD_DATE"
)
"${BUILD_ARGS[@]}"

APP_BUNDLE="build/ios/iphoneos/Runner.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Error: app bundle not found: $APP_BUNDLE"
  exit 1
fi
/bin/bash "$PROJECT_ROOT/scripts/verify_ios_device_frameworks.sh" "$APP_BUNDLE"

mkdir -p "$FAST_IPA_DIR"
SOURCE_IPA="$FAST_IPA_DIR/$OUTPUT_NAME"
PACKAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/starflow-ipa.XXXXXX")"
trap 'rm -rf "$PACKAGE_DIR"' EXIT
mkdir -p "$PACKAGE_DIR/Payload"
ditto "$APP_BUNDLE" "$PACKAGE_DIR/Payload/Runner.app"
(cd "$PACKAGE_DIR" && zip -qry "$PROJECT_ROOT/$SOURCE_IPA" Payload)

mkdir -p "$ICLOUD_INSTALLER_DIR"
cp -f "$SOURCE_IPA" "$ICLOUD_INSTALLER_DIR/$OUTPUT_NAME"

echo "Done."
echo "Source IPA: $SOURCE_IPA"
echo "Copied to: $ICLOUD_INSTALLER_DIR/$OUTPUT_NAME"
