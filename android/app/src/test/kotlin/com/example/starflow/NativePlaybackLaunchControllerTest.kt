package com.example.starflow

import android.os.Handler
import org.junit.Test
import org.mockito.ArgumentCaptor
import org.mockito.Mockito.*

class NativePlaybackLaunchControllerTest {
    @Test
    fun startupDeadlineSurvivesRebuildAndCannotExtendForever() {
        val host = mock(NativePlaybackLaunchController.Host::class.java, RETURNS_DEEP_STUBS)
        val handler = mock(Handler::class.java)
        var time = 1_000L
        val launch = NativePlaybackLaunchController(host, handler) { time }
        launch.schedulePlaybackLaunchTimeout()
        time += 110_000L
        launch.cancelPlaybackLaunchTimeout()
        launch.schedulePlaybackLaunchTimeout()
        val scheduled = ArgumentCaptor.forClass(Runnable::class.java)
        verify(handler).postDelayed(scheduled.capture(), eq(10_000L))
        time += 10_000L
        `when`(host.session.player!!.bufferedPosition).thenReturn(100_000L)
        // Avoid constructing a real dialog in this JVM test, after the failure
        // has already notified the episode controller.
        `when`(host.activity.isFinishing).thenReturn(false, true)
        scheduled.value.run()
        verify(host.episodes).onPlaybackFailed()
        verify(handler, times(2)).postDelayed(any(Runnable::class.java), anyLong())
    }

    @Test
    fun rebuildsHaveFiniteStartupAttempts() {
        val host = mock(NativePlaybackLaunchController.Host::class.java, RETURNS_DEEP_STUBS)
        val handler = mock(Handler::class.java)
        val launch = NativePlaybackLaunchController(host, handler) { 1_000L }
        `when`(host.activity.isFinishing).thenReturn(true)
        repeat(4) { launch.schedulePlaybackLaunchTimeout() }
        verify(host.episodes).onPlaybackFailed()
        verify(handler, times(3)).postDelayed(any(Runnable::class.java), anyLong())
        launch.resetStartupDeadline()
        launch.schedulePlaybackLaunchTimeout()
        verify(handler, times(4)).postDelayed(any(Runnable::class.java), anyLong())
    }

    @Test
    fun timeoutWaitsAnotherWindowWhileBufferingStillAdvances() {
        val host = mock(NativePlaybackLaunchController.Host::class.java, RETURNS_DEEP_STUBS)
        val handler = mock(Handler::class.java)
        val launch = NativePlaybackLaunchController(host, handler) { 0L }
        `when`(host.session.player!!.bufferedPosition).thenReturn(4_000L)
        `when`(host.session.player!!.bufferedPercentage).thenReturn(3)
        launch.schedulePlaybackLaunchTimeout()

        val scheduled = ArgumentCaptor.forClass(Runnable::class.java)
        verify(handler).postDelayed(scheduled.capture(), eq(PLAYBACK_LAUNCH_TIMEOUT_MS))
        scheduled.value.run()

        verify(handler, times(2))
            .postDelayed(any(Runnable::class.java), eq(PLAYBACK_LAUNCH_TIMEOUT_MS))
        verify(host.episodes, never()).onPlaybackFailed()
        verify(host.session, never()).releasePlayer()
    }

    @Test
    fun everyEpisodeSchedulesTimeoutEvenAfterInitialLaunchWasReported() {
        val host = mock(NativePlaybackLaunchController.Host::class.java)
        val handler = mock(Handler::class.java)
        val launch = NativePlaybackLaunchController(host, handler) { 0L }
        launch.reportPlaybackLaunchResult(NativePlaybackActivity.RESULT_PLAYBACK_READY)
        launch.schedulePlaybackLaunchTimeout()
        launch.cancelPlaybackLaunchTimeout()
        launch.schedulePlaybackLaunchTimeout()
        verify(handler, times(2)).postDelayed(any(Runnable::class.java), eq(30_000L))
        verify(handler, times(3)).removeCallbacks(any(Runnable::class.java))
    }
}
