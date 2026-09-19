package com.example.starflow

import android.widget.TextView
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.TrackGroup
import androidx.media3.common.Tracks
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackSessionTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()
    @Test
    fun audioOutputRestartRestoresTrackSpeedVolumePositionAndPause() {
        val host = mock(NativePlaybackSession.Host::class.java, RETURNS_DEEP_STUBS)
        `when`(host.target.playbackItemKey).thenReturn("episode")
        val session = spy(NativePlaybackSession(host))
        doNothing().`when`(session).rebuildPlayer()
        val old = mock(ExoPlayer::class.java)
        val format = Format.Builder().setId("jpn").setLanguage("jpn")
            .setSampleMimeType(MimeTypes.AUDIO_AC3).setChannelCount(6).build()
        val oldGroup = TrackGroup(format)
        `when`(old.currentTracks).thenReturn(Tracks(listOf(Tracks.Group(oldGroup, false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(true)))))
        `when`(old.playbackParameters).thenReturn(PlaybackParameters(1.5f))
        `when`(old.volume).thenReturn(0.6f)
        `when`(old.currentPosition).thenReturn(42_000L)
        `when`(old.playWhenReady).thenReturn(false)
        session.player = old
        session.audioFallbackMime = MimeTypes.AUDIO_AC3
        session.restartPlayerWithAudioOutputMode(NativeAudioOutputMode.PCM_COMPATIBILITY)
        assertNull(session.audioFallbackMime)
        org.junit.Assert.assertEquals(42_000L, session.pendingResumePositionOverrideMs)
        org.junit.Assert.assertEquals(false, session.nextInitializePlayWhenReady)
        verify(session).rebuildPlayer()
        val fresh = mock(ExoPlayer::class.java)
        `when`(fresh.trackSelectionParameters).thenReturn(TrackSelectionParameters.Builder().build())
        session.player = fresh
        session.restoreAudioPlaybackParameters(fresh)
        verify(fresh).playbackParameters = PlaybackParameters(1.5f)
        verify(fresh).volume = 0.6f
        assertTrue(session.restoreAudioTrack(Tracks.EMPTY))
        val newGroup = TrackGroup("new", format)
        val tracks = Tracks(listOf(Tracks.Group(newGroup, false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(false))))
        assertTrue(session.restoreAudioTrack(tracks))
        val captor = org.mockito.ArgumentCaptor.forClass(TrackSelectionParameters::class.java)
        verify(fresh).trackSelectionParameters = captor.capture()
        assertSame(newGroup, captor.value.overrides.values.single().mediaTrackGroup)
        assertFalse(session.restoreAudioTrack(tracks))
    }

    @Test
    fun usesCompatibleTsExtractorFactory() {
        val session = NativePlaybackSession(mock(NativePlaybackSession.Host::class.java))
        assertTrue(session.buildExtractorsFactory() is NativePlaybackExtractorsFactory)
    }

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
