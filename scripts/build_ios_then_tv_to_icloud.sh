#!/usr/bin/env bash
#
# Build the iOS IPA first, then build the Android TV APK and copy both
# artifacts into iCloud Drive through the existing platform scripts.
#
# Usage:
#   ./scripts/build_ios_then_tv_to_icloud.sh
#   ./scripts/build_ios_then_tv_to_icloud.sh path/to/settings.json
#
# The optional settings JSON is passed to the TV build only, which embeds it
# in the config APK. The iOS build remains the normal unsigned IPA build.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [path/to/settings.json]" >&2
  exit 1
fi

SETTINGS_JSON_PATH="${1:-}"
if [[ -n "$SETTINGS_JSON_PATH" ]]; then
  if [[ ! -f "$SETTINGS_JSON_PATH" ]]; then
    echo "Error: settings JSON not found: $SETTINGS_JSON_PATH" >&2
    exit 1
  fi
  SETTINGS_JSON_PATH="$(cd "$(dirname "$SETTINGS_JSON_PATH")" && pwd)/$(basename "$SETTINGS_JSON_PATH")"
fi

if [[ -z "${STARFLOW_FLUTTER_SDK:-}" && -d "$PROJECT_ROOT/.fvm/flutter_sdk" ]]; then
  STARFLOW_FLUTTER_SDK="$PROJECT_ROOT/.fvm/flutter_sdk"
fi
if [[ -n "${STARFLOW_FLUTTER_SDK:-}" ]]; then
  FLUTTER="${STARFLOW_FLUTTER_SDK}/bin/flutter"
  if [[ ! -x "$FLUTTER" ]]; then
    echo "Error: Flutter SDK not found: $STARFLOW_FLUTTER_SDK" >&2
    exit 1
  fi
  export STARFLOW_FLUTTER_SDK="$(cd "$(dirname "$FLUTTER")/.." && pwd)"
  export PATH="$STARFLOW_FLUTTER_SDK/bin:$PATH"
elif ! command -v flutter >/dev/null 2>&1; then
  echo "Error: flutter command not found in PATH." >&2
  exit 1
fi

cd "$PROJECT_ROOT"

echo "==> Building iOS IPA and copying it to iCloud..."
bash "$SCRIPT_DIR/build_ipa_to_icloud.sh"

# The iOS script advances the release version once. Keep that exact version
# for TV so one combined release produces matching artifact names without
# bypassing the TV preflight rule against fixed release versions.
export STARFLOW_KEEP_RELEASE_VERSION=1

echo "==> iOS build complete. Building Android TV APK and copying it to iCloud..."
if [[ -n "$SETTINGS_JSON_PATH" ]]; then
  bash "$SCRIPT_DIR/build_tv_apk_to_icloud.sh" "$SETTINGS_JSON_PATH"
else
  bash "$SCRIPT_DIR/build_tv_apk_to_icloud.sh"
fi

echo "==> iOS and Android TV artifacts are ready in iCloud."
