# Media3 FFmpeg audio decoder

`media3-decoder-ffmpeg-1.10.1.aar` is built from the official AndroidX Media3
`1.10.1` source at commit `5fb306449733dd71595700c1227ad6087578c559` and
FFmpeg `release/6.0` commit `3f92512fd1fd6f5e6d6eb45a156c352835314d69`.

The `ac3`, `eac3`, `mlp`, `truehd`, `dca`, `mp1` and `mp2` audio decoders are
enabled. The AAR contains `armeabi-v7a` and `arm64-v8a` native libraries and
has SHA-256:

`b0832a9c20f54d923b96128db0c9d2cada2f5626de57eb0b155e4da0110586a6`

Rebuild it with the official Media3
`libraries/decoder_ffmpeg/src/main/jni/build_ffmpeg.sh` instructions, Android
API 23, and FFmpeg arguments `ac3 eac3 mlp truehd dca mp1 mp2`, then run:

```text
./gradlew :lib-decoder-ffmpeg:assembleRelease
```

Media3 code is Apache-2.0 licensed. FFmpeg is configured as LGPL 2.1-or-later;
the corresponding license texts are stored beside the AAR. The complete,
corresponding source is identified by the immutable commits above so the
library can be rebuilt or replaced independently of the application.
