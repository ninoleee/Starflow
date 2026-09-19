package com.example.starflow

import android.net.Uri
import android.os.Handler
import androidx.media3.common.MediaItem
import java.util.concurrent.ExecutorService
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class NativeExternalSubtitleLifecycleTest {
    private val host = mock(NativePlaybackExternalSubtitleController.Host::class.java, RETURNS_DEEP_STUBS)
    private val handler = mock(Handler::class.java)
    private val worker = mock(ExecutorService::class.java)
    private val controller = NativePlaybackExternalSubtitleController(host, handler, worker)
    private val jobs = mutableListOf<Runnable>()
    private val callbacks = mutableListOf<Runnable>()

    private fun prepare() {
        doAnswer { jobs += it.getArgument<Runnable>(0); null }.`when`(worker).execute(any(Runnable::class.java))
        doAnswer { callbacks += it.getArgument<Runnable>(0); true }.`when`(handler).post(any(Runnable::class.java))
        `when`(host.target.playbackTargetJson).thenReturn("episode-one")
        controller.externalSubtitleSource = ExternalSubtitleSource(mock(Uri::class.java), "application/x-subrip", "test")
    }

    @Test fun latePreparationCannotReplaceAnotherEpisode() {
        prepare()
        assertTrue(controller.applyExternalSubtitleConfiguration())
        `when`(host.target.playbackTargetJson).thenReturn("episode-two")
        jobs.removeAt(0).run()
        callbacks.removeAt(0).run()
        verify(host.session.player!!, never()).setMediaItem(any(MediaItem::class.java), anyLong())
    }

    @Test fun closeInvalidatesQueuedPreparationAndIsIdempotent() {
        prepare()
        assertTrue(controller.applyExternalSubtitleConfiguration())
        controller.close()
        controller.close()
        jobs.removeAt(0).run()
        callbacks.removeAt(0).run()
        verify(host.session.player!!, never()).setMediaItem(any(MediaItem::class.java), anyLong())
        verify(worker, times(1)).shutdown()
        assertFalse(controller.applyExternalSubtitleConfiguration())
    }

    @Test fun processingFailureDoesNotReportSuccessfulMount() {
        prepare()
        var applied = false
        var failed = false
        `when`(host.subtitleFiles.buildSubtitleConfiguration(controller.externalSubtitleSource!!, 0L))
            .thenThrow(IllegalArgumentException("invalid subtitle"))
        assertTrue(controller.applyExternalSubtitleConfiguration(onApplied = { applied = true }, onFailure = { failed = true }))
        jobs.removeAt(0).run()
        callbacks.removeAt(0).run()
        assertFalse(applied)
        assertTrue(failed)
        verify(host.session.player!!, never()).setMediaItem(any(MediaItem::class.java), anyLong())
    }
}
