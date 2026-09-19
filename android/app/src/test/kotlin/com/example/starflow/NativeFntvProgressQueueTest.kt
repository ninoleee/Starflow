package com.example.starflow

import org.junit.Assert.*
import org.junit.Test

class NativeFntvProgressQueueTest {
    @Test
    fun coalescesPendingProgressWithoutDroppingTheFinalSave() {
        val sent = mutableListOf<Map<String, Any?>>()
        val callbacks = mutableListOf<() -> Unit>()
        val queue = NativeFntvProgressQueue { value, done ->
            sent += value
            callbacks += done
        }
        queue.enqueue("a", mapOf("position" to 10))
        queue.enqueue("a", mapOf("position" to 20))
        queue.enqueue("a", mapOf("position" to 30))
        var closed = false
        queue.finish { closed = true }
        assertEquals(listOf(10), sent.map { it["position"] })
        assertFalse(closed)
        callbacks.removeAt(0)()
        assertEquals(listOf(10, 30), sent.map { it["position"] })
        assertFalse(closed)
        callbacks.removeAt(0)()
        assertTrue(closed)
    }

    @Test
    fun keepsFinalProgressForOldEpisodeAheadOfNewEpisode() {
        val sent = mutableListOf<Map<String, Any?>>()
        val callbacks = mutableListOf<() -> Unit>()
        val queue = NativeFntvProgressQueue { value, done ->
            sent += value
            callbacks += done
        }
        queue.enqueue("a", mapOf("position" to 10))
        queue.enqueue("a", mapOf("position" to 100))
        queue.enqueue("b", mapOf("position" to 0))
        callbacks.removeAt(0)()
        callbacks.removeAt(0)()
        assertEquals(listOf(10, 100, 0), sent.map { it["position"] })
    }

    @Test
    fun idleQueueClosesImmediately() {
        var closed = false
        NativeFntvProgressQueue { _, done -> done() }.finish { closed = true }
        assertTrue(closed)
    }
}
