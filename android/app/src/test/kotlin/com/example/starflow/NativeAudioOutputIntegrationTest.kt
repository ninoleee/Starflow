package com.example.starflow

import android.media.AudioTrack
import android.util.SparseArray
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.AudioTrackAudioOutputProvider
import androidx.media3.exoplayer.audio.DefaultAudioSink
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class NativeAudioOutputIntegrationTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()

    @Test fun actualMedia3SinkTurnsRejectedFloatConfigurationIntoOnePcmRecovery() {
        mockConstruction(SparseArray::class.java).use {
            val provider = NativePlaybackAudioOutputProvider(
                AudioTrackAudioOutputProvider.Builder(null).build(),
            ) { _, _, _ -> AudioTrack.ERROR_BAD_VALUE }
            val delegate = DefaultAudioSink.Builder().setEnableFloatOutput(true).build()
            delegate.setAudioOutputProvider(provider)
            val state = NativeAudioOutputState()
            val sink = NativePlaybackAudioSink(delegate, { false }, state::onSinkConfigured)
            val pcm = Format.Builder().setId("pcm").setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setSampleRate(96_000).setChannelCount(2).setPcmEncoding(C.ENCODING_PCM_24BIT).build()
            val failure = assertThrows(AudioSink.ConfigurationException::class.java) {
                sink.configure(pcm, 0, null)
            }
            assertSame(pcm, failure.format)
            assertSame(pcm, state.sinkInput)
            assertNotNull(failure.cause)
            val host = mock(NativePlaybackRecoveryController.Host::class.java, RETURNS_DEEP_STUBS)
            val current = mock(ExoPlayer::class.java)
            `when`(current.audioFormat).thenReturn(pcm)
            `when`(current.currentTracks).thenReturn(Tracks.EMPTY)
            `when`(host.session.player).thenReturn(current)
            `when`(host.session.audioOutputState).thenReturn(state)
            `when`(host.session.highPrecisionPcmEnabled).thenReturn(true)
            val error = ExoPlaybackException.createForRenderer(failure, "MediaCodecAudioRenderer", 1,
                failure.format, C.FORMAT_HANDLED, false, PlaybackException.ERROR_CODE_AUDIO_TRACK_INIT_FAILED)
            val recovery = NativePlaybackRecoveryController(host) { false }
            assertTrue(recovery.retryAudioWithSoftwareDecoder(error))
            assertFalse(recovery.retryAudioWithSoftwareDecoder(error))
            verify(host.session).pcm16Fallback = true
            verify(host.session, times(1)).rebuildPlayer()
            verify(host.session, never()).audioFallbackMime = anyString()
        }
    }
}
