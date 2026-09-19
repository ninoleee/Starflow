package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.exoplayer.ExoPlaybackException
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
    ) = ExoPlaybackException.createForRenderer(
        IllegalStateException("decoder"), renderer, 1,
        Format.Builder().setSampleMimeType(mime)
            .setCryptoType(if (encrypted) C.CRYPTO_TYPE_FRAMEWORK else C.CRYPTO_TYPE_NONE).build(),
        C.FORMAT_HANDLED, false, code,
    )

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
}
