package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.PlaybackParameters
import androidx.media3.exoplayer.ExoPlayer
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackHealthIntegrationTest {
    @Test fun displayActivityControlsRequestsWithoutRestartingPlayback() {
        val host = mock(NativePlaybackSession.Host::class.java, RETURNS_DEEP_STUBS)
        `when`(host.isTelevisionDevice).thenReturn(true)
        val session = spy(NativePlaybackSession(host))
        doReturn(true).`when`(session).supportsFrameRateMatching
        val frameRate = mock(NativePlaybackFrameRateController::class.java)
        doReturn(frameRate).`when`(session).frameRate
        val player = mock(ExoPlayer::class.java)
        session.player = player
        `when`(player.isPlaying).thenReturn(true)
        `when`(player.playbackParameters).thenReturn(PlaybackParameters.DEFAULT)

        assertFalse(session.frameRateMatchingEnabled)
        session.setFrameRateMatching(true)
        assertTrue(session.frameRateMatchingEnabled)
        verify(player).setVideoChangeFrameRateStrategy(C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_OFF)
        verify(frameRate).setEnabled(true)
        verify(frameRate, never()).update(player)
        session.setDisplayActive(true)
        verify(frameRate).update(player)

        clearInvocations(frameRate)
        `when`(player.playbackParameters).thenReturn(PlaybackParameters(1.5f))
        session.updatePlaybackHealth()
        verify(frameRate).restore()
        verify(frameRate, never()).update(player)
        `when`(player.playbackParameters).thenReturn(PlaybackParameters.DEFAULT)

        clearInvocations(frameRate)
        `when`(player.isPlaying).thenReturn(false)
        session.updatePlaybackHealth()
        verify(frameRate).restore()
        verify(frameRate, never()).update(player)
        session.setDisplayActive(false)
        session.setFrameRateMatching(false)
        verify(frameRate).setEnabled(false)
        verify(player).setVideoChangeFrameRateStrategy(C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_ONLY_IF_SEAMLESS)
        verify(session, never()).rebuildPlayer()
    }

    @Test fun unsupportedDevicesCannotEnableDisplayMatching() {
        val host = mock(NativePlaybackSession.Host::class.java, RETURNS_DEEP_STUBS)
        val session = spy(NativePlaybackSession(host))
        doReturn(false).`when`(session).supportsFrameRateMatching
        val frameRate = mock(NativePlaybackFrameRateController::class.java)
        doReturn(frameRate).`when`(session).frameRate
        session.setFrameRateMatching(true)
        assertFalse(session.frameRateMatchingEnabled)
        verify(frameRate).setEnabled(false)
    }
}
