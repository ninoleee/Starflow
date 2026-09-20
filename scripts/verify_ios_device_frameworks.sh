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

if [[ "$APP_BUNDLE" != *.app || ! -f "$APP_BUNDLE/Info.plist" ]]; then
  echo "error: Expected a complete .app bundle: $APP_BUNDLE" >&2
  exit 1
fi
app_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_BUNDLE/Info.plist")"
if [[ -z "$app_executable" || ! -f "$APP_BUNDLE/$app_executable" ]]; then
  echo "error: App executable is missing." >&2
  exit 1
fi

FRAMEWORKS_DIR="$APP_BUNDLE/Frameworks"
if [[ ! -d "$FRAMEWORKS_DIR" ]]; then
  echo "error: Flutter app Frameworks directory is missing." >&2
  exit 1
fi
for required in App Flutter; do
  if [[ ! -d "$FRAMEWORKS_DIR/$required.framework" ]]; then
    echo "error: Required $required.framework is missing." >&2
    exit 1
  fi
done

FAILED=0
while IFS= read -r -d '' framework; do
  executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$framework/Info.plist")"
  if [[ -z "$executable_name" || ! -f "$framework/$executable_name" ]]; then
    echo "error: Framework executable is missing: $framework" >&2
    FAILED=1
    continue
  fi

  binary="$framework/$executable_name"
  build_info="$(xcrun vtool -show-build "$binary")"
  architectures="$(xcrun lipo -archs "$binary")"
  load_commands="$(xcrun otool -l "$binary")"

  if ! grep -qw "arm64" <<<"$architectures" ||
    grep -Eq '(^|[[:space:]])(i386|x86_64)([[:space:]]|$)' <<<"$architectures"; then
    echo "error: $(basename "$framework") lacks a valid device architecture: $architectures" >&2
    FAILED=1
  fi
  if ! grep -Eq 'platform[[:space:]]+IOS([[:space:]]|$)' <<<"$build_info" &&
    ! grep -q 'LC_VERSION_MIN_IPHONEOS' <<<"$load_commands"; then
    echo "error: $(basename "$framework") has no iPhoneOS platform declaration." >&2
    FAILED=1
  fi

  if grep -q "platform IOSSIMULATOR" <<<"$build_info"; then
    echo "error: $(basename "$framework") contains an iOS-simulator binary in an iPhoneOS app." >&2
    FAILED=1
  fi
  if grep -qw "x86_64" <<<"$architectures"; then
    echo "error: $(basename "$framework") contains x86_64 in an iPhoneOS app." >&2
    FAILED=1
  fi

done < <(find "$FRAMEWORKS_DIR" -maxdepth 1 -type d -name '*.framework' -print0)

if [[ $FAILED -ne 0 ]]; then
  echo "error: Refusing to package an iOS app with incompatible frameworks." >&2
  exit 1
fi

echo "Verified iPhoneOS framework platforms in: $APP_BUNDLE"
