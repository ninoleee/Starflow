package com.example.starflow

import org.junit.Assert.*
import org.junit.Test

class NativeEpisodeTransitionTest {
    private var time = 100_000L
    private val transition = NativeEpisodeTransition { time }
    private val entry = NativeEpisodeQueueEntry("target", "episode", "series")
    private val key =
        NativeEpisodePreparationKey(
            NativeEpisodeQueue(listOf(entry, entry, entry)),
            1,
            "source",
            "resolver",
            "url",
            "headers",
            "mime",
        )

    @Test
    fun prefetchDoesNotSwitchAndIsConsumedOnce() {
        val request = transition.prefetch(key)!!
        assertNull(transition.prefetch(key))
        assertNull(transition.resolve(request, entry))
        assertEquals(NativeEpisodeTransition.State.IDLE, transition.state)
        val ready = transition.begin(key, "outro") as NativeEpisodeTransition.Decision.Ready
        assertTrue(ready.destination.prepared)
        assertEquals(entry, ready.destination.entry)
        transition.awaitFirstFrame()
        assertEquals(
            NativeEpisodeTransition.Decision.Wait,
            transition.begin(key.copy(index = 2), "ended"),
        )
        assertEquals(
            NativeEpisodeTransition.Decision.Wait,
            transition.begin(key.copy(index = 2), "remote-next"),
        )
        transition.onFirstFrame()
        assertEquals(NativeEpisodeTransition.State.IDLE, transition.state)
    }

    @Test
    fun advancePromotesInflightPreparationWithoutSecondRequest() {
        val request = transition.prefetch(key)!!
        assertEquals(NativeEpisodeTransition.Decision.Wait, transition.begin(key, "outro"))
        assertEquals(request, transition.pending)
        assertEquals(NativeEpisodeTransition.Decision.Wait, transition.begin(key, "ended"))
        assertEquals("outro", transition.resolve(request, entry)?.reason)
    }

    @Test
    fun repeatedAutomaticFailureDoesNotLoopAndManualRetryIsAllowed() {
        val request =
            (transition.begin(key, "outro") as NativeEpisodeTransition.Decision.Resolve).request
        assertEquals("outro", transition.fail(request))
        assertEquals(NativeEpisodeTransition.State.FAILED, transition.state)
        assertEquals(NativeEpisodeTransition.Decision.Wait, transition.begin(key, "ended"))
        assertEquals(NativeEpisodeTransition.Decision.Wait, transition.begin(key, "outro"))
        assertTrue(transition.begin(key, "remote-next") is NativeEpisodeTransition.Decision.Resolve)
    }

    @Test
    fun backgroundFailureIsQuietAndDoesNotBlockForeground() {
        val request = transition.prefetch(key)!!
        assertNull(transition.fail(request))
        assertNull(transition.prefetch(key))
        assertTrue(transition.begin(key, "outro") is NativeEpisodeTransition.Decision.Resolve)
    }

    @Test
    fun preparedAddressesExpireAtSixtySeconds() {
        transition.resolve(transition.prefetch(key)!!, entry)
        time += 60_000L
        assertTrue(transition.begin(key, "outro") is NativeEpisodeTransition.Decision.Resolve)
    }

    @Test
    fun expiresPendingResolutionAndRejectsLateResult() {
        val request = transition.prefetch(key)!!
        time += 29_999L
        assertNull(transition.expiredRequest())
        time++
        assertEquals(request, transition.expiredRequest())
        transition.fail(request)
        assertNull(transition.resolve(request, entry))
    }

    @Test
    fun cacheIsBoundToSourceHeadersQueueAndResolver() {
        for (changed in
            listOf(
                key.copy(sourceHeaders = "other"),
                key.copy(sourceUrl = "other"),
                key.copy(resolverSessionId = "other"),
                key.copy(sourceTargetJson = "other"),
                key.copy(
                    queue = key.queue.copy(entries = listOf(entry, entry.copy(seriesKey = "other")))
                ),
            )) {
            transition.reset()
            transition.resolve(transition.prefetch(key)!!, entry)
            assertTrue(
                transition.begin(changed, "outro") is NativeEpisodeTransition.Decision.Resolve
            )
        }
    }

    @Test
    fun newIntentInvalidatesRequestAndCache() {
        val request = transition.prefetch(key)!!
        transition.reset()
        assertNull(transition.resolve(request, entry))
        val next = transition.prefetch(key)!!
        assertNotEquals(request.id, next.id)
    }

    @Test
    fun manualSelectionSupersedesAutomaticRequestButNotViceVersa() {
        val old =
            (transition.begin(key, "outro") as NativeEpisodeTransition.Decision.Resolve).request
        val manual =
            transition.begin(key.copy(index = 2), "episode-picker")
                as NativeEpisodeTransition.Decision.Resolve
        assertNull(transition.resolve(old, entry))
        assertEquals(NativeEpisodeTransition.Decision.Wait, transition.begin(key, "ended"))
        assertEquals("episode-picker", transition.resolve(manual.request, entry)?.reason)
    }

    @Test
    fun pauseOrBackwardSeekDemotesAutomaticRequestToCacheOnly() {
        val request =
            (transition.begin(key, "outro") as NativeEpisodeTransition.Decision.Resolve).request
        transition.cancelAutomaticAdvance()
        assertNull(transition.resolve(request, entry))
        assertTrue(transition.begin(key, "outro") is NativeEpisodeTransition.Decision.Ready)
    }

    @Test
    fun pauseDoesNotCancelExplicitSelection() {
        val request =
            (transition.begin(key, "episode-picker") as NativeEpisodeTransition.Decision.Resolve)
                .request
        transition.cancelAutomaticAdvance()
        assertEquals("episode-picker", transition.resolve(request, entry)?.reason)
    }

    @Test
    fun failureDuringFirstFrameUnlocksManualCommands() {
        transition.resolve(
            (transition.begin(key, "outro") as NativeEpisodeTransition.Decision.Resolve).request,
            entry,
        )
        transition.awaitFirstFrame()
        transition.onPlaybackFailed()
        assertTrue(
            transition.begin(key.copy(index = 2), "episode-picker")
                is NativeEpisodeTransition.Decision.Resolve
        )
    }
}
