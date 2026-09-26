#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DART="$PROJECT_ROOT/.fvm/flutter_sdk/bin/dart"

if [[ "${1:-}" == "--help" && $# -eq 1 ]]; then
  printf '%s\n' \
    'Local-only TV update staging; no build, version bump, or upload.' \
    'Usage: scripts/publish_update_release.sh --apk APK --notes NOTES.txt' \
    '  --artifact-url https://host/releases/VERSION_CODE/starflow-tv-VERSION.apk' \
    '  --stage-dir DIRECTORY' \
    'Optional: --published-at ISO-8601-UTC-Z' \
    'Uses the pinned .fvm/flutter_sdk and existing TV release verifier.' \
    'VERSION_CODE is the actual numeric APK versionCode; the URL parent must match it.' \
    'Stages VERSION_CODE/{starflow-tv-VERSION.apk,manifest.json}; switches latest.json last.' \
    'Deploy the staged immutable versionCode directory before latest.json using your host tooling.' \
    'Plain JSON manifest; HTTPS and Android APK signature checks remain required.' \
    'The app reads WebDAV sync directory/releases/latest.json using sync credentials.'
  exit 0
fi

has_stage=false
for arg in "$@"; do
  case "$arg" in
    --stage-dir) has_stage=true ;;
    --output) printf '%s\n' 'Publishing requires --stage-dir, not --output.' >&2; exit 2 ;;
  esac
done
if [[ "$has_stage" != true ]]; then
  printf '%s\n' 'An explicit local --stage-dir is required; use --help for usage.' >&2
  exit 2
fi
if [[ ! -x "$DART" ]]; then
  printf '%s\n' 'Pinned .fvm/flutter_sdk/bin/dart is missing; restore the pinned SDK.' >&2
  exit 1
fi

exec "$DART" "$PROJECT_ROOT/tool/generate_update_manifest.dart" "$@"
