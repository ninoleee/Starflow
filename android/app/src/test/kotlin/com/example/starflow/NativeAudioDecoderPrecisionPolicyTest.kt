package com.example.starflow

import androidx.media3.common.MimeTypes
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeAudioDecoderPrecisionPolicyTest {
    @Test
    fun ac3DoesNotTriggerFloatRestoration() {
        assertFalse(shouldRestore(MimeTypes.AUDIO_AC3, "ffmpeg6.0-ac3"))
        assertFalse(shouldRestore(MimeTypes.AUDIO_AC3, "FFmpeg6.0-ac3"))
    }

    @Test
    fun codecsMappedToBundledDecodersCanRestoreFloat() {
        val candidates = listOf(
            MimeTypes.AUDIO_E_AC3 to "eac3",
            MimeTypes.AUDIO_E_AC3_JOC to "eac3",
            MimeTypes.AUDIO_TRUEHD to "truehd",
            MimeTypes.AUDIO_DTS to "dca",
            MimeTypes.AUDIO_DTS_HD to "dca",
            MimeTypes.AUDIO_MPEG to "mp3",
            MimeTypes.AUDIO_MPEG_L1 to "mp3",
            MimeTypes.AUDIO_MPEG_L2 to "mp3",
        )
        for ((mime, codec) in candidates) {
            assertTrue(mime, shouldRestore(mime, "ffmpeg6.0-$codec"))
        }
        assertTrue(shouldRestore(MimeTypes.AUDIO_E_AC3, "FFmpeg6.0-eac3"))
    }

    @Test
    fun absentUnknownNonAudioAndRawSourcesDoNotRestoreFloat() {
        for (mime in listOf(
            null,
            "",
            "audio/unknown",
            "audio/x-unknown",
            "audio/mlp",
            "audio/vnd.dts.uhd",
            "application/octet-stream",
            MimeTypes.VIDEO_H264,
            MimeTypes.AUDIO_RAW,
        )) {
            assertFalse("source=$mime", shouldRestore(mime, "ffmpeg6.0-dca"))
        }
    }

    @Test
    fun upstreamMappingsDoNotImplyDecodersAreBundled() {
        for (mime in listOf(
            MimeTypes.AUDIO_AAC,
            MimeTypes.AUDIO_VORBIS,
            MimeTypes.AUDIO_OPUS,
            MimeTypes.AUDIO_AMR_NB,
            MimeTypes.AUDIO_AMR_WB,
            MimeTypes.AUDIO_FLAC,
            MimeTypes.AUDIO_ALAC,
            MimeTypes.AUDIO_MLAW,
            MimeTypes.AUDIO_ALAW,
        )) {
            assertFalse(mime, shouldRestore(mime, "ffmpeg6.0-aac"))
        }
    }

    @Test
    fun absentOrNonFfmpegDecoderDoesNotRestoreFloat() {
        for (decoder in listOf(
            "",
            "unknown",
            "c2.android.eac3.decoder",
            "OMX.google.eac3.decoder",
            "MediaCodec",
            "c2.vendor.ffmpeg.eac3.decoder",
            "not-ffmpeg6.0-eac3",
        )) {
            assertFalse(decoder, shouldRestore(MimeTypes.AUDIO_E_AC3, decoder))
        }
    }

    private fun shouldRestore(sourceMime: String?, decoderName: String): Boolean =
        NativeAudioDecoderPrecisionPolicy.shouldRestoreFloat(sourceMime, decoderName)
}
