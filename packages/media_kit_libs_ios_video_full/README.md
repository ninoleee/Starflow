# media_kit iOS full build override

This local package keeps the public plugin identity of
`media_kit_libs_ios_video` but downloads the upstream `full` libmpv build.
The default build omits FFmpeg's MLP and TrueHD decoders; the full build keeps
them so embedded MPV can decode TrueHD on iPhone and iPad.

The XCFramework archive is downloaded from the upstream media-kit release and
verified with SHA-256 during CocoaPods installation. It is not checked into
this project.
