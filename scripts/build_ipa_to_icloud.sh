#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ICLOUD_ROOT="${ICLOUD_ROOT:-$HOME/Library/Mobile Documents/com~apple~CloudDocs}"
ICLOUD_IPA_DIR="${ICLOUD_IPA_DIR:-$ICLOUD_ROOT/IPA}"

cd "$PROJECT_ROOT"

if [[ ! -f "pubspec.yaml" ]]; then
  echo "Error: pubspec.yaml not found in project root."
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Error: flutter command not found in PATH."
  exit 1
fi

APP_NAME="$(awk '/^name:[[:space:]]*/ {print $2; exit}' pubspec.yaml)"
VERSION_RAW="$(awk '/^version:[[:space:]]*/ {print $2; exit}' pubspec.yaml)"

if [[ -z "${APP_NAME:-}" || -z "${VERSION_RAW:-}" ]]; then
  echo "Error: failed to read app name/version from pubspec.yaml."
  exit 1
fi

VERSION="${VERSION_RAW%%+*}"
if [[ "$VERSION_RAW" == *"+"* ]]; then
  BUILD_NUMBER="${VERSION_RAW#*+}"
else
  BUILD_NUMBER="$(date +%Y%m%d%H%M%S)"
fi

echo "Building IPA for $APP_NAME ($VERSION+$BUILD_NUMBER)..."
flutter build ipa --release

shopt -s nullglob
IPA_CANDIDATES=(build/ios/ipa/*.ipa)
shopt -u nullglob

if [[ ${#IPA_CANDIDATES[@]} -eq 0 ]]; then
  echo "Error: no IPA artifact found under build/ios/ipa."
  exit 1
fi

SOURCE_IPA="${IPA_CANDIDATES[0]}"
OUTPUT_NAME="${APP_NAME}_v${VERSION}(${BUILD_NUMBER}).ipa"

mkdir -p "$ICLOUD_IPA_DIR"
cp -f "$SOURCE_IPA" "$ICLOUD_IPA_DIR/$OUTPUT_NAME"

echo "Done."
echo "Source IPA: $SOURCE_IPA"
echo "Copied to: $ICLOUD_IPA_DIR/$OUTPUT_NAME"
