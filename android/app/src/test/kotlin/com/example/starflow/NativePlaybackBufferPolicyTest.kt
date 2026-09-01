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
        assertEquals(1_500, config.bufferForPlaybackMs)
        assertEquals(4_000, config.bufferForPlaybackAfterRebufferMs)
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
        assertEquals(2_000, config.bufferForPlaybackMs)
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
        assertEquals(2_500, config.bufferForPlaybackMs)
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

    @Test
    fun cachedFastHostBandwidthReducesStartupBufferWait() {
        val config = NativePlaybackBufferPolicy.resolve(
            isTelevision = true,
            memoryClassMb = 192,
            isHeavyPlayback = true,
            cachedBandwidthBytesPerSecond = 5_000_000L,
            sourceBitrate = 10_000_000L,
        )

        assertEquals(1_200, config.bufferForPlaybackMs)
        assertEquals(3_500, config.bufferForPlaybackAfterRebufferMs)
        assertEquals("fast", config.bandwidthProfile)
    }

    @Test
    fun constrainedHostBandwidthRaisesRebufferThreshold() {
        val config = NativePlaybackBufferPolicy.resolve(
            isTelevision = true,
            memoryClassMb = 192,
            isHeavyPlayback = false,
            cachedBandwidthBytesPerSecond = 1_000_000L,
            sourceBitrate = 8_000_000L,
        )

        assertEquals(2_000, config.bufferForPlaybackMs)
        assertEquals(6_000, config.bufferForPlaybackAfterRebufferMs)
        assertEquals("constrained", config.bandwidthProfile)
    }
}
