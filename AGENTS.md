# Starflow project instructions

## Flutter SDK consistency

- Use the SDK pinned by `.fvmrc` through `.fvm/flutter_sdk` for dependency resolution, tests, analysis, and builds, not only TV release builds.
- Keep Flutter and Dart from the same SDK. After changing SDKs, run that SDK's `flutter pub get` before testing; do not manually edit `.dart_tool/package_config.json`.
- Do not run different Flutter SDK versions or `flutter clean` concurrently in the same checkout. Coordinate shared builds or use a separate checkout for incompatible toolchains.

## Android TV APK delivery

- For every user-facing Android TV APK, follow `scripts/build_tv_apk.ps1` and the release rules documented in `README.md`.
- Do not deliver raw `app-debug.apk`, `app-release.apk`, or an ad-hoc artifact name.
- Build a release APK, keep the Android 6.0 / API 23 compatibility target, and use `--android-skip-build-dependency-validation`.
- TV APKs must use `--target-platform android-arm,android-arm64`, keeping ARM 32-bit and ARM64 in one APK and excluding x86_64.
- Let the preset increment the three-part version `major.month.sequence`: preserve the major version, use the current month, increment the sequence within that month, and reset the sequence to `0` when the month changes.
- Name the normal artifact `starflow-tv-major.month.sequence.apk` and the embedded-settings artifact `starflow-tv-config-major.month.sequence.apk`.
- Output the final artifact to the desktop by default. Embed settings only when the user explicitly supplies a settings JSON file.
- If PowerShell is unavailable, reproduce the preset behavior exactly instead of falling back to a raw `flutter build apk` artifact.

## Documentation synchronization

- When user-facing behavior changes, keep `README.md` and the relevant files under `docs/` aligned with the implementation in the same change.
- Treat `docs/architecture.md` as the source for component boundaries, `docs/development-network.md` as the source for runtime/build networking, and the two performance documents as the source for host and device measurements.
- Do not describe application logging as disabled: the legacy trace helpers are silent, while the structured local logger, Android native exit capture, preview, filtering, clearing, and export flows are active.
- Use `docs/code-map.md` for source navigation and `docs/subtitles.md` for subtitle pipeline boundaries. Keep dependency and resource READMEs scoped to the files they describe.
- Record verification dates and distinguish host smoke/JVM/Swift strategy checks from real-device measurements. Keep historical review findings labeled as pre-fix snapshots when the implementation has changed; never turn an old test result into a current all-green claim.
- Update authored Markdown, not generated dependency/build documentation. Documentation-only work should not invoke release presets that increment `pubspec.yaml` or regenerate binary assets.
