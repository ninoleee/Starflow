#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ICLOUD_ROOT="${ICLOUD_ROOT:-$HOME/Library/Mobile Documents/com~apple~CloudDocs}"
ICLOUD_IPA_DIR="${ICLOUD_IPA_DIR:-$ICLOUD_ROOT/IPA}"
EXPORT_METHOD="${EXPORT_METHOD:-development}"
ARCHIVE="${ARCHIVE:-0}"

cd "$PROJECT_ROOT"

if [[ ! -f "pubspec.yaml" ]]; then
  echo "Error: pubspec.yaml not found in project root."
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Error: flutter command not found in PATH."
  exit 1
fi

update_pubspec_version() {
  local pubspec_path="$1"
  local version_line
  local major
  local current_month_in_version
  local current_sequence
  local month
  local next_sequence
  local next_version

  version_line="$(awk '/^version:[[:space:]]*/ {print $0; exit}' "$pubspec_path")"
  if [[ ! "$version_line" =~ ^version:[[:space:]]*([0-9]+)\.([0-9]+)\.([0-9]+)(\+[0-9]+)?[[:space:]]*$ ]]; then
    echo "Error: unable to parse version from $pubspec_path." >&2
    exit 1
  fi

  major="${BASH_REMATCH[1]}"
  current_month_in_version="${BASH_REMATCH[2]}"
  current_sequence="${BASH_REMATCH[3]}"
  month="$(date +%-m)"

  if [[ "$current_month_in_version" == "$month" ]]; then
    next_sequence=$((10#$current_sequence + 1))
  else
    next_sequence=0
  fi

  next_version="${major}.${month}.${next_sequence}"
  perl -0pi -e "s/^version:\\s*\\d+\\.\\d+\\.\\d+(?:\\+\\d+)?\\s*$/version: ${next_version}/m" "$pubspec_path"
  printf '%s\n' "$next_version"
}

APP_NAME="$(awk '/^name:[[:space:]]*/ {print $2; exit}' pubspec.yaml)"

if [[ -z "${APP_NAME:-}" ]]; then
  echo "Error: failed to read app name from pubspec.yaml."
  exit 1
fi

VERSION="$(update_pubspec_version pubspec.yaml)"
BUILD_NUMBER="$VERSION"
BUILD_DATE="$(date +%Y-%m-%d)"
OUTPUT_NAME="${APP_NAME}_v${VERSION}.ipa"
FAST_IPA_DIR="build/ios/ipa_fast"

echo "Building IPA for $APP_NAME ($VERSION+$BUILD_NUMBER, $BUILD_DATE)..."
if [[ "$ARCHIVE" == "1" ]]; then
  flutter build ipa \
    --release \
    --export-method "$EXPORT_METHOD" \
    --build-name "$VERSION" \
    --build-number "$BUILD_NUMBER" \
    --dart-define "STARFLOW_BUILD_DATE=$BUILD_DATE"

  shopt -s nullglob
  IPA_CANDIDATES=(build/ios/ipa/*.ipa)
  shopt -u nullglob

  if [[ ${#IPA_CANDIDATES[@]} -eq 0 ]]; then
    echo "Error: no IPA artifact found under build/ios/ipa."
    exit 1
  fi

  SOURCE_IPA="${IPA_CANDIDATES[0]}"
else
  flutter build ios \
    --release \
    --build-name "$VERSION" \
    --build-number "$BUILD_NUMBER" \
    --dart-define "STARFLOW_BUILD_DATE=$BUILD_DATE"

  APP_BUNDLE="build/ios/iphoneos/Runner.app"
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Error: app bundle not found: $APP_BUNDLE"
    exit 1
  fi

  mkdir -p "$FAST_IPA_DIR"
  SOURCE_IPA="$FAST_IPA_DIR/$OUTPUT_NAME"
  PACKAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/starflow-ipa.XXXXXX")"
  trap 'rm -rf "$PACKAGE_DIR"' EXIT
  mkdir -p "$PACKAGE_DIR/Payload"
  ditto "$APP_BUNDLE" "$PACKAGE_DIR/Payload/Runner.app"
  (cd "$PACKAGE_DIR" && zip -qry "$PROJECT_ROOT/$SOURCE_IPA" Payload)
fi

mkdir -p "$ICLOUD_IPA_DIR"
cp -f "$SOURCE_IPA" "$ICLOUD_IPA_DIR/$OUTPUT_NAME"

echo "Done."
echo "Source IPA: $SOURCE_IPA"
echo "Copied to: $ICLOUD_IPA_DIR/$OUTPUT_NAME"
