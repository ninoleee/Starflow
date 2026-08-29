# media_kit Android full build override

This local package keeps the public plugin identity of
`media_kit_libs_android_video` but downloads the upstream `full` libmpv build.
The default build omits FFmpeg's MLP and TrueHD decoders; the full build keeps
them so embedded MPV can decode TrueHD on Android phones and Android TV.

The binaries are downloaded from the upstream media-kit release and verified
with SHA-256 during the Android build. They are not checked into this project.
