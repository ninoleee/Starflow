package com.example.starflow

import android.os.Handler
import androidx.media3.common.Player
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackLaunchControllerTest {
    private val host = mock(NativePlaybackLaunchController.Host::class.java, RETURNS_DEEP_STUBS)
    private val handler = mock(Handler::class.java)
    private val source = mock(DataSource::class.java)
    private val dataSpec = mock(DataSpec::class.java)
    private var time = 1_000L
    private var finishing = false
    private var scheduled: Runnable? = null
    private var scheduledAt = 0L
    private val transfer = NativePlaybackTransferProgress { time }
    private val launch = NativePlaybackLaunchController(host, handler) { time }

    @Before
    fun setup() {
        `when`(host.session.playbackTransferProgress).thenReturn(transfer)
        `when`(host.session.player!!.playbackState).thenReturn(Player.STATE_BUFFERING)
        `when`(host.session.player!!.isLoading).thenReturn(true)
        `when`(host.activity.isFinishing).thenAnswer { finishing }
        // Stop at failure notification without constructing an Android dialog in the JVM.
        val episodes = host.episodes
        doAnswer {
            finishing = true
            null
        }.`when`(episodes).onPlaybackFailed()
        doAnswer { call ->
            scheduled = call.getArgument(0)
            scheduledAt = time + call.getArgument<Long>(1)
            true
        }.`when`(handler).postDelayed(any(Runnable::class.java), anyLong())
        doAnswer { call ->
            if (scheduled === call.getArgument<Runnable>(0)) scheduled = null
            null
        }.`when`(handler).removeCallbacks(any(Runnable::class.java))
    }

    private fun advanceBy(milliseconds: Long) {
        val target = time + milliseconds
        while (scheduled != null && scheduledAt <= target) {
            time = scheduledAt
            val callback = scheduled!!
            scheduled = null
            callback.run()
        }
        time = target
    }

    private fun receiveBytes(progress: NativePlaybackTransferProgress = transfer) {
        progress.onBytesTransferred(source, dataSpec, true, 4_096)
    }

    @Test
    fun qualityFailureUsesRollbackBeforeShowingPlaybackFailure() {
        `when`(host.fntv.recoverQualityFailure()).thenReturn(true)
        launch.handlePlaybackFailure("quality failed")
        verify(host.fntv).recoverQualityFailure()
        verify(host.episodes, never()).onPlaybackFailed()
        verify(host.session, never()).releasePlayer()
    }

    @Test
    fun loadingFlagWithoutActualProgressFailsAtThirtySeconds() {
        launch.schedulePlaybackLaunchTimeout()
        advanceBy(29_999L)
        verify(host.episodes, never()).onPlaybackFailed()
        advanceBy(1L)
        verify(host.episodes).onPlaybackFailed()
        assertFalse(launch.isStartupPending)
        assertNull(scheduled)
    }

    @Test
    fun receivedBytesKeepContainerLoadingAliveWithoutBufferedSamples() {
        launch.schedulePlaybackLaunchTimeout()
        advanceBy(20_000L)
        receiveBytes()
        advanceBy(10_000L)
        verify(host.episodes, never()).onPlaybackFailed()
        assertTrue(launch.isStartupPending)
    }

    @Test
    fun idleDeadlineUsesActualReceiveTimeInsteadOfNextPollingWindow() {
        launch.schedulePlaybackLaunchTimeout()
        advanceBy(10_250L)
        receiveBytes()
        advanceBy(29_999L)
        verify(host.episodes, never()).onPlaybackFailed()
        advanceBy(1L)
        verify(host.episodes).onPlaybackFailed()
    }

    @Test
    fun continuousTransferStillStopsAtSixtySeconds() {
        launch.schedulePlaybackLaunchTimeout()
        repeat(59) {
            advanceBy(1_000L)
            receiveBytes()
        }
        verify(host.episodes, never()).onPlaybackFailed()
        advanceBy(999L)
        receiveBytes()
        advanceBy(1L)
        verify(host.episodes).onPlaybackFailed()
        assertFalse(launch.isStartupPending)
    }

    @Test
    fun bufferedMediaGrowthWithoutNetworkBytesExtendsTheIdleDeadline() {
        launch.schedulePlaybackLaunchTimeout()
        advanceBy(9_999L)
        `when`(host.session.player!!.totalBufferedDuration).thenReturn(2_000L)
        advanceBy(20_001L)
        verify(host.episodes, never()).onPlaybackFailed()
        advanceBy(9_999L)
        verify(host.episodes, never()).onPlaybackFailed()
        advanceBy(1L)
        verify(host.episodes).onPlaybackFailed()
    }

    @Test
    fun introOrResumeOffsetIsNotDownloadedBufferProgress() {
        `when`(host.session.player!!.currentPosition).thenReturn(120_000L)
        `when`(host.session.player!!.bufferedPosition).thenReturn(120_000L)
        `when`(host.session.player!!.bufferedPercentage).thenReturn(40)
        `when`(host.session.player!!.totalBufferedDuration).thenReturn(0L)
        launch.schedulePlaybackLaunchTimeout()
        advanceBy(30_000L)
        verify(host.episodes).onPlaybackFailed()
    }

    @Test
    fun readyVideoWithoutFirstFrameOrProgressStillFails() {
        `when`(host.session.player!!.playbackState).thenReturn(Player.STATE_READY)
        launch.schedulePlaybackLaunchTimeout()
        advanceBy(30_000L)
        verify(host.episodes).onPlaybackFailed()
    }

    @Test
    fun rebuildDoesNotResetTheNoProgressDeadline() {
        launch.schedulePlaybackLaunchTimeout()
        advanceBy(20_000L)
        launch.cancelPlaybackLaunchTimeout()
        launch.schedulePlaybackLaunchTimeout()
        advanceBy(9_999L)
        verify(host.episodes, never()).onPlaybackFailed()
        advanceBy(1L)
        verify(host.episodes).onPlaybackFailed()
    }

    @Test
    fun startupHardDeadlineSurvivesRebuildAndNewTransferListener() {
        launch.schedulePlaybackLaunchTimeout()
        repeat(5) {
            advanceBy(9_000L)
            receiveBytes()
        }
        launch.cancelPlaybackLaunchTimeout()
        advanceBy(14_999L)
        val nextTransfer = NativePlaybackTransferProgress { time }
        `when`(host.session.playbackTransferProgress).thenReturn(nextTransfer)
        launch.schedulePlaybackLaunchTimeout()
        assertEquals(1L, scheduledAt - time)
        receiveBytes(nextTransfer)
        advanceBy(1L)
        verify(host.episodes).onPlaybackFailed()
    }

    @Test
    fun expiredBudgetRejectsRebuildBeforeItCanPrepareAgain() {
        launch.schedulePlaybackLaunchTimeout()
        advanceBy(20_000L)
        launch.cancelPlaybackLaunchTimeout()
        advanceBy(40_000L)
        launch.schedulePlaybackLaunchTimeout()
        verify(host.episodes).onPlaybackFailed()
        assertFalse(launch.isStartupPending)
        assertNull(scheduled)
    }

    @Test
    fun oldPlayerTransferCannotExtendTheNextEpisodesStartup() {
        launch.schedulePlaybackLaunchTimeout()
        advanceBy(10_000L)
        receiveBytes()
        launch.cancelPlaybackLaunchTimeout()
        launch.resetStartupDeadline()
        `when`(host.session.playbackTransferProgress)
            .thenReturn(NativePlaybackTransferProgress { time })
        launch.schedulePlaybackLaunchTimeout()
        advanceBy(29_999L)
        receiveBytes(transfer)
        advanceBy(1L)
        verify(host.episodes).onPlaybackFailed()
    }

    @Test
    fun rebuildsHaveFiniteStartupAttemptsAndManualRetryResetsTheBudget() {
        repeat(3) {
            launch.schedulePlaybackLaunchTimeout()
            launch.cancelPlaybackLaunchTimeout()
        }
        verify(host.episodes, never()).onPlaybackFailed()
        launch.schedulePlaybackLaunchTimeout()
        verify(host.episodes).onPlaybackFailed()
        finishing = false
        launch.resetStartupDeadline()
        launch.schedulePlaybackLaunchTimeout()
        advanceBy(29_999L)
        assertTrue(launch.isStartupPending)
        verify(host.episodes, times(1)).onPlaybackFailed()
    }

    @Test
    fun everyEpisodeHasAnIndependentDeadlineAfterFirstFrame() {
        launch.schedulePlaybackLaunchTimeout()
        advanceBy(20_000L)
        launch.cancelPlaybackLaunchTimeout()
        launch.reportPlaybackLaunchResult(NativePlaybackActivity.RESULT_PLAYBACK_READY)
        advanceBy(60_000L)
        verify(host.episodes, never()).onPlaybackFailed()
        launch.schedulePlaybackLaunchTimeout()
        advanceBy(29_999L)
        verify(host.episodes, never()).onPlaybackFailed()
        advanceBy(1L)
        verify(host.episodes).onPlaybackFailed()
    }
}
