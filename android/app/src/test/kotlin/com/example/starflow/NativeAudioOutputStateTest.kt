package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackParameters
import androidx.media3.exoplayer.audio.AudioSink
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class NativeAudioOutputStateTest {
    @Test fun configureRetainsReusedTrackAndRecordsAttemptedInput() {
        val state = NativeAudioOutputState()
        val track = track(C.ENCODING_PCM_FLOAT)
        val initialInput = pcm(C.ENCODING_PCM_24BIT)
        state.onSinkConfigured(initialInput)
        state.onAudioTrackInitialized(track)
        val before = state.snapshot

        val sameOutputInput = initialInput.buildUpon().setId("next-track").build()
        state.onSinkConfigured(sameOutputInput)
        assertSame(sameOutputInput, state.sinkInput)
        assertSame(track, state.snapshot.activeOutput)
        assertEquals(C.ENCODING_PCM_FLOAT, state.outputEncoding)
        assertTrue(state.needsPrecisionChange(true, false))

        // The configure callback precedes the delegate: failure produces no initialized event.
        val failedAttempt = pcm(C.ENCODING_PCM_16BIT)
        state.onSinkConfigured(failedAttempt)
        assertSame(failedAttempt, state.snapshot.sinkInput)
        assertSame(track, state.snapshot.activeOutput)
        assertEquals(C.ENCODING_PCM_FLOAT, state.outputEncoding)
        assertSame(initialInput, before.sinkInput)
        assertSame(track, before.activeOutput)
    }

    @Test fun activeOutputDeterminesPassthroughWhileNextInputIsPending() {
        val state = NativeAudioOutputState()
        state.onSinkConfigured(source(MimeTypes.AUDIO_DTS))
        assertTrue(state.isPassthrough())
        val compressedTrack = track(C.ENCODING_DTS)
        state.onAudioTrackInitialized(compressedTrack)
        state.onSinkConfigured(pcm(C.ENCODING_PCM_16BIT))
        assertTrue(state.isPassthrough())

        state.onAudioTrackInitialized(track(C.ENCODING_PCM_16BIT))
        state.onAudioTrackReleased(compressedTrack)
        state.onSinkConfigured(source(MimeTypes.AUDIO_DTS))
        assertFalse(state.isPassthrough())
    }

    @Test fun releasingOldTrackDoesNotInvalidateNewOutput() {
        val state = NativeAudioOutputState()
        state.onSinkConfigured(pcm(C.ENCODING_PCM_16BIT))
        state.onAudioTrackInitialized(track(C.ENCODING_PCM_FLOAT))
        val current = track(C.ENCODING_PCM_16BIT)
        state.onAudioTrackInitialized(current)
        state.onAudioTrackReleased(track(C.ENCODING_PCM_FLOAT))
        assertSame(current, state.snapshot.activeOutput)
        assertEquals(C.ENCODING_PCM_16BIT, state.outputEncoding)
        state.onAudioTrackReleased(track(C.ENCODING_PCM_16BIT))
        assertNull(state.snapshot.activeOutput)
        assertNull(state.outputEncoding)
        assertNotNull(state.sinkInput)
    }

    @Test fun sameConfigurationReleasesConsumeOldestGenerationFirst() {
        val state = NativeAudioOutputState()
        state.onAudioTrackInitialized(track(C.ENCODING_PCM_FLOAT))
        val current = track(C.ENCODING_PCM_FLOAT)
        state.onAudioTrackInitialized(current)
        state.onAudioTrackReleased(track(C.ENCODING_PCM_FLOAT))
        assertSame(current, state.snapshot.activeOutput)
        assertEquals(C.ENCODING_PCM_FLOAT, state.outputEncoding)
        state.onAudioTrackReleased(track(C.ENCODING_PCM_FLOAT))
        assertNull(state.outputEncoding)
    }

    @Test fun releasesMatchCompleteConfigurationAndIgnoreUnknownTracks() {
        val state = NativeAudioOutputState()
        val current = track(C.ENCODING_PCM_FLOAT)
        state.onAudioTrackInitialized(current)
        val nonMatching = listOf(
            AudioSink.AudioTrackConfig(C.ENCODING_PCM_FLOAT, 96_000, 12, false, false, 4096),
            AudioSink.AudioTrackConfig(C.ENCODING_PCM_FLOAT, 48_000, 16, false, false, 4096),
            AudioSink.AudioTrackConfig(C.ENCODING_PCM_FLOAT, 48_000, 12, true, false, 4096),
            AudioSink.AudioTrackConfig(C.ENCODING_PCM_FLOAT, 48_000, 12, false, true, 4096),
            AudioSink.AudioTrackConfig(C.ENCODING_PCM_FLOAT, 48_000, 12, false, false, 8192),
        )
        nonMatching.forEach(state::onAudioTrackReleased)
        assertSame(current, state.snapshot.activeOutput)
        state.onAudioTrackReleased(track(C.ENCODING_PCM_FLOAT))
        assertNull(state.outputEncoding)
    }

    @Test fun releasingCurrentTrackNeverResurrectsOlderOutput() {
        val state = NativeAudioOutputState()
        state.onAudioTrackInitialized(track(C.ENCODING_PCM_FLOAT))
        state.onAudioTrackInitialized(track(C.ENCODING_PCM_16BIT))
        state.onAudioTrackReleased(track(C.ENCODING_PCM_16BIT))
        assertNull(state.outputEncoding)
        state.onAudioTrackReleased(track(C.ENCODING_PCM_FLOAT))
        assertNull(state.outputEncoding)
    }

    @Test fun decoderReleaseClearsOnlyCurrentMatchingGeneration() {
        val state = NativeAudioOutputState()
        state.onDecoderInitialized("ffmpeg")
        state.onDecoderInitialized("c2.android.aac.decoder")
        state.onDecoderReleased("unknown")
        state.onDecoderReleased("ffmpeg")
        assertEquals("c2.android.aac.decoder", state.decoderName)
        state.onDecoderReleased("c2.android.aac.decoder")
        assertEquals("", state.decoderName)

        state.onDecoderInitialized("ffmpeg")
        state.onDecoderInitialized("ffmpeg")
        state.onDecoderReleased("ffmpeg")
        assertEquals("ffmpeg", state.decoderName)
        state.onDecoderReleased("ffmpeg")
        assertEquals("", state.decoderName)
    }

    @Test fun floatRestorationUsesCurrentSourceMimeAndActiveDecoder() {
        val state = NativeAudioOutputState()
        state.onSinkConfigured(pcm(C.ENCODING_PCM_16BIT))
        state.onDecoderInitialized("ffmpeg")
        assertFalse(state.needsPrecisionChange(false, true))
        state.onSourceInputChanged(source(MimeTypes.AUDIO_AC3))
        assertFalse(state.needsPrecisionChange(false, true))
        state.onSourceInputChanged(source(MimeTypes.AUDIO_AAC))
        assertFalse(state.needsPrecisionChange(false, true))
        state.onSourceInputChanged(source(MimeTypes.AUDIO_DTS))
        assertTrue(state.needsPrecisionChange(false, true))
        assertFalse(state.needsPrecisionChange(true, false))
        state.onSourceInputChanged(source(MimeTypes.VIDEO_H264))
        assertFalse(state.needsPrecisionChange(false, true))
        state.onSourceInputChanged(null)
        assertNull(state.sourceInput)
        assertFalse(state.needsPrecisionChange(false, true))
        state.onSourceInputChanged(source(MimeTypes.AUDIO_DTS))
        assertTrue(state.needsPrecisionChange(false, true))
        state.onDecoderReleased("ffmpeg")
        assertFalse(state.needsPrecisionChange(false, true))
        state.onDecoderInitialized("c2.android.aac.decoder")
        assertFalse(state.needsPrecisionChange(false, true))
    }

    @Test fun sourceAndSinkInputsStayIndependent() {
        val state = NativeAudioOutputState()
        val compressed = source(MimeTypes.AUDIO_AAC)
        val decoded = pcm(C.ENCODING_PCM_16BIT)
        state.onSourceInputChanged(compressed)
        state.onSinkConfigured(decoded)
        val previous = state.snapshot
        val next = source(MimeTypes.AUDIO_AC3)
        state.onSourceInputChanged(next)
        assertSame(next, state.snapshot.sourceInput)
        assertSame(decoded, state.snapshot.sinkInput)
        assertSame(compressed, previous.sourceInput)
    }

    @Test fun outputAndDecoderCompatibilityPropertiesRemainWritable() {
        val state = NativeAudioOutputState()
        state.sourceInput = source(MimeTypes.AUDIO_AAC)
        state.sinkInput = pcm(C.ENCODING_PCM_16BIT)
        state.decoderName = "ffmpeg"
        state.decoderName = "ffmpeg"
        state.onDecoderReleased("ffmpeg")
        assertEquals("", state.decoderName)
        state.onAudioTrackInitialized(track(C.ENCODING_PCM_FLOAT))
        state.outputEncoding = C.ENCODING_PCM_16BIT
        state.onAudioTrackReleased(track(C.ENCODING_PCM_FLOAT))
        assertEquals(C.ENCODING_PCM_16BIT, state.outputEncoding)
        assertNull(state.snapshot.activeOutput)
        state.outputEncoding = null
        state.decoderName = ""
        assertNull(state.outputEncoding)
    }

    @Test fun separatePlayersDoNotShareObservationsOrReleases() {
        val old = NativeAudioOutputState()
        val current = NativeAudioOutputState()
        old.onAudioTrackInitialized(track(C.ENCODING_PCM_FLOAT))
        current.onAudioTrackInitialized(track(C.ENCODING_PCM_16BIT))
        old.onDecoderInitialized("ffmpeg")
        current.onDecoderInitialized("c2.android.aac.decoder")
        old.onAudioTrackReleased(track(C.ENCODING_PCM_FLOAT))
        old.onDecoderReleased("ffmpeg")
        assertEquals(C.ENCODING_PCM_16BIT, current.outputEncoding)
        assertEquals("c2.android.aac.decoder", current.decoderName)
    }

    @Test fun snapshotsNeverExposeMismatchedActiveTrackAndEncoding() {
        val state = NativeAudioOutputState()
        val executor = Executors.newSingleThreadExecutor()
        try {
            val updates = executor.submit {
                repeat(1000) {
                    val config = track(if (it % 2 == 0) C.ENCODING_PCM_FLOAT else C.ENCODING_PCM_16BIT)
                    state.onAudioTrackInitialized(config)
                    state.onAudioTrackReleased(config)
                }
            }
            repeat(2000) {
                val current = state.snapshot
                assertEquals(current.activeOutput?.encoding, current.outputEncoding)
            }
            updates.get(5, TimeUnit.SECONDS)
            assertNull(state.snapshot.activeOutput)
            assertNull(state.snapshot.outputEncoding)
        } finally {
            executor.shutdownNow()
        }
    }

    @Test fun ordinaryPcm16DoesNotNeedPrecisionRebuildInEitherDirection() {
        val state = NativeAudioOutputState().apply {
            sinkInput = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setPcmEncoding(C.ENCODING_PCM_16BIT).build()
        }
        assertFalse(state.needsPrecisionChange(true, false))
        assertFalse(state.needsPrecisionChange(false, true))
        assertFalse(state.isPassthrough())
        state.sinkInput = state.sinkInput!!.buildUpon().setPcmEncoding(C.ENCODING_PCM_24BIT).build()
        assertTrue(state.needsPrecisionChange(true, false))
        assertTrue(state.needsPrecisionChange(false, true))
    }

    @Test fun speedAndPitchDisablePassthroughInEveryModeButDoNotAffectVideo() {
        for (mode in NativeAudioOutputMode.entries) {
            for (parameters in listOf(PlaybackParameters(1.5f), PlaybackParameters(1f, 0.9f))) {
                assertTrue(NativePlaybackAudioPolicy.requiresDecodedOutput(MimeTypes.AUDIO_DTS,
                    false, mode, parameters = parameters))
                assertFalse(NativePlaybackAudioPolicy.requiresDecodedOutput(MimeTypes.VIDEO_H264,
                    false, mode, parameters = parameters))
            }
        }
        assertFalse(NativePlaybackAudioPolicy.requiresDecodedOutput(MimeTypes.AUDIO_DTS,
            false, NativeAudioOutputMode.DEVICE_PASSTHROUGH))
        assertTrue(NativePlaybackAudioPolicy.requiresDecodedOutput(MimeTypes.AUDIO_DTS,
            false, NativeAudioOutputMode.DEVICE_PASSTHROUGH, outputFallback = true))
    }

    @Test fun diagnosticsDoNotCallUnknownEncodingPcm() {
        assertEquals("unknown", NativePlaybackAudioPolicy.encodingLabel(null))
        assertEquals("PCM16", NativePlaybackAudioPolicy.encodingLabel(C.ENCODING_PCM_16BIT))
        assertEquals("PCM24", NativePlaybackAudioPolicy.encodingLabel(C.ENCODING_PCM_24BIT))
        assertEquals("Float32", NativePlaybackAudioPolicy.encodingLabel(C.ENCODING_PCM_FLOAT))
        assertEquals("encoding(9999)", NativePlaybackAudioPolicy.encodingLabel(9999))
    }

    private fun source(mime: String): Format = Format.Builder().setSampleMimeType(mime).build()

    private fun pcm(encoding: Int): Format = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_RAW)
        .setPcmEncoding(encoding).setSampleRate(48_000).setChannelCount(2).build()

    private fun track(encoding: Int): AudioSink.AudioTrackConfig =
        AudioSink.AudioTrackConfig(encoding, 48_000, 12, false, false, 4096)
}
