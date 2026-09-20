package com.example.starflow

import android.net.Uri
import android.os.Handler
import androidx.media3.common.MediaItem
import java.util.concurrent.ExecutorService
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class NativeExternalSubtitleLifecycleTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()
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

    @Test fun newerOffInternalAndDualIntentsRejectCompletedBuildAndCleanPreparedFile() {
        prepare()
        val trackHost = mock(NativePlaybackTrackController.Host::class.java, RETURNS_DEEP_STUBS)
        val subtitles = NativePlaybackTrackController(trackHost)
        `when`(host.subtitles).thenReturn(subtitles)
        `when`(trackHost.externalSubtitles).thenReturn(controller)
        val configuration = MediaItem.SubtitleConfiguration.Builder(mock(Uri::class.java)).build()
        val source = controller.externalSubtitleSource!!
        `when`(host.subtitleFiles.buildSubtitleConfiguration(source, 0L)).thenReturn(configuration)
        for (mode in NativeSubtitleSessionMode.values()) {
            controller.externalSubtitleSource = source
            var applied = false
            var failed = false
            assertTrue(controller.applyExternalSubtitleConfiguration(onApplied = { applied = true }, onFailure = { failed = true }))
            jobs.removeAt(0).run()
            subtitles.beginSubtitleSelection()
            subtitles.subtitleSessionPreference = NativeSubtitleSessionPreference(mode)
            callbacks.removeAt(0).run()
            jobs.removeAt(0).run()
            assertFalse(applied)
            assertFalse(failed)
            assertEquals(mode, subtitles.subtitleSessionPreference?.mode)
        }
        verify(host.subtitleFiles, times(3)).deletePrepared(configuration.uri)
        verify(host.session.player!!, never()).setMediaItem(any(MediaItem::class.java), anyLong())
        verify(host.session.player!!, never()).prepare()
    }

    @Test fun revisionAloneRejectsBuildEvenWhenPlayerAndSourceAreUnchanged() {
        prepare()
        `when`(host.subtitles.subtitleSelectionRevision).thenReturn(1L)
        val configuration = MediaItem.SubtitleConfiguration.Builder(mock(Uri::class.java)).build()
        `when`(host.subtitleFiles.buildSubtitleConfiguration(controller.externalSubtitleSource!!, 0L))
            .thenReturn(configuration)
        assertTrue(controller.applyExternalSubtitleConfiguration())
        jobs.removeAt(0).run()
        `when`(host.subtitles.subtitleSelectionRevision).thenReturn(2L)
        callbacks.removeAt(0).run()
        jobs.removeAt(0).run()
        verify(host.subtitleFiles).deletePrepared(configuration.uri)
        verify(host.session.player!!, never()).prepare()
    }

    @Test fun staleDownloadRevisionCannotEvenChangeExternalSource() {
        prepare()
        val source = controller.externalSubtitleSource
        `when`(host.subtitles.subtitleSelectionRevision).thenReturn(2L)
        assertFalse(controller.loadCachedSubtitleFile("/tmp/old.srt", "old", selectionRevision = 1L))
        assertSame(source, controller.externalSubtitleSource)
        assertTrue(jobs.isEmpty())
    }

    @Test fun unchangedIntentMountsAndReportsSuccessOnlyAfterBuild() {
        prepare()
        val configuration = MediaItem.SubtitleConfiguration.Builder(mock(Uri::class.java)).build()
        `when`(host.subtitleFiles.buildSubtitleConfiguration(controller.externalSubtitleSource!!, 0L))
            .thenReturn(configuration)
        `when`(host.session.baseMediaItem).thenReturn(MediaItem.Builder().setMediaId("media").build())
        `when`(host.session.player!!.currentPosition).thenReturn(12_000L)
        var applied = false
        assertTrue(controller.applyExternalSubtitleConfiguration(showFeedback = false, onApplied = { applied = true }))
        assertFalse(applied)
        jobs.removeAt(0).run()
        assertFalse(applied)
        callbacks.removeAt(0).run()
        assertTrue(applied)
        verify(host.session.player!!).setMediaItem(any(MediaItem::class.java), eq(12_000L))
        verify(host.session.player!!).prepare()
        verify(host.subtitles).pendingExternalSubtitleSelection = true
    }

    @Test fun staleFailureDoesNotRollbackNewerSelectionOrShowFailure() {
        prepare()
        `when`(host.subtitleFiles.buildSubtitleConfiguration(controller.externalSubtitleSource!!, 0L))
            .thenThrow(IllegalArgumentException("invalid old subtitle"))
        var failed = false
        controller.applyExternalSubtitleConfiguration(onFailure = { failed = true })
        jobs.removeAt(0).run()
        controller.externalSubtitleSource = null
        callbacks.removeAt(0).run()
        assertFalse(failed)
        assertNull(controller.externalSubtitleSource)
        verify(host, never()).showToast(anyString())
    }
}
