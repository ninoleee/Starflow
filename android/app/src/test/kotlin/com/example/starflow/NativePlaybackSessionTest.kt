package com.example.starflow

import android.widget.TextView
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackSessionTest {
    @Test
    fun initializationIsIdempotentForExistingPlayer() {
        val host = mock(NativePlaybackSession.Host::class.java)
        val session = NativePlaybackSession(host)
        val player = mock(ExoPlayer::class.java)
        session.player = player
        session.initializePlayer()
        assertSame(player, session.player)
        verifyNoInteractions(host, player)
    }

    @Test
    fun releaseDetachesListenersAndStopsLoopsBeforeReleasingPlayer() {
        val host = mock(NativePlaybackSession.Host::class.java, RETURNS_DEEP_STUBS)
        val session = NativePlaybackSession(host)
        val player = mock(ExoPlayer::class.java)
        val meter = mock(DefaultBandwidthMeter::class.java)
        session.player = player
        session.playbackBandwidthMeter = meter
        val playerListener = host.playerListener
        val analyticsListener = host.diagnostics.playbackPerformanceAnalyticsListener
        val bandwidthListener = host.diagnostics.bandwidthEventListener
        val activity = host.activity
        doReturn(mock(TextView::class.java))
            .`when`(activity)
            .findViewById<TextView>(R.id.native_network_speed)
        session.releasePlayer()
        val order = inOrder(host.remote, host.launch, host.runtime, host.playerView, player, meter)
        order.verify(host.remote).resetInputState()
        order.verify(host.launch).cancelPlaybackLaunchTimeout()
        order.verify(host.runtime).stopPlaybackWatchdog()
        order.verify(host.runtime).stopPlaybackRuntimeLoop()
        order.verify(host.playerView).player = null
        order.verify(player).removeListener(playerListener)
        order.verify(player).removeAnalyticsListener(analyticsListener)
        order.verify(player).release()
        order.verify(meter).removeEventListener(bandwidthListener)
        assertNull(session.player)
        assertNull(session.playbackBandwidthMeter)
        session.releasePlayer()
        verify(player, times(1)).release()
        verify(meter, times(1)).removeEventListener(bandwidthListener)
    }

    @Test
    fun rebuildAlwaysReleasesBeforeInitialization() {
        val session = spy(NativePlaybackSession(mock(NativePlaybackSession.Host::class.java)))
        doNothing().`when`(session).releasePlayer()
        doNothing().`when`(session).initializePlayer()
        session.rebuildPlayer()
        val order = inOrder(session)
        order.verify(session).releasePlayer()
        order.verify(session).initializePlayer()
    }

    @Test
    fun absoluteSeekClampsAndUpdatesRuntimeAndControllerWithoutRebuildingPlayer() {
        val host = mock(NativePlaybackSession.Host::class.java, RETURNS_DEEP_STUBS)
        val session = NativePlaybackSession(host)
        val player = mock(ExoPlayer::class.java)
        session.player = player
        `when`(player.duration).thenReturn(100_000L)
        `when`(player.currentPosition).thenReturn(50_000L)
        assertTrue(session.seekTo(120_000L))
        verify(player).seekTo(100_000L)
        verify(host.runtime).resetPlaybackWatchdogProgress(100_000L)
        verify(host.runtime).syncSkipFlagsWithCurrentPosition()
        verify(host.controllerView).showControllerForRemoteFocus(ControllerFocusTarget.PLAYER)
        assertTrue(session.seekTo(-10_000L))
        verify(player).seekTo(0L)
        assertFalse(session.seekTo(50_000L))
        verify(player, times(2)).seekTo(anyLong())
        verify(player, never()).release()
        verify(player, never()).prepare()
    }

    @Test
    fun relativeSeekKeepsExistingStepAndUnknownDurationSupport() {
        val host = mock(NativePlaybackSession.Host::class.java, RETURNS_DEEP_STUBS)
        val session = NativePlaybackSession(host)
        val player = mock(ExoPlayer::class.java)
        session.player = player
        `when`(player.duration).thenReturn(-1L)
        `when`(player.currentPosition).thenReturn(50_000L)
        assertTrue(session.seekBy(10_000L))
        verify(player).seekTo(60_000L)
        session.player = null
        assertFalse(session.seekTo(60_000L))
        assertFalse(session.seekBy(10_000L))
    }
}
