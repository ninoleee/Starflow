# media_kit iOS full build override

Verified against the working tree on 2026-09-20.

This local package keeps the public plugin identity of
`media_kit_libs_ios_video` but downloads the upstream `full` libmpv build.
The default build omits FFmpeg's MLP and TrueHD decoders; the full build keeps
them so embedded MPV can decode TrueHD on iPhone and iPad.

## Integration

The root [pubspec.yaml](../../pubspec.yaml) selects this package through
`dependency_overrides`. Its public plugin name remains `media_kit_libs_ios_video`
(Dart package version `1.1.4`); the podspec retains pod version `1.0.4`. These
versions are separate from the native archive release.

The [podspec](ios/media_kit_libs_ios_video.podspec) invokes `make` during CocoaPods
installation. The [Makefile](ios/Makefile) pins the `v0.6.0` iOS universal
`video-full` XCFramework archive and verifies this SHA-256:

```text
652047297624170bfd172ef25a99e49603c032d189a1761335edcb36db55b7ee
```

## Build Behavior

- Building requires macOS, Xcode, CocoaPods, make, curl, tar and shasum, plus
  network access to the pinned media-kit GitHub release when the cache is empty.
- Download archives are cached in `ios/.cache/xcframeworks/`; extracted
  frameworks and generated symlinks live in `ios/Frameworks/`. These are local
  generated dependencies, not source assets to edit or commit.
- `create_framework_symlinks.sh` constructs the MPV framework symlink layout
  expected by the plugin. Preserve that step when updating the upstream build.
- The pod declares iOS 9.0, but Starflow's application deployment target is
  iOS 13.0. The pod's lower value does not make the app installable on iOS 9.
- Do not replace a hash to silence a failed download. An intentional native
  release update requires reviewing the archive, slices, licenses and playback.

The [iOS release preset](../../scripts/build_ipa_to_icloud.sh) cleans stale
simulator Native Assets and verifies device frameworks before packaging an
unsigned IPA. `prepare_ios_device_build.sh` and
`verify_ios_device_frameworks.sh` are the corresponding checks. The script
changes the app version and cleans the build, so it is not a read-only check.

## Scope

This dependency supplies full libmpv to embedded MPV only. It does not add codecs,
dual subtitles or online subtitle mounting to system AVPlayer, and it does not
replace the macOS MPV dependency. Native downloads occur at build time, not when
opening a video.

See [architecture](../../docs/architecture.md),
[device validation](../../docs/performance-device.md) and [license](LICENSE).
The documentation pass did not rebuild the XCFrameworks or claim device decode
validation.
