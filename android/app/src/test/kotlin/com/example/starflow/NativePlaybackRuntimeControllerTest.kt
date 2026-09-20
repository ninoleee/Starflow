package com.example.starflow

import androidx.media3.common.Player
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackRuntimeControllerTest {
    private val host = mock(NativePlaybackRuntimeController.Host::class.java, RETURNS_DEEP_STUBS)
    private var time = 100_000L
    private val runtime = NativePlaybackRuntimeController(host, NativePlaybackWatchdogPolicy { time })
    private var position = 60_000L

    @Before
    fun setup() {
        `when`(host.session.player!!.playWhenReady).thenReturn(true)
        `when`(host.session.player!!.playbackState).thenReturn(Player.STATE_READY)
        `when`(host.session.player!!.duration).thenReturn(100_000L)
        `when`(host.session.player!!.currentPosition).thenAnswer { position }
        `when`(host.target.seriesKey).thenReturn("series")
        `when`(host.target.playbackItemKey).thenReturn("episode")
        `when`(host.target.playbackTargetJson).thenReturn("{}")
        `when`(host.memory.peekSeriesSkipPreference("series"))
            .thenReturn(
                JSONObject("""{"enabled":true,"introDurationMs":10000,"outroDurationMs":40000}""")
            )
        runtime.introSkipApplied = true
    }

    @Test
    fun finalAndAutoSkipProgressReportCompletionToServer() {
        runtime.markAutoSkipCompleted()
        verify(host.fntv).report(100_000L, 100_000L)
        runtime.onUserSeek()
        runtime.persistPlaybackProgress(force = true)
        verify(host.fntv).report(60_000L, 100_000L)
        `when`(host.session.player!!.playbackState).thenReturn(Player.STATE_ENDED)
        runtime.persistPlaybackProgress(force = true)
        verify(host.fntv, times(2)).report(100_000L, 100_000L)
    }

    @Test
    fun periodicProgressIsThrottledButForcedSaveIsNot() {
        runtime.persistPlaybackProgress()
        position += 1_000L
        runtime.persistPlaybackProgress()
        verify(host.fntv, times(1)).report(anyLong(), anyLong())
        runtime.persistPlaybackProgress(force = true)
        verify(host.fntv).report(61_000L, 100_000L)
    }

    @Test
    fun outroRequestsNextWithoutSeekingOrPausing() {
        `when`(host.episodes.advanceToAdjacentEpisode(true, "outro")).thenReturn(true)
        runtime.maybeApplyAutoSkip()
        verify(host.episodes).advanceToAdjacentEpisode(true, "outro")
        verify(host.session.player!!, never()).seekTo(anyLong())
        verify(host.session, never()).setPlayWhenReady(false)
        verify(host.memory, never())
            .enqueuePlaybackEntry(
                anyString(),
                anyString(),
                anyString(),
                anyLong(),
                anyLong(),
                anyBoolean(),
                anyBoolean(),
            )
    }

    @Test
    fun lastEpisodePausesAndKeepsCompletionOnSubsequentSaves() {
        runtime.maybeApplyAutoSkip()
        verify(host.session).setPlayWhenReady(false)
        verify(host.session.player!!, never()).seekTo(anyLong())
        runtime.persistPlaybackProgress(force = true)
        verify(host.memory, times(2))
            .enqueuePlaybackEntry("{}", "episode", "series", 60_000L, 100_000L, true, true)
        runtime.maybeApplyAutoSkip()
        verify(host.session, times(1)).setPlayWhenReady(false)
    }

    @Test
    fun seekBackClearsCompletionAndDoesNotReplayIntroSkip() {
        runtime.markAutoSkipCompleted()
        position = 5_000L
        runtime.onUserSeek()
        runtime.maybeApplyAutoSkip()
        runtime.persistPlaybackProgress(force = true)
        verify(host.session.player!!, never()).seekTo(anyLong())
        verify(host.memory)
            .enqueuePlaybackEntry("{}", "episode", "series", 5_000L, 100_000L, true, false)
    }

    @Test
    fun pauseAndSwitchingDoNotTriggerAutomaticSkip() {
        `when`(host.session.player!!.playWhenReady).thenReturn(false)
        runtime.maybeApplyAutoSkip()
        `when`(host.session.player!!.playWhenReady).thenReturn(true)
        `when`(host.episodes.isSwitching).thenReturn(true)
        runtime.maybeApplyAutoSkip()
        verify(host.episodes, never()).advanceToAdjacentEpisode(anyBoolean(), anyString())
    }

    @Test
    fun invalidIntroDoesNotSkipEntireEpisode() {
        position = 0L
        `when`(host.memory.peekSeriesSkipPreference("series"))
            .thenReturn(JSONObject("""{"enabled":true,"introDurationMs":100000}"""))
        runtime.introSkipApplied = false
        runtime.maybeApplyAutoSkip()
        verify(host.session.player!!, never()).seekTo(anyLong())
    }

    @Test
    fun manualSeekIntoCreditsAllowsWatchingThem() {
        runtime.onUserSeek()
        runtime.maybeApplyAutoSkip()
        verify(host.episodes, never()).advanceToAdjacentEpisode(anyBoolean(), anyString())
    }

    @Test
    fun startupDoesNotSeekOrRebuildWhileLaunchControllerOwnsTheDeadline() {
        `when`(host.activity.hasWindowFocus()).thenReturn(true)
        `when`(host.session.player!!.playbackState).thenReturn(Player.STATE_BUFFERING)
        `when`(host.launch.isStartupPending).thenReturn(true)
        runtime.resetPlaybackWatchdogProgress(position)
        repeat(3) {
            time += 30_000L
            assertTrue(runtime.evaluatePlaybackWatchdog())
        }
        verify(host.recovery, never()).recoverPlaybackStall(anyLong())

        `when`(host.launch.isStartupPending).thenReturn(false)
        assertTrue(runtime.evaluatePlaybackWatchdog())
        time += 44_999L
        assertTrue(runtime.evaluatePlaybackWatchdog())
        verify(host.recovery, never()).recoverPlaybackStall(anyLong())
        time++
        runtime.evaluatePlaybackWatchdog()
        verify(host.recovery).recoverPlaybackStall(position)
    }
}
