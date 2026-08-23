#!/usr/bin/env bash

set -euo pipefail

if [[ $# -gt 0 ]]; then
  APP_BUNDLE="$1"
elif [[ "${PLATFORM_NAME:-}" == "iphoneos" ]]; then
  APP_BUNDLE="${TARGET_BUILD_DIR:?}/${WRAPPER_NAME:?}"
else
  exit 0
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: iOS app bundle not found for framework verification: $APP_BUNDLE" >&2
  exit 1
fi

FRAMEWORKS_DIR="$APP_BUNDLE/Frameworks"
if [[ ! -d "$FRAMEWORKS_DIR" ]]; then
  exit 0
fi

FAILED=0
while IFS= read -r -d '' framework; do
  executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$framework/Info.plist" 2>/dev/null || true)"
  if [[ -z "$executable_name" || ! -f "$framework/$executable_name" ]]; then
    continue
  fi

  binary="$framework/$executable_name"
  build_info="$(xcrun vtool -show-build "$binary" 2>/dev/null || true)"
  architectures="$(xcrun lipo -archs "$binary" 2>/dev/null || true)"

  if grep -q "platform IOSSIMULATOR" <<<"$build_info"; then
    echo "error: $(basename "$framework") contains an iOS-simulator binary in an iPhoneOS app." >&2
    FAILED=1
  fi
  if grep -qw "x86_64" <<<"$architectures"; then
    echo "error: $(basename "$framework") contains x86_64 in an iPhoneOS app." >&2
    FAILED=1
  fi

  if [[ "$(basename "$framework")" == "objective_c.framework" ]] &&
    ! grep -Eq 'platform[[:space:]]+IOS([[:space:]]|$)' <<<"$build_info"; then
    echo "error: objective_c.framework is not built for a physical iOS device." >&2
    FAILED=1
  fi
done < <(find "$FRAMEWORKS_DIR" -maxdepth 1 -type d -name '*.framework' -print0)

if [[ $FAILED -ne 0 ]]; then
  echo "error: Refusing to package an iOS app with incompatible frameworks." >&2
  exit 1
fi

echo "Verified iPhoneOS framework platforms in: $APP_BUNDLE"
