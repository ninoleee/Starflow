package com.example.starflow

import androidx.media3.common.Player
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackEpisodeControllerTest {
    private val host = mock(NativePlaybackEpisodeController.Host::class.java, RETURNS_DEEP_STUBS)
    private var time = 100_000L
    private val callbacks = mutableListOf<(Map<String, Any?>) -> Unit>()
    private val requestedTargets = mutableListOf<String>()
    private val controller =
        NativePlaybackEpisodeController(host, { time }) { _, target, callback ->
            requestedTargets += target
            callbacks += callback
            true
        }
    private val source =
        NativeEpisodeQueueEntry("""{"streamUrl":"https://host/1.mkv"}""", "one", "series")
    private val next =
        NativeEpisodeQueueEntry("""{"streamUrl":"https://host/2.strm"}""", "two", "series")
    private val resolved =
        mapOf<String, Any?>(
            "ok" to true,
            "playbackTargetJson" to
                """{"streamUrl":"https://host/resolved.mkv","headers":{"Authorization":"resolved"}}""",
            "playbackItemKey" to "two",
            "seriesKey" to "series",
            "mediaMimeType" to "video/x-matroska",
        )

    @Before
    fun setup() {
        controller.episodeQueue = NativeEpisodeQueue(listOf(source, next))
        `when`(host.target.playbackTargetJson).thenReturn(source.playbackTargetJson)
        `when`(host.target.resolverSessionId).thenReturn("resolver")
        `when`(host.target.seriesKey).thenReturn("series")
        `when`(host.activity.intent.getStringExtra(anyString())).thenReturn("")
        `when`(host.session.player!!.playWhenReady).thenReturn(true)
        `when`(host.session.player!!.playbackState).thenReturn(Player.STATE_READY)
        `when`(host.session.player!!.duration).thenReturn(100_000L)
        `when`(host.session.player!!.currentPosition).thenReturn(60_000L)
        `when`(host.memory.loadSeriesSkipPreference("series"))
            .thenReturn(JSONObject("""{"enabled":true,"outroDurationMs":10000}"""))
        val activity = host.activity
        doAnswer { call ->
                call.getArgument<Runnable>(0).run()
                null
            }
            .`when`(activity)
            .runOnUiThread(any(Runnable::class.java))
    }

    @Test
    fun preparationDoesNotChangeQueueAndOutrosUseItWithoutAnotherRequest() {
        val oldQueue = controller.episodeQueue
        controller.tick()
        assertEquals(1, callbacks.size)
        callbacks.single()(resolved)
        assertSame(oldQueue, controller.episodeQueue)
        verify(host.session, never()).releasePlayer()
        verify(host, never()).showToast(anyString())
        assertTrue(controller.advanceToAdjacentEpisode(true, "outro"))
        assertEquals(1, callbacks.size)
        val order = inOrder(host.runtime, host.session)
        order.verify(host.runtime).markAutoSkipCompleted()
        order.verify(host.session).releasePlayer()
        order.verify(host.session).initializePlayer()
        verify(host.session).nextEpisodeIsAutomatic = true
        verify(host.activity.intent)
            .putExtra(NativePlaybackActivity.EXTRA_HEADERS_JSON, """{"Authorization":"resolved"}""")
        assertEquals(1, controller.episodeQueue?.currentIndex)
        assertTrue(controller.isSwitching)
        controller.advanceToAdjacentEpisode(true, "ended")
        verify(host.session, times(1)).initializePlayer()
        controller.onPlaybackReady()
        assertFalse(controller.isSwitching)
    }

    @Test
    fun inflightPreparationIsPromotedAndPausePreventsLateSwitch() {
        controller.tick()
        controller.advanceToAdjacentEpisode(true, "outro")
        assertEquals(1, callbacks.size)
        `when`(host.session.player!!.playWhenReady).thenReturn(false)
        callbacks.single()(resolved)
        verify(host.session, never()).releasePlayer()
        assertEquals(0, controller.episodeQueue?.currentIndex)
        `when`(host.session.player!!.playWhenReady).thenReturn(true)
        controller.advanceToAdjacentEpisode(true, "outro")
        verify(host.session).initializePlayer()
    }

    @Test
    fun sourceChangeRejectsLateResult() {
        controller.tick()
        `when`(host.target.resolverSessionId).thenReturn("new-resolver")
        callbacks.single()(resolved)
        verify(host.session, never()).releasePlayer()
        assertEquals(0, controller.episodeQueue?.currentIndex)
    }

    @Test
    fun foregroundTimeoutKeepsOldPlayerAndDoesNotLoopOnEnded() {
        controller.advanceToAdjacentEpisode(true, "outro")
        time += 30_000L
        controller.tick()
        callbacks.first()(resolved)
        controller.advanceToAdjacentEpisode(true, "ended")
        assertEquals(1, callbacks.size)
        verify(host.session, never()).releasePlayer()
        controller.advanceToAdjacentEpisode(true, "remote-next")
        assertEquals(2, callbacks.size)
    }

    @Test
    fun backgroundFailureIsSilentAndForegroundCanRetry() {
        controller.tick()
        callbacks.single()(mapOf("ok" to false))
        controller.tick()
        assertEquals(1, callbacks.size)
        verify(host, never()).showToast(anyString())
        controller.advanceToAdjacentEpisode(true, "outro")
        assertEquals(2, callbacks.size)
    }

    @Test
    fun newIntentInvalidatesInflightResult() {
        controller.advanceToAdjacentEpisode(true, "outro")
        controller.invalidateResolution()
        callbacks.single()(resolved)
        verify(host.session, never()).releasePlayer()
    }

    @Test
    fun preparedCacheExpiryUsesOriginalUnresolvedTarget() {
        controller.tick()
        callbacks.single()(resolved)
        time += 60_000L
        controller.advanceToAdjacentEpisode(true, "outro")
        assertEquals(listOf(next.playbackTargetJson, next.playbackTargetJson), requestedTargets)
        verify(host.session, never()).releasePlayer()
    }
}
