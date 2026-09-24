# Media3 FFmpeg audio decoder

Verified against the working tree on 2026-09-20. This is the Android ExoPlayer
audio extension, not the full libmpv dependency used by embedded MPV. Runtime
policy and historical fixes are documented in the
[audio review](../../../docs/reviews/audio-decoding-review-2026-09-19.md).

`media3-decoder-ffmpeg-1.10.1.aar` is built from the official AndroidX Media3
`1.10.1` source at commit `5fb306449733dd71595700c1227ad6087578c559` and
FFmpeg `release/6.0` commit `3f92512fd1fd6f5e6d6eb45a156c352835314d69`.

The `ac3`, `eac3`, `mlp`, `truehd`, `dca`, `mp1`, `mp2` and `mp3` audio decoders are
enabled. The AAR contains `armeabi-v7a` and `arm64-v8a` native libraries and
has SHA-256:

`9958a8f9d0cf507faf11a03ee97f35d193bc91ebf82348c8c2aa2af3a8c7196d`

Rebuild the native libraries from the repository root with the
[repository script](../../../scripts/rebuild_media3_audio.sh). It requires an
installed NDK (validated version: 28.2.13676358), Bash, curl, shasum, tar,
unzip/zip, make and ripgrep. It targets API 23 with 16 KiB ELF alignment and
preserves the existing AAR's Media3 Java classes. The checked-in AAR must
already exist; this script is not a full Java extension build from scratch.

```sh
ANDROID_NDK_HOME=/path/to/ndk/28.2.13676358 bash scripts/rebuild_media3_audio.sh /tmp/starflow-audio-build
```

For Linux set `NDK_HOST_TAG=linux-x86_64`; the default is `darwin-x86_64`.
Use a dedicated work directory and optionally pass an explicit output AAR as
the second argument. `JOBS` defaults to 4. Source archives and JNI source are
SHA-256 checked. Output defaults to the work directory and must be validated
before replacing this AAR. ZIP timestamps can change the rebuilt archive hash.
Media3 maps all MPEG Layer I/II/III MIME types to decoder name `mp3`, so enabling
only `mp1` and `mp2` is insufficient. Both ABI libraries were checked for decoder
and JNI symbols, API 23 and 16 KiB alignment; this is not an on-device decode test.

The app references this local AAR in `android/app/build.gradle.kts`. No decoder
is downloaded at playback time. There are no x86/x86_64 native FFmpeg libraries
in this AAR, so an x86 emulator cannot validate this extension's execution.
FFmpeg is always registered as an audio renderer candidate, but actual selection
depends on the input MIME, output policy and device capabilities. PCM mode does
not guarantee FFmpeg selection, stereo downmix or lossless high-bit-depth output.

After a deliberate replacement, update the SHA-256 here, run Android unit tests
and release Kotlin compilation, inspect both ABI libraries, and perform ARM
device playback checks. Rebuilding only this AAR is not an APK release; TV
delivery still follows the root README. The 2026-09-20 documentation pass checked
the existing archive hash but did not rebuild or replace it.

Media3 code is Apache-2.0 licensed. FFmpeg is configured as LGPL 2.1-or-later;
the corresponding [Media3](LICENSE-media3-apache-2.0.txt) and
[FFmpeg](LICENSE-ffmpeg-lgpl-2.1.txt) license texts are stored beside the AAR. The complete,
corresponding source is identified by the immutable commits above so the
library can be rebuilt or replaced independently of the application.
