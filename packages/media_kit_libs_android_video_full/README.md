# media_kit Android full build override

Verified against the working tree on 2026-09-20.

This local package keeps the public plugin identity of
`media_kit_libs_android_video` but downloads the upstream `full` libmpv build.
The default build omits FFmpeg's MLP and TrueHD decoders; the full build keeps
them so embedded MPV can decode TrueHD on Android phones and Android TV.

## Integration

The root [pubspec.yaml](../../pubspec.yaml) selects this package through
`dependency_overrides`. Its public name remains `media_kit_libs_android_video`
(package version `1.3.8`), with the upstream plugin class and Java helper intact.
The package directory name is not a replacement import name.

[android/build.gradle](android/build.gradle) pins upstream native release
`v1.1.8` and a separate SHA-256 for each full archive. These native release
numbers are independent of the Dart package version.

## Build Behavior

- `preBuild` runs `downloadDependencies`, verifies archive hashes and recreates
  the generated `output` directory. Cached archives live under the Gradle
  module's `$buildDir/v1.1.8/`, not in this source directory.
- The task processes `armeabi-v7a`, `arm64-v8a`, `x86` and `x86_64` archives even
  when the app only packages ARM. The TV release preset and app ABI filters
  determine the final APK contents: ARM32 and ARM64 in one APK, excluding x86_64.
- A hash mismatch deletes the bad cached archive and fails the build. Check
  connectivity and the pinned upstream asset before rerunning; do not remove
  validation or substitute an unverified binary.
- This module declares minSdk 23, compileSdk 35 and its own AGP 8.13.0. The app's
  current compileSdk is 36; module settings do not replace the app baseline.
- Downloads use build-time networking, not the installed app's runtime proxy.
  Avoid concurrent builds sharing the same generated output directory.

The native binaries are build-time downloads and are not checked into this
package. Playback does not download codecs. Updating the pinned release requires
updating all hashes, checking licensing, building both TV ABIs and validating
real device playback; a successful JVM test does not load these native decoders.

## Scope

This override supplies embedded MPV, including MLP / TrueHD support. It does not
change Android Media3 / ExoPlayer, whose separate local audio extension is
documented in [android/app/libs](../../android/app/libs/README.md), or guarantee
HDMI passthrough. The app does not currently override MPV's Android audio backend
or enable `audio-spdif` through the Exo audio-output menu.

See [network setup](../../docs/development-network.md),
[device validation](../../docs/performance-device.md) and the package
[license](LICENSE). User-facing TV APKs must follow the root release preset.
