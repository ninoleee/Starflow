#!/usr/bin/env bash

set -euo pipefail

if [[ "${PLATFORM_NAME:-}" != "iphoneos" ]]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ ! -f "$PROJECT_ROOT/pubspec.yaml" ]]; then
  echo "error: Refusing to clean iOS Native Assets outside the Flutter project." >&2
  exit 1
fi

NATIVE_BINARY="$PROJECT_ROOT/build/native_assets/ios/objective_c.framework/objective_c"
if [[ ! -f "$NATIVE_BINARY" ]]; then
  exit 0
fi

BUILD_INFO="$(xcrun vtool -show-build "$NATIVE_BINARY" 2>/dev/null || true)"
if ! grep -q "platform IOSSIMULATOR" <<<"$BUILD_INFO"; then
  exit 0
fi

echo "warning: Removing cached iOS-simulator Native Assets before an iPhoneOS build."
GENERATED_PATHS=(
  "$PROJECT_ROOT/build/native_assets/ios"
  "$PROJECT_ROOT/.dart_tool/flutter_build"
  "$PROJECT_ROOT/.dart_tool/hooks_runner"
  "$PROJECT_ROOT/.dart_tool/native_assets"
)

for generated_path in "${GENERATED_PATHS[@]}"; do
  case "$generated_path" in
    "$PROJECT_ROOT"/*) ;;
    *)
      echo "error: Unsafe generated path: $generated_path" >&2
      exit 1
      ;;
  esac
  rm -rf -- "$generated_path"
done
