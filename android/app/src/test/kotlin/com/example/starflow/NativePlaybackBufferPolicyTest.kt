package com.example.starflow

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativePlaybackBufferPolicyTest {
    @Test
    fun lowMemoryTelevisionUsesSmallBoundedBuffer() {
        val config = NativePlaybackBufferPolicy.resolve(
            isTelevision = true,
            memoryClassMb = 192,
            isHeavyPlayback = false,
        )

        assertEquals(20_000, config.minBufferMs)
        assertEquals(60_000, config.maxBufferMs)
        assertEquals(32 * 1024 * 1024, config.targetBufferBytes)
        assertFalse(config.prioritizeTimeOverSizeThresholds)
    }

    @Test
    fun heavyPlaybackGetsMoreRoomWithoutReturningToOld160MiBLimit() {
        val config = NativePlaybackBufferPolicy.resolve(
            isTelevision = true,
            memoryClassMb = 512,
            isHeavyPlayback = true,
        )

        assertEquals(80 * 1024 * 1024, config.targetBufferBytes)
        assertEquals(6_000, config.bufferForPlaybackAfterRebufferMs)
        assertFalse(config.prioritizeTimeOverSizeThresholds)
    }

    @Test
    fun highMemoryTelevisionStillHasBoundedBuffer() {
        val config = NativePlaybackBufferPolicy.resolve(
            isTelevision = true,
            memoryClassMb = 1024,
            isHeavyPlayback = true,
        )

        assertEquals(128 * 1024 * 1024, config.targetBufferBytes)
        assertEquals(120_000, config.maxBufferMs)
        assertFalse(config.prioritizeTimeOverSizeThresholds)
    }

    @Test
    fun phoneKeepsTimePrioritizedDefault() {
        val config = NativePlaybackBufferPolicy.resolve(
            isTelevision = false,
            memoryClassMb = 128,
            isHeavyPlayback = true,
        )

        assertEquals(-1, config.targetBufferBytes)
        assertTrue(config.prioritizeTimeOverSizeThresholds)
    }
}
