package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.DrmInitData
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.TrackGroup
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.audio.AudioSink
import java.io.IOException
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackAudioRecoveryTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()
    private fun error(
        mime: String = MimeTypes.AUDIO_AC3,
        renderer: String = "MediaCodecAudioRenderer",
        code: Int = PlaybackException.ERROR_CODE_DECODING_FAILED,
        encrypted: Boolean = false,
        pcmEncoding: Int = C.ENCODING_PCM_16BIT,
        cause: Throwable = IllegalStateException("decoder"),
    ) = ExoPlaybackException.createForRenderer(
        cause, renderer, 1,
        Format.Builder().setSampleMimeType(mime)
            .setPcmEncoding(pcmEncoding)
            .setCryptoType(if (encrypted) C.CRYPTO_TYPE_FRAMEWORK else C.CRYPTO_TYPE_NONE).build(),
        C.FORMAT_HANDLED, false, code,
    )

    private fun pcmFormat(encoding: Int = C.ENCODING_PCM_FLOAT): Format =
        Format.Builder().setSampleMimeType(MimeTypes.AUDIO_RAW).setPcmEncoding(encoding).build()

    private fun sinkExceptions(format: Format): List<Exception> = listOf(
        AudioSink.WriteException(-1, format, false),
        AudioSink.InitializationException("test", 0, format, false, null),
        AudioSink.ConfigurationException("test", format),
    )

    private fun sinkError(
        cause: Exception,
        renderer: String = "FfmpegAudioRenderer",
        rendererFormat: Format? = null,
    ): ExoPlaybackException = ExoPlaybackException.createForRenderer(
        cause, renderer, 1, rendererFormat, C.FORMAT_HANDLED, false,
        if (cause is AudioSink.WriteException) PlaybackException.ERROR_CODE_AUDIO_TRACK_WRITE_FAILED
        else PlaybackException.ERROR_CODE_AUDIO_TRACK_INIT_FAILED,
    )

    private fun outputHost(
        source: Format? = null,
        tracks: Tracks = Tracks.EMPTY,
    ): NativePlaybackRecoveryController.Host {
        val host = mock(NativePlaybackRecoveryController.Host::class.java, RETURNS_DEEP_STUBS)
        val player = mock(ExoPlayer::class.java)
        `when`(host.session.player).thenReturn(player)
        `when`(player.audioFormat).thenReturn(source)
        `when`(player.currentTracks).thenReturn(tracks)
        `when`(host.session.audioOutputState).thenReturn(NativeAudioOutputState())
        `when`(host.session.highPrecisionPcmEnabled).thenReturn(true)
        `when`(host.session.audioFallbackMime).thenReturn(null)
        return host
    }

    private fun selectedAudioTracks(format: Format): Tracks = Tracks(listOf(
        Tracks.Group(TrackGroup(format), false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(true)),
    ))

    @Test fun highPrecisionOutputFailureFallsBackOnceWithoutFfmpeg() {
        val host = mock(NativePlaybackRecoveryController.Host::class.java, RETURNS_DEEP_STUBS)
        val session = host.session
        `when`(session.audioOutputState).thenReturn(NativeAudioOutputState())
        `when`(session.highPrecisionPcmEnabled).thenReturn(true)
        val recovery = NativePlaybackRecoveryController(host) { false }
        val failure = error(mime = MimeTypes.AUDIO_RAW, pcmEncoding = C.ENCODING_PCM_24BIT,
            code = PlaybackException.ERROR_CODE_AUDIO_TRACK_INIT_FAILED)
        assertTrue(recovery.retryAudioWithSoftwareDecoder(failure))
        verify(session).preserveAudioSession()
        verify(session).pcm16Fallback = true
        assertFalse(recovery.retryAudioWithSoftwareDecoder(failure))
        verify(session, times(1)).rebuildPlayer()
        recovery.resetForNewMedia()
        assertTrue(recovery.retryAudioWithSoftwareDecoder(failure))
    }

    @Test fun pcmCompatibilityAndNetworkFailuresDoNotRetryPrecision() {
        val host = mock(NativePlaybackRecoveryController.Host::class.java, RETURNS_DEEP_STUBS)
        `when`(host.session.audioOutputState).thenReturn(NativeAudioOutputState())
        val recovery = NativePlaybackRecoveryController(host) { false }
        assertFalse(recovery.retryAudioWithSoftwareDecoder(error(mime = MimeTypes.AUDIO_RAW,
            pcmEncoding = C.ENCODING_PCM_24BIT, code = PlaybackException.ERROR_CODE_AUDIO_TRACK_INIT_FAILED)))
        `when`(host.session.highPrecisionPcmEnabled).thenReturn(true)
        assertFalse(recovery.retryAudioWithSoftwareDecoder(error(mime = MimeTypes.AUDIO_RAW,
            pcmEncoding = C.ENCODING_PCM_24BIT, code = PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED)))
        verify(host.session, never()).rebuildPlayer()
    }

    @Test fun audioRetryPreservesStateAndIsBounded() {
        val host = mock(NativePlaybackRecoveryController.Host::class.java, RETURNS_DEEP_STUBS)
        val session = host.session
        `when`(session.audioFallbackMime).thenReturn(null)
        val recovery = NativePlaybackRecoveryController(host) { true }
        assertTrue(recovery.retryAudioWithSoftwareDecoder(error()))
        val order = inOrder(session)
        order.verify(session).preserveAudioSession()
        order.verify(session).audioFallbackMime = MimeTypes.AUDIO_AC3
        order.verify(session).rebuildPlayer()
        // A manual output change may clear the MIME override, but not the budget.
        `when`(session.audioFallbackMime).thenReturn(null)
        assertFalse(recovery.retryAudioWithSoftwareDecoder(error()))
        verify(session, times(1)).rebuildPlayer()
    }

    @Test fun excludesNetworkVideoDrmAndExistingSoftwareDecoderFailures() {
        val host = mock(NativePlaybackRecoveryController.Host::class.java, RETURNS_DEEP_STUBS)
        `when`(host.session.audioFallbackMime).thenReturn(null)
        val recovery = NativePlaybackRecoveryController(host) { true }
        assertFalse(recovery.retryAudioWithSoftwareDecoder(error(mime = MimeTypes.VIDEO_H264)))
        assertFalse(recovery.retryAudioWithSoftwareDecoder(error(renderer = "FfmpegAudioRenderer")))
        assertFalse(recovery.retryAudioWithSoftwareDecoder(error(encrypted = true)))
        assertFalse(recovery.retryAudioWithSoftwareDecoder(error(code = PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED)))
        assertFalse(recovery.retryAudioWithSoftwareDecoder(PlaybackException("network", null, PlaybackException.ERROR_CODE_IO_UNSPECIFIED)))
        verify(host.session, never()).rebuildPlayer()
    }

    @Test fun unavailableNativeDecoderDoesNotRetry() {
        val host = mock(NativePlaybackRecoveryController.Host::class.java, RETURNS_DEEP_STUBS)
        `when`(host.session.audioFallbackMime).thenReturn(null)
        assertFalse(NativePlaybackRecoveryController(host) { false }.retryAudioWithSoftwareDecoder(error()))
        verify(host.session, never()).rebuildPlayer()
    }

    @Test fun compressedInputFloatOutputFailureKeepsDecoderAndDoesNotSpendDecodeBudget() {
        for (renderer in listOf("MediaCodecAudioRenderer", "FfmpegAudioRenderer")) {
            val host = mock(NativePlaybackRecoveryController.Host::class.java, RETURNS_DEEP_STUBS)
            val session = host.session
            val state = NativeAudioOutputState().apply {
                sinkInput = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_RAW)
                    .setPcmEncoding(C.ENCODING_PCM_FLOAT).build()
            }
            `when`(session.audioOutputState).thenReturn(state)
            `when`(session.highPrecisionPcmEnabled).thenReturn(true)
            `when`(session.audioFallbackMime).thenReturn(null)
            val recovery = NativePlaybackRecoveryController(host) { true }
            val failure = error(mime = MimeTypes.AUDIO_AAC, renderer = renderer,
                code = PlaybackException.ERROR_CODE_AUDIO_TRACK_INIT_FAILED)
            assertTrue(recovery.retryAudioWithSoftwareDecoder(failure))
            verify(session).pcm16Fallback = true
            verify(session, never()).audioFallbackMime = anyString()
            assertFalse(recovery.retryAudioWithSoftwareDecoder(failure))
            if (renderer == "MediaCodecAudioRenderer") {
                assertTrue(recovery.retryAudioWithSoftwareDecoder(error()))
                verify(session).audioFallbackMime = MimeTypes.AUDIO_AC3
            }
        }
    }

    @Test fun pcm16SinkFailureIsNotMisclassifiedAsCompressedPassthroughOrDecoderFailure() {
        val host = mock(NativePlaybackRecoveryController.Host::class.java, RETURNS_DEEP_STUBS)
        val state = NativeAudioOutputState().apply {
            sinkInput = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setPcmEncoding(C.ENCODING_PCM_16BIT).build()
            outputEncoding = C.ENCODING_PCM_16BIT
        }
        `when`(host.session.audioOutputState).thenReturn(state)
        `when`(host.session.highPrecisionPcmEnabled).thenReturn(true)
        val recovery = NativePlaybackRecoveryController(host) { true }
        assertFalse(recovery.retryAudioWithSoftwareDecoder(error(code = PlaybackException.ERROR_CODE_AUDIO_TRACK_WRITE_FAILED)))
        state.sinkInput = null
        assertFalse(recovery.retryAudioWithSoftwareDecoder(error(code = PlaybackException.ERROR_CODE_AUDIO_TRACK_WRITE_FAILED)))
        verify(host.session, never()).rebuildPlayer()
    }

    @Test fun passthroughOutputFailureDecodesWithoutForcingSoftwareDecoder() {
        val host = mock(NativePlaybackRecoveryController.Host::class.java, RETURNS_DEEP_STUBS)
        val state = NativeAudioOutputState().apply {
            sinkInput = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_DTS).build()
        }
        `when`(host.session.audioOutputState).thenReturn(state)
        val recovery = NativePlaybackRecoveryController(host) { false }
        assertTrue(recovery.retryAudioWithSoftwareDecoder(error(mime = MimeTypes.AUDIO_DTS,
            code = PlaybackException.ERROR_CODE_AUDIO_TRACK_WRITE_FAILED)))
        verify(host.session).pcm16Fallback = true
        verify(host.session, never()).audioFallbackMime = anyString()
    }

    @Test fun sinkExceptionFormatOverridesCachedFormatAndEncoding() {
        val host = mock(NativePlaybackRecoveryController.Host::class.java, RETURNS_DEEP_STUBS)
        val pcm16 = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_RAW)
            .setPcmEncoding(C.ENCODING_PCM_16BIT).build()
        val pcm24 = pcm16.buildUpon().setPcmEncoding(C.ENCODING_PCM_24BIT).build()
        val state = NativeAudioOutputState().apply {
            sinkInput = pcm24
            outputEncoding = C.ENCODING_PCM_FLOAT
        }
        `when`(host.session.audioOutputState).thenReturn(state)
        `when`(host.session.highPrecisionPcmEnabled).thenReturn(true)
        val recovery = NativePlaybackRecoveryController(host) { true }
        assertFalse(recovery.retryAudioWithSoftwareDecoder(error(
            code = PlaybackException.ERROR_CODE_AUDIO_TRACK_WRITE_FAILED,
            cause = AudioSink.WriteException(-1, pcm16, false))))
        verify(host.session, never()).rebuildPlayer()
        state.sinkInput = pcm16
        state.outputEncoding = C.ENCODING_PCM_16BIT
        assertTrue(recovery.retryAudioWithSoftwareDecoder(error(
            code = PlaybackException.ERROR_CODE_AUDIO_TRACK_WRITE_FAILED,
            cause = AudioSink.WriteException(-1, pcm24, false))))
        verify(host.session).pcm16Fallback = true
    }

    @Test fun outputRecoveryRejectsDrmAndVideoEvenWithFloatSinkEvidence() {
        val host = mock(NativePlaybackRecoveryController.Host::class.java, RETURNS_DEEP_STUBS)
        `when`(host.session.audioOutputState).thenReturn(NativeAudioOutputState().apply {
            sinkInput = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setPcmEncoding(C.ENCODING_PCM_FLOAT).build()
        })
        `when`(host.session.highPrecisionPcmEnabled).thenReturn(true)
        val recovery = NativePlaybackRecoveryController(host) { true }
        assertFalse(recovery.retryAudioWithSoftwareDecoder(error(encrypted = true,
            code = PlaybackException.ERROR_CODE_AUDIO_TRACK_INIT_FAILED)))
        assertFalse(recovery.retryAudioWithSoftwareDecoder(error(mime = MimeTypes.VIDEO_H264,
            code = PlaybackException.ERROR_CODE_AUDIO_TRACK_WRITE_FAILED)))
        verify(host.session, never()).rebuildPlayer()
    }

    @Test fun realSinkExceptionsWithMissingRendererFormatRecoverOnceForKnownAudioRenderers() {
        val source = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_AAC).build()
        for (renderer in listOf("FfmpegAudioRenderer", "MediaCodecAudioRenderer")) {
            for (cause in sinkExceptions(pcmFormat())) {
                val host = outputHost(if (renderer == "MediaCodecAudioRenderer") source else null)
                val recovery = NativePlaybackRecoveryController(host) { false }
                val failure = sinkError(cause, renderer)
                assertNull(failure.rendererFormat)
                assertTrue("$renderer ${cause.javaClass.simpleName}", recovery.retryAudioWithSoftwareDecoder(failure))
                assertFalse(recovery.retryAudioWithSoftwareDecoder(failure))
                verify(host.session).preserveAudioSession()
                verify(host.session).pcm16Fallback = true
                verify(host.session, never()).audioFallbackMime = anyString()
                verify(host.session, times(1)).rebuildPlayer()
            }
        }
    }

    @Test fun missingSourceIsConservativeExceptForExplicitFfmpegRenderer() {
        for (cause in sinkExceptions(pcmFormat())) {
            for (renderer in listOf("MediaCodecAudioRenderer", "UnknownRenderer", "OtherFfmpegAudioRenderer")) {
                val host = outputHost()
                host.session.audioOutputState.sinkInput = pcmFormat()
                host.session.audioOutputState.outputEncoding = C.ENCODING_PCM_FLOAT
                val recovery = NativePlaybackRecoveryController(host) { true }
                assertFalse(recovery.retryAudioWithSoftwareDecoder(sinkError(cause, renderer)))
                // A raw rendererFormat substituted by a sink exception is not source DRM evidence either.
                assertFalse(recovery.retryAudioWithSoftwareDecoder(sinkError(cause, renderer, pcmFormat())))
                verify(host.session, never()).rebuildPlayer()
            }
        }
        val host = outputHost()
        `when`(host.session.player).thenReturn(null)
        assertTrue(NativePlaybackRecoveryController(host) { false }.retryAudioWithSoftwareDecoder(
            sinkError(AudioSink.WriteException(-1, pcmFormat(), false)),
        ))
    }

    @Test fun missingRendererFormatStillRejectsVideoUnknownAndSourceFailures() {
        val source = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_AAC).build()
        val host = outputHost(source)
        val recovery = NativePlaybackRecoveryController(host) { true }
        for (cause in sinkExceptions(pcmFormat())) {
            assertFalse(recovery.retryAudioWithSoftwareDecoder(sinkError(cause, "MediaCodecVideoRenderer")))
            assertFalse(recovery.retryAudioWithSoftwareDecoder(sinkError(cause, "UnknownRenderer")))
            assertFalse(recovery.retryAudioWithSoftwareDecoder(sinkError(cause,
                rendererFormat = Format.Builder().setSampleMimeType(MimeTypes.VIDEO_H264).build())))
            // TYPE_SOURCE must never call getRendererException, even with a sink-looking cause/code.
            assertFalse(recovery.retryAudioWithSoftwareDecoder(ExoPlaybackException.createForSource(
                IOException(cause), PlaybackException.ERROR_CODE_AUDIO_TRACK_INIT_FAILED,
            )))
        }
        verify(host.session, never()).rebuildPlayer()
    }

    @Test fun sourceDrmSurvivesMissingOrRawRendererFormatForEverySinkException() {
        val clear = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_AAC).build()
        val encryptedFormats = listOf(
            clear.buildUpon().setCryptoType(C.CRYPTO_TYPE_FRAMEWORK).build(),
            clear.buildUpon().setDrmInitData(DrmInitData(
                DrmInitData.SchemeData(C.WIDEVINE_UUID, MimeTypes.AUDIO_AAC, byteArrayOf(1)),
            )).build(),
        )
        for (encrypted in encryptedFormats) {
            for (fromTracks in listOf(false, true)) {
                val host = if (fromTracks) outputHost(clear, selectedAudioTracks(encrypted)) else outputHost(encrypted)
                val recovery = NativePlaybackRecoveryController(host) { true }
                for (renderer in listOf("MediaCodecAudioRenderer", "FfmpegAudioRenderer")) {
                    for (cause in sinkExceptions(pcmFormat())) {
                        for (format in listOf(null, pcmFormat(), clear)) {
                            assertFalse(recovery.retryAudioWithSoftwareDecoder(sinkError(cause, renderer, format)))
                        }
                    }
                }
                verify(host.session, never()).rebuildPlayer()
            }
        }
    }

    @Test fun selectedClearSourceCanSupplyDrmEvidenceWithoutAudioFormat() {
        val clear = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_AAC).build()
        val encrypted = clear.buildUpon().setCryptoType(C.CRYPTO_TYPE_FRAMEWORK).build()
        val host = outputHost(tracks = Tracks(listOf(
            Tracks.Group(TrackGroup(clear, encrypted), false,
                intArrayOf(C.FORMAT_HANDLED, C.FORMAT_HANDLED), booleanArrayOf(true, false)),
        )))
        assertTrue(NativePlaybackRecoveryController(host) { false }.retryAudioWithSoftwareDecoder(
            sinkError(AudioSink.ConfigurationException("test", pcmFormat()), "MediaCodecAudioRenderer", pcmFormat()),
        ))
    }

    @Test fun missingRendererFormatDoesNotRetryPcm16OrExistingCompatibilityFallback() {
        for (encoding in listOf(C.ENCODING_PCM_16BIT, C.ENCODING_PCM_FLOAT)) {
            for (cause in sinkExceptions(pcmFormat(encoding))) {
                val host = outputHost()
                host.session.audioOutputState.sinkInput = pcmFormat()
                host.session.audioOutputState.outputEncoding = C.ENCODING_PCM_FLOAT
                `when`(host.session.pcm16Fallback).thenReturn(encoding == C.ENCODING_PCM_FLOAT)
                assertFalse(NativePlaybackRecoveryController(host) { true }.retryAudioWithSoftwareDecoder(sinkError(cause)))
                verify(host.session, never()).rebuildPlayer()
            }
        }
    }

    @Test fun missingRendererFormatRequiresRealAudioSinkEvidenceAndRejectsItsDrmMarkers() {
        val host = outputHost()
        host.session.audioOutputState.sinkInput = pcmFormat()
        host.session.audioOutputState.outputEncoding = C.ENCODING_PCM_FLOAT
        val recovery = NativePlaybackRecoveryController(host) { true }
        assertFalse(recovery.retryAudioWithSoftwareDecoder(sinkError(IllegalStateException("output"))))
        val encrypted = pcmFormat().buildUpon().setCryptoType(C.CRYPTO_TYPE_FRAMEWORK).build()
        for (cause in sinkExceptions(encrypted)) {
            assertFalse(recovery.retryAudioWithSoftwareDecoder(sinkError(cause)))
        }
        for (cause in sinkExceptions(Format.Builder().setSampleMimeType(MimeTypes.VIDEO_H264).build())) {
            assertFalse(recovery.retryAudioWithSoftwareDecoder(sinkError(cause)))
        }
        verify(host.session, never()).rebuildPlayer()
    }

    @Test fun missingRendererFormatPassthroughFailureUsesOutputBudgetWithoutHighPrecisionOrFfmpeg() {
        val source = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_DTS).build()
        for (cause in sinkExceptions(source)) {
            val host = outputHost(source)
            `when`(host.session.highPrecisionPcmEnabled).thenReturn(false)
            val recovery = NativePlaybackRecoveryController(host) { false }
            val failure = sinkError(cause, "MediaCodecAudioRenderer")
            assertTrue(recovery.retryAudioWithSoftwareDecoder(failure))
            assertFalse(recovery.retryAudioWithSoftwareDecoder(failure))
            verify(host.session).pcm16Fallback = true
            verify(host.session, never()).audioFallbackMime = anyString()
            verify(host.session, times(1)).rebuildPlayer()
        }
    }

    @Test fun missingRendererFormatOutputBudgetRemainsIndependentOfDecoderBudgetInBothOrders() {
        val source = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_AC3).build()
        for (outputFirst in listOf(false, true)) {
            val host = outputHost(source)
            val recovery = NativePlaybackRecoveryController(host) { true }
            val output = sinkError(AudioSink.WriteException(-1, pcmFormat(), false))
            val decoder = error()
            val failures = if (outputFirst) listOf(output, decoder) else listOf(decoder, output)
            failures.forEach { assertTrue(recovery.retryAudioWithSoftwareDecoder(it)) }
            failures.forEach { assertFalse(recovery.retryAudioWithSoftwareDecoder(it)) }
            verify(host.session, times(2)).preserveAudioSession()
            verify(host.session, times(2)).rebuildPlayer()
            verify(host.session).pcm16Fallback = true
            verify(host.session).audioFallbackMime = MimeTypes.AUDIO_AC3
            recovery.resetForNewMedia()
            assertTrue(recovery.retryAudioWithSoftwareDecoder(output))
            assertTrue(recovery.retryAudioWithSoftwareDecoder(decoder))
        }
    }
}
