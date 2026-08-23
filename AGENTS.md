# Starflow project instructions

## Android TV APK delivery

- For every user-facing Android TV APK, follow `scripts/build_tv_apk.ps1` and the release rules documented in `README.md`.
- Do not deliver raw `app-debug.apk`, `app-release.apk`, or an ad-hoc artifact name.
- Build a release APK, keep the Android 6.0 / API 23 compatibility target, and use `--android-skip-build-dependency-validation`.
- Let the preset increment the three-part version `major.month.sequence`: preserve the major version, use the current month, increment the sequence within that month, and reset the sequence to `0` when the month changes.
- Name the normal artifact `starflow-tv-major.month.sequence.apk` and the embedded-settings artifact `starflow-tv-config-major.month.sequence.apk`.
- Output the final artifact to the desktop by default. Embed settings only when the user explicitly supplies a settings JSON file.
- If PowerShell is unavailable, reproduce the preset behavior exactly instead of falling back to a raw `flutter build apk` artifact.

## Documentation synchronization

- When user-facing behavior changes, keep `README.md` and the relevant files under `docs/` aligned with the implementation in the same change.
- Treat `docs/architecture.md` as the source for component boundaries, `docs/development-network.md` as the source for runtime/build networking, and the two performance documents as the source for host and device measurements.
- Do not describe application logging as disabled: the legacy trace helpers are silent, while the structured local logger, Android native exit capture, preview, filtering, clearing, and export flows are active.
