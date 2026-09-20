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
    fun systemDecoderSpeedRoundTripRestoresTemporaryPrecisionLoss() {
        val host = mock(NativePlaybackSession.Host::class.java, RETURNS_DEEP_STUBS)
        val session = spy(NativePlaybackSession(host))
        doNothing().`when`(session).rebuildPlayer()
        val current = mock(ExoPlayer::class.java)
        val source = Format.Builder().setId("flac-1").setSampleMimeType(MimeTypes.AUDIO_FLAC)
            .setSampleRate(96_000).setChannelCount(2).build()
        `when`(current.audioFormat).thenReturn(source)
        `when`(current.currentTracks).thenReturn(Tracks.EMPTY)
        `when`(current.playbackParameters).thenReturn(PlaybackParameters.DEFAULT)
        session.player = current
        val precisionFlag = NativePlaybackSession::class.java.getDeclaredField("highPrecisionPcmEnabled")
        precisionFlag.isAccessible = true
        precisionFlag.setBoolean(session, true)
        session.audioOutputState.sourceInput = source
        session.audioOutputState.sinkInput = source.buildUpon().setSampleMimeType(MimeTypes.AUDIO_RAW)
            .setPcmEncoding(C.ENCODING_PCM_FLOAT).build()
        session.audioOutputState.decoderName = "c2.android.flac.decoder"
        session.setPlaybackParameters(PlaybackParameters(1.5f))
        verify(session).rebuildPlayer()
        precisionFlag.setBoolean(session, false)
        session.audioOutputState.sinkInput = session.audioOutputState.sinkInput!!.buildUpon()
            .setPcmEncoding(C.ENCODING_PCM_16BIT).build()
        session.audioOutputState.outputEncoding = C.ENCODING_PCM_16BIT
        `when`(current.playbackParameters).thenReturn(PlaybackParameters(1.5f))
        session.setPlaybackParameters(PlaybackParameters.DEFAULT)
        verify(session, times(2)).rebuildPlayer()
        session.setPlaybackParameters(PlaybackParameters.DEFAULT)
        verify(session, times(2)).rebuildPlayer()
    }

    @Test
    fun temporaryPrecisionHistoryDoesNotForceDifferentTrackOrDeviceFallback() {
        for (fallback in listOf(false, true)) {
            val host = mock(NativePlaybackSession.Host::class.java, RETURNS_DEEP_STUBS)
            val session = spy(NativePlaybackSession(host))
            doNothing().`when`(session).rebuildPlayer()
            val current = mock(ExoPlayer::class.java)
            val source = Format.Builder().setId("first").setSampleMimeType(MimeTypes.AUDIO_FLAC).build()
            `when`(current.audioFormat).thenReturn(source)
            `when`(current.currentTracks).thenReturn(Tracks.EMPTY)
            `when`(current.playbackParameters).thenReturn(PlaybackParameters.DEFAULT)
            session.player = current
            val flag = NativePlaybackSession::class.java.getDeclaredField("highPrecisionPcmEnabled")
            flag.isAccessible = true
            flag.setBoolean(session, true)
            session.audioOutputState.sinkInput = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setPcmEncoding(C.ENCODING_PCM_FLOAT).build()
            session.setPlaybackParameters(PlaybackParameters(1.5f))
            flag.setBoolean(session, false)
            session.audioOutputState.sinkInput = session.audioOutputState.sinkInput!!.buildUpon()
                .setPcmEncoding(C.ENCODING_PCM_16BIT).build()
            if (fallback) session.pcm16Fallback = true else {
                `when`(current.audioFormat).thenReturn(source.buildUpon().setId("second").build())
            }
            session.setPlaybackParameters(PlaybackParameters.DEFAULT)
            verify(session, times(1)).rebuildPlayer()
            verify(current).playbackParameters = PlaybackParameters.DEFAULT
        }
    }
    @Test
    fun ordinaryAudioChangesSpeedWithoutReopeningAndSwitchingToHighResolutionReconciles() {
        val host = mock(NativePlaybackSession.Host::class.java, RETURNS_DEEP_STUBS)
        val session = spy(NativePlaybackSession(host))
        doNothing().`when`(session).rebuildPlayer()
        val current = mock(ExoPlayer::class.java)
        session.player = current
        session.audioOutputState.sinkInput = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_RAW)
            .setPcmEncoding(C.ENCODING_PCM_16BIT).build()
        session.setPlaybackParameters(PlaybackParameters.DEFAULT)
        session.setPlaybackParameters(PlaybackParameters(1.5f))
        verify(current).playbackParameters = PlaybackParameters.DEFAULT
        verify(current).playbackParameters = PlaybackParameters(1.5f)
        verify(session, never()).rebuildPlayer()
        session.audioOutputState.sinkInput = session.audioOutputState.sinkInput!!.buildUpon()
            .setPcmEncoding(C.ENCODING_PCM_24BIT).build()
        `when`(current.playbackParameters).thenReturn(PlaybackParameters.DEFAULT)
        `when`(current.currentTracks).thenReturn(Tracks.EMPTY)
        session.reconcileAudioPrecision(current, PlaybackParameters.DEFAULT)
        verify(session).rebuildPlayer()
    }

    @Test
    fun passthroughSpeedChangeAndReturnToNormalRestoreOutputPolicy() {
        val host = mock(NativePlaybackSession.Host::class.java, RETURNS_DEEP_STUBS)
        val session = spy(NativePlaybackSession(host))
        doNothing().`when`(session).rebuildPlayer()
        val current = mock(ExoPlayer::class.java)
        session.player = current
        `when`(current.currentTracks).thenReturn(Tracks.EMPTY)
        `when`(current.playbackParameters).thenReturn(PlaybackParameters.DEFAULT)
        session.audioOutputState.sinkInput = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_DTS).build()
        session.setPlaybackParameters(PlaybackParameters(1.5f))
        verify(session).rebuildPlayer()
        session.audioOutputState.sinkInput = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_RAW)
            .setPcmEncoding(C.ENCODING_PCM_16BIT).build()
        `when`(current.playbackParameters).thenReturn(PlaybackParameters(1.5f))
        session.setPlaybackParameters(PlaybackParameters.DEFAULT)
        verify(session, times(2)).rebuildPlayer()
    }

    @Test
    fun speedPrecisionTransitionStagesParametersAndKeepsPauseAndVolume() {
        val host = mock(NativePlaybackSession.Host::class.java, RETURNS_DEEP_STUBS)
        `when`(host.target.playbackItemKey).thenReturn("episode")
        val session = spy(NativePlaybackSession(host))
        doNothing().`when`(session).rebuildPlayer()
        val current = mock(ExoPlayer::class.java)
        `when`(current.currentTracks).thenReturn(Tracks.EMPTY)
        `when`(current.playbackParameters).thenReturn(PlaybackParameters(1.5f))
        `when`(current.currentPosition).thenReturn(12_000L)
        `when`(current.volume).thenReturn(0.4f)
        session.player = current
        // Initial test session is the PCM16 branch, returning to 1x rebuilds it.
        session.setPlaybackParameters(PlaybackParameters.DEFAULT)
        verify(session).rebuildPlayer()
        verify(current, never()).setPlaybackParameters(PlaybackParameters.DEFAULT)
        org.junit.Assert.assertEquals(12_000L, session.pendingResumePositionOverrideMs)
        org.junit.Assert.assertEquals(false, session.nextInitializePlayWhenReady)
        val fresh = mock(ExoPlayer::class.java)
        session.restoreAudioPlaybackParameters(fresh)
        verify(fresh).playbackParameters = PlaybackParameters.DEFAULT
        verify(fresh).volume = 0.4f
    }

    @Test
    fun compatibleSpeedChangesDoNotRebuildAndStaleCallbacksAreIgnored() {
        val session = spy(NativePlaybackSession(mock(NativePlaybackSession.Host::class.java, RETURNS_DEEP_STUBS)))
        val current = mock(ExoPlayer::class.java)
        session.player = current
        session.audioOutputMode = NativeAudioOutputMode.PCM_COMPATIBILITY
        session.setPlaybackParameters(PlaybackParameters(1.5f))
        verify(current).playbackParameters = PlaybackParameters(1.5f)
        session.reconcileAudioPrecision(mock(ExoPlayer::class.java), PlaybackParameters.DEFAULT)
        `when`(current.playbackParameters).thenReturn(PlaybackParameters(2f))
        session.reconcileAudioPrecision(current, PlaybackParameters.DEFAULT)
        verify(session, never()).rebuildPlayer()
    }

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
    fun rapidSpeedRebuildsRetainPendingAudioUntilTracksArrive() {
        val host = mock(NativePlaybackSession.Host::class.java, RETURNS_DEEP_STUBS)
        `when`(host.target.playbackItemKey).thenReturn("episode")
        val session = spy(NativePlaybackSession(host))
        doNothing().`when`(session).rebuildPlayer()
        val selected = Format.Builder().setId("manual").setLanguage("ja")
            .setSampleMimeType(MimeTypes.AUDIO_DTS).build()
        val old = mock(ExoPlayer::class.java)
        val oldTracks = Tracks(listOf(Tracks.Group(TrackGroup(selected), false,
            intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(true))))
        `when`(old.currentTracks).thenReturn(oldTracks)
        `when`(old.playbackParameters).thenReturn(PlaybackParameters.DEFAULT)
        session.player = old
        session.audioOutputState.sinkInput = selected
        session.setPlaybackParameters(PlaybackParameters(1.5f))
        val preparing = mock(ExoPlayer::class.java)
        `when`(preparing.currentTracks).thenReturn(Tracks.EMPTY)
        `when`(preparing.playbackParameters).thenReturn(PlaybackParameters(1.5f))
        session.player = preparing
        assertTrue(session.restoreAudioTrack(Tracks.EMPTY))
        session.setPlaybackParameters(PlaybackParameters.DEFAULT)
        verify(session, times(2)).rebuildPlayer()
        // A third output rebuild can happen before discovery or selection finishes.
        session.restartPlayerWithAudioOutputMode(NativeAudioOutputMode.PCM_COMPATIBILITY)
        verify(session, times(3)).rebuildPlayer()
        val fresh = mock(ExoPlayer::class.java)
        `when`(fresh.trackSelectionParameters).thenReturn(TrackSelectionParameters.Builder().build())
        session.player = fresh
        val group = TrackGroup("fresh", selected)
        assertTrue(session.restoreAudioTrack(Tracks(listOf(Tracks.Group(group, false,
            intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(false))))))
        val captor = org.mockito.ArgumentCaptor.forClass(TrackSelectionParameters::class.java)
        verify(fresh).trackSelectionParameters = captor.capture()
        assertSame(group, captor.value.overrides.values.single().mediaTrackGroup)
    }

    @Test
    fun preparingDefaultTrackDoesNotReplacePendingManualSelection() {
        val host = mock(NativePlaybackSession.Host::class.java, RETURNS_DEEP_STUBS)
        `when`(host.target.playbackItemKey).thenReturn("episode")
        val session = NativePlaybackSession(host)
        val manual = Format.Builder().setId("manual").setLanguage("ja")
            .setSampleMimeType(MimeTypes.AUDIO_AAC).build()
        val default = manual.buildUpon().setId("default").setLanguage("en").build()
        val old = mock(ExoPlayer::class.java)
        val oldTracks = Tracks(listOf(Tracks.Group(TrackGroup(manual), false,
            intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(true))))
        `when`(old.currentTracks).thenReturn(oldTracks)
        `when`(old.playbackParameters).thenReturn(PlaybackParameters.DEFAULT)
        session.player = old
        session.preserveAudioSession()
        val preparing = mock(ExoPlayer::class.java)
        val group = TrackGroup(manual)
        val preparingTracks = Tracks(listOf(
            Tracks.Group(TrackGroup(default), false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(true)),
            Tracks.Group(group, false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(false)),
        ))
        `when`(preparing.currentTracks).thenReturn(preparingTracks)
        `when`(preparing.playbackParameters).thenReturn(PlaybackParameters(1.5f))
        session.player = preparing
        session.preserveAudioSession()
        val parameters = TrackSelectionParameters.Builder().build()
        `when`(preparing.trackSelectionParameters).thenReturn(parameters)
        assertTrue(session.restoreAudioTrack(preparingTracks))
        val captor = org.mockito.ArgumentCaptor.forClass(TrackSelectionParameters::class.java)
        verify(preparing).trackSelectionParameters = captor.capture()
        assertSame(group, captor.value.overrides.values.single().mediaTrackGroup)
    }

    @Test
    fun rebuildImmediatelyAfterRestoreUsesOverrideBeforeSelectedFlagsCatchUp() {
        val host = mock(NativePlaybackSession.Host::class.java, RETURNS_DEEP_STUBS)
        `when`(host.target.playbackItemKey).thenReturn("episode")
        val session = NativePlaybackSession(host)
        val manual = Format.Builder().setId("manual").setLanguage("ja")
            .setSampleMimeType(MimeTypes.AUDIO_AAC).build()
        val default = manual.buildUpon().setId("default").setLanguage("en").build()
        val player = mock(ExoPlayer::class.java)
        val initial = Tracks(listOf(Tracks.Group(TrackGroup(manual), false,
            intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(true))))
        `when`(player.currentTracks).thenReturn(initial)
        `when`(player.playbackParameters).thenReturn(PlaybackParameters.DEFAULT)
        var parameters = TrackSelectionParameters.Builder().build()
        `when`(player.trackSelectionParameters).thenAnswer { parameters }
        doAnswer { parameters = it.getArgument(0); null }.`when`(player).setTrackSelectionParameters(any())
        session.player = player
        session.preserveAudioSession()
        val manualGroup = TrackGroup("new-manual", manual)
        val preparing = Tracks(listOf(
            Tracks.Group(TrackGroup(default), false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(true)),
            Tracks.Group(manualGroup, false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(false)),
        ))
        `when`(player.currentTracks).thenReturn(preparing)
        assertTrue(session.restoreAudioTrack(preparing))
        session.preserveAudioSession()
        val finalGroup = TrackGroup("final-manual", manual)
        val finalTracks = Tracks(listOf(
            Tracks.Group(TrackGroup("final-default", default), false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(true)),
            Tracks.Group(finalGroup, false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(false)),
        ))
        assertTrue(session.restoreAudioTrack(finalTracks))
        assertSame(finalGroup, parameters.overrides.values.single().mediaTrackGroup)
    }

    @Test
    fun pendingAudioDoesNotCrossMediaEvenWhenNewMediaStagesSpeedFirst() {
        for (stageSpeed in listOf(false, true)) {
            val host = mock(NativePlaybackSession.Host::class.java, RETURNS_DEEP_STUBS)
            `when`(host.target.playbackItemKey).thenReturn("one")
            val session = NativePlaybackSession(host)
            val old = mock(ExoPlayer::class.java)
            val format = Format.Builder().setId("same-id").setSampleMimeType(MimeTypes.AUDIO_AAC).build()
            val tracks = Tracks(listOf(Tracks.Group(TrackGroup(format), false,
                intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(true))))
            `when`(old.currentTracks).thenReturn(tracks)
            `when`(old.playbackParameters).thenReturn(PlaybackParameters.DEFAULT)
            session.player = old
            session.preserveAudioSession()
            `when`(host.target.playbackItemKey).thenReturn("two")
            if (stageSpeed) session.stagePlaybackParameters(PlaybackParameters(1.5f))
            assertFalse(session.restoreAudioTrack(tracks))
            `when`(old.currentTracks).thenReturn(Tracks.EMPTY)
            session.preserveAudioSession()
            assertFalse(session.restoreAudioTrack(tracks))
        }
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
        val oldOutputState = session.audioOutputState
        oldOutputState.outputEncoding = C.ENCODING_PCM_FLOAT
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
        org.junit.Assert.assertNotSame(oldOutputState, session.audioOutputState)
        oldOutputState.sinkInput = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_DTS).build()
        assertNull(session.audioOutputState.outputEncoding)
        assertFalse(session.audioOutputState.isPassthrough())
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
