package com.example.starflow

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeEpisodeResolutionRequestTest {
    private val first = NativeEpisodeQueueEntry("first", "one", "series")
    private val second = NativeEpisodeQueueEntry("second", "two", "series")
    private val queue = NativeEpisodeQueue(listOf(first, second))
    private val request = NativeEpisodeResolutionRequest(1L, 0, "first", 1, "second")

    @Test
    fun acceptsUnchangedPlayback() {
        assertTrue(request.matchesPlayback(queue, "first"))
    }

    @Test
    fun rejectsReplacedPlaybackOrQueue() {
        assertFalse(request.matchesPlayback(queue, "replacement"))
        assertFalse(request.matchesPlayback(queue.copy(currentIndex = 1), "first"))
        assertFalse(request.matchesPlayback(null, "first"))
    }

    @Test
    fun rejectsRemovedOrReplacedDestination() {
        assertFalse(request.matchesPlayback(queue.copy(entries = listOf(first)), "first"))
        assertFalse(request.matchesPlayback(queue.replaceEntry(1, first), "first"))
    }
}
