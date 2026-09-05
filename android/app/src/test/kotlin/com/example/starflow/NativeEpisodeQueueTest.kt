package com.example.starflow

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class NativeEpisodeQueueTest {
    private val first =
        NativeEpisodeQueueEntry(
            """{"streamUrl":"https://host/1.mkv","title":"One","headers":{"Authorization":"test"}}""",
            "one",
            "series",
        )
    private val second =
        NativeEpisodeQueueEntry(
            """{"streamUrl":"https://host/2.strm?token=value"}""",
            "two",
            "series",
        )

    @Test
    fun roundTripRetainsTargetsHeadersAndMime() {
        val queue =
            NativeEpisodeQueue(listOf(first, second), 1)
                .withCurrentMediaMimeType(" application/x-mpegURL ")
        val restored = NativeEpisodeQueue.fromJsonString(queue.toJsonString())!!
        assertEquals(queue.currentIndex, restored.currentIndex)
        assertEquals(first.url(), restored.entries[0].url())
        assertEquals(
            "test",
            JSONObject(restored.entries[0].headersJson()).getString("Authorization"),
        )
        assertEquals(second.playbackItemKey, restored.entries[1].playbackItemKey)
        assertEquals(second.seriesKey, restored.entries[1].seriesKey)
        assertEquals(queue.currentEntry()?.mediaMimeType, restored.currentEntry()?.mediaMimeType)
        assertEquals("application/x-mpegURL", queue.currentEntry()?.mediaMimeType)
        assertTrue(queue.hasPrevious())
        assertFalse(queue.hasNext())
        assertEquals(first, queue.moveToPrevious()?.currentEntry())
        assertNull(queue.moveToNext())
    }

    @Test
    fun invalidInputAndIndexClamping() {
        assertNull(NativeEpisodeQueue.fromJsonString("broken"))
        assertNull(NativeEpisodeQueue.fromJsonString("{}"))
        assertNull(NativeEpisodeQueue.fromJsonString("""{"entries":[]}"""))
        assertEquals(
            0,
            NativeEpisodeQueue.fromJsonString("""{"currentIndex":99,"entries":[null,{}]}""")
                ?.currentIndex,
        )
    }

    @Test
    fun resolutionAndImmutableReplacement() {
        assertFalse(first.needsResolution())
        assertTrue(second.needsResolution())
        assertTrue(second.copy(playbackTargetJson = "{}").needsResolution())
        val queue = NativeEpisodeQueue(listOf(first, second))
        assertSame(queue, queue.replaceEntry(9, first))
        assertEquals(second, queue.entries[1])
        assertEquals(first, queue.replaceEntry(1, first).entries[1])
        assertSame(queue, queue.withCurrentMediaMimeType(" "))
    }
}
