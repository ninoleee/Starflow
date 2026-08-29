package com.example.starflow

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativePlaybackAudioPolicyTest {
    @Test
    fun `forces pcm for eac3 family on television`() {
        for (codec in listOf("eac3", "EAC3_JOC", "ec-3", "ddp", "ddplus")) {
            assertTrue(
                "Expected PCM output for $codec",
                NativePlaybackAudioPolicy.shouldForcePcmOutput(
                    isTelevision = true,
                    audioCodec = codec,
                ),
            )
        }
    }

    @Test
    fun `keeps normal routing for other television audio codecs`() {
        for (codec in listOf("aac", "ac3", "dts", "truehd", "opus", "")) {
            assertFalse(
                "Expected normal output routing for $codec",
                NativePlaybackAudioPolicy.shouldForcePcmOutput(
                    isTelevision = true,
                    audioCodec = codec,
                ),
            )
        }
    }

    @Test
    fun `does not change phone audio routing`() {
        assertFalse(
            NativePlaybackAudioPolicy.shouldForcePcmOutput(
                isTelevision = false,
                audioCodec = "eac3",
            ),
        )
    }

    @Test
    fun `pcm compatibility always forces decoded output`() {
        assertTrue(
            NativePlaybackAudioPolicy.shouldForcePcmOutput(
                isTelevision = false,
                audioCodec = "aac",
                outputMode = NativeAudioOutputMode.PCM_COMPATIBILITY,
            ),
        )
    }

    @Test
    fun `device passthrough never forces pcm`() {
        assertFalse(
            NativePlaybackAudioPolicy.shouldForcePcmOutput(
                isTelevision = true,
                audioCodec = "eac3",
                outputMode = NativeAudioOutputMode.DEVICE_PASSTHROUGH,
            ),
        )
    }

    @Test
    fun `ffmpeg decoder is enabled only for forced ac3 family audio`() {
        assertTrue(
            NativePlaybackAudioPolicy.shouldEnableFfmpegAudioDecoder(
                forcePcmAudioOutput = true,
                audioCodec = "eac3",
            ),
        )
        assertFalse(
            NativePlaybackAudioPolicy.shouldEnableFfmpegAudioDecoder(
                forcePcmAudioOutput = false,
                audioCodec = "eac3",
            ),
        )
        assertFalse(
            NativePlaybackAudioPolicy.shouldEnableFfmpegAudioDecoder(
                forcePcmAudioOutput = true,
                audioCodec = "aac",
            ),
        )
    }

    @Test
    fun `ffmpeg decoder is always enabled for truehd family audio`() {
        for (codec in listOf("truehd", "TrueHD", "truehd atmos", "mlp", "mha")) {
            assertTrue(
                "Expected FFmpeg decoder for $codec",
                NativePlaybackAudioPolicy.shouldEnableFfmpegAudioDecoder(
                    forcePcmAudioOutput = false,
                    audioCodec = codec,
                ),
            )
        }
    }

    @Test
    fun `ffmpeg decoder is always enabled for dts family audio`() {
        for (codec in listOf("dts", "DTS", "dtshd", "dts-hd", "dts hd ma", "dca")) {
            assertTrue(
                "Expected FFmpeg decoder for $codec",
                NativePlaybackAudioPolicy.shouldEnableFfmpegAudioDecoder(
                    forcePcmAudioOutput = false,
                    audioCodec = codec,
                ),
            )
        }
    }

    @Test
    fun `ffmpeg decoder is always enabled for mpeg layer 1 and 2 audio`() {
        for (codec in listOf("mp1", "mp2", "mpa")) {
            assertTrue(
                "Expected FFmpeg decoder for $codec",
                NativePlaybackAudioPolicy.shouldEnableFfmpegAudioDecoder(
                    forcePcmAudioOutput = false,
                    audioCodec = codec,
                ),
            )
        }
        assertFalse(
            NativePlaybackAudioPolicy.shouldEnableFfmpegAudioDecoder(
                forcePcmAudioOutput = false,
                audioCodec = "mp3",
            ),
        )
    }
}
