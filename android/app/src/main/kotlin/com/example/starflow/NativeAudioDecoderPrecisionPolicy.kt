package com.example.starflow

import androidx.media3.common.MimeTypes

internal object NativeAudioDecoderPrecisionPolicy {
    // Intersection of Media3 1.10.1 FfmpegLibrary MIME mappings and the decoders
    // enabled in scripts/rebuild_media3_audio.sh, excluding AC3's PCM16 output.
    private val floatCandidateMimes = setOf(
        MimeTypes.AUDIO_E_AC3,
        MimeTypes.AUDIO_E_AC3_JOC,
        MimeTypes.AUDIO_TRUEHD,
        MimeTypes.AUDIO_DTS,
        MimeTypes.AUDIO_DTS_HD,
        MimeTypes.AUDIO_MPEG,
        MimeTypes.AUDIO_MPEG_L1,
        MimeTypes.AUDIO_MPEG_L2,
    )

    // A candidate to retry, not a guarantee of float support or lossless output.
    // The caller still gates on speed/pitch, output mode and sink capabilities.
    fun shouldRestoreFloat(sourceMime: String?, decoderName: String): Boolean {
        // FfmpegAudioDecoder.getName() returns "ffmpeg" + version + "-" + codec.
        return decoderName.startsWith("ffmpeg", ignoreCase = true) &&
            sourceMime in floatCandidateMimes
    }
}
