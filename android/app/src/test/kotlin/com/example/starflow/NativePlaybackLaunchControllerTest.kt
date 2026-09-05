package com.example.starflow

import android.os.Handler
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackLaunchControllerTest {
    @Test
    fun everyEpisodeSchedulesTimeoutEvenAfterInitialLaunchWasReported() {
        val host = mock(NativePlaybackLaunchController.Host::class.java)
        val handler = mock(Handler::class.java)
        val launch = NativePlaybackLaunchController(host, handler)
        launch.reportPlaybackLaunchResult(NativePlaybackActivity.RESULT_PLAYBACK_READY)
        launch.schedulePlaybackLaunchTimeout()
        launch.cancelPlaybackLaunchTimeout()
        launch.schedulePlaybackLaunchTimeout()
        verify(handler, times(2)).postDelayed(any(Runnable::class.java), eq(30_000L))
        verify(handler, times(3)).removeCallbacks(any(Runnable::class.java))
    }
}
