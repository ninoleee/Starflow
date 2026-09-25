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
        assertEquals(2_000, config.bufferForPlaybackAfterRebufferMs)
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
        assertEquals(2_000, config.bufferForPlaybackAfterRebufferMs)
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
        assertEquals(2_000, config.bufferForPlaybackAfterRebufferMs)
        assertEquals(120_000, config.maxBufferMs)
        assertFalse(config.prioritizeTimeOverSizeThresholds)
    }

    @Test
    fun baseBudgetKeepsLowerTiersAndUses128MiBAbove512ForAllMedia() {
        for ((memory, normalMb, heavyMb) in listOf(
            Triple(256, 32, 48), Triple(257, 64, 80), Triple(512, 64, 80),
            Triple(513, 128, 128), Triple(1024, 128, 128),
        )) {
            for (heavy in listOf(false, true)) {
                for (episodeSwitch in listOf(false, true)) {
                    val config = NativePlaybackBufferPolicy.resolve(
                        isTelevision = true,
                        memoryClassMb = memory,
                        isHeavyPlayback = heavy,
                        isRemoteEpisodeSwitch = episodeSwitch,
                    )
                    val expectedMb = if (heavy || episodeSwitch) heavyMb else normalMb
                    assertEquals(expectedMb * 1024 * 1024, config.targetBufferBytes)
                }
            }
        }
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
        assertEquals(1_500, config.bufferForPlaybackAfterRebufferMs)
        assertEquals("fast", config.bandwidthProfile)
    }

    @Test
    fun constrainedHostBandwidthKeepsRebufferWaitShort() {
        val config = NativePlaybackBufferPolicy.resolve(
            isTelevision = true,
            memoryClassMb = 192,
            isHeavyPlayback = false,
            cachedBandwidthBytesPerSecond = 1_000_000L,
            sourceBitrate = 8_000_000L,
        )

        assertEquals(2_000, config.bufferForPlaybackMs)
        assertEquals(3_000, config.bufferForPlaybackAfterRebufferMs)
        assertEquals("constrained", config.bandwidthProfile)
    }

    @Test
    fun lowMemoryTelevisionKeepsReadAheadWithoutDelayingRemoteEpisodeSwitch() {
        val config = NativePlaybackBufferPolicy.resolve(
            isTelevision = true,
            memoryClassMb = 192,
            isHeavyPlayback = false,
            isRemoteEpisodeSwitch = true,
        )

        assertEquals(30_000, config.minBufferMs)
        assertEquals(1_500, config.bufferForPlaybackMs)
        assertEquals(2_000, config.bufferForPlaybackAfterRebufferMs)
        assertEquals(48 * 1024 * 1024, config.targetBufferBytes)
        assertTrue(config.episodeSwitchWarmup)
    }

    @Test
    fun initialPlaybackKeepsFastStartupPolicy() {
        val config = NativePlaybackBufferPolicy.resolve(
            isTelevision = true,
            memoryClassMb = 192,
            isHeavyPlayback = false,
            isRemoteEpisodeSwitch = false,
        )

        assertEquals(1_500, config.bufferForPlaybackMs)
        assertEquals(2_000, config.bufferForPlaybackAfterRebufferMs)
        assertEquals(32 * 1024 * 1024, config.targetBufferBytes)
        assertFalse(config.episodeSwitchWarmup)
    }

    @Test
    fun cachedFastBandwidthAlsoReducesEpisodeSwitchWait() {
        val config = NativePlaybackBufferPolicy.resolve(
            isTelevision = true,
            memoryClassMb = 192,
            isHeavyPlayback = false,
            cachedBandwidthBytesPerSecond = 5_000_000L,
            sourceBitrate = 10_000_000L,
            isRemoteEpisodeSwitch = true,
        )

        assertEquals("fast", config.bandwidthProfile)
        assertEquals(1_200, config.bufferForPlaybackMs)
        assertEquals(1_500, config.bufferForPlaybackAfterRebufferMs)
        assertEquals(48 * 1024 * 1024, config.targetBufferBytes)
        assertTrue(config.episodeSwitchWarmup)
    }

    @Test
    fun televisionResumeThresholdDoesNotGrowWithMemoryOrEpisodeSwitch() {
        for (memoryClassMb in listOf(192, 256, 257, 512, 513, 1024)) {
            for (isHeavyPlayback in listOf(false, true)) {
                for ((bandwidth, expectedResumeMs) in listOf(
                    0L to 2_000,
                    1_000_000L to 3_000,
                    2_000_000L to 2_000,
                    5_000_000L to 1_500,
                )) {
                    val initial = NativePlaybackBufferPolicy.resolve(
                        isTelevision = true,
                        memoryClassMb = memoryClassMb,
                        isHeavyPlayback = isHeavyPlayback,
                        cachedBandwidthBytesPerSecond = bandwidth,
                        sourceBitrate = 10_000_000L,
                    )
                    val switched = NativePlaybackBufferPolicy.resolve(
                        isTelevision = true,
                        memoryClassMb = memoryClassMb,
                        isHeavyPlayback = isHeavyPlayback,
                        cachedBandwidthBytesPerSecond = bandwidth,
                        sourceBitrate = 10_000_000L,
                        isRemoteEpisodeSwitch = true,
                    )

                    assertEquals(expectedResumeMs, initial.bufferForPlaybackAfterRebufferMs)
                    assertEquals(expectedResumeMs, switched.bufferForPlaybackAfterRebufferMs)
                    assertEquals(initial.bufferForPlaybackMs, switched.bufferForPlaybackMs)
                    assertEquals(initial.maxBufferMs, switched.maxBufferMs)
                    assertTrue(switched.targetBufferBytes >= initial.targetBufferBytes)
                    assertFalse(switched.prioritizeTimeOverSizeThresholds)
                }
            }
        }
    }

    @Test
    fun missingBitrateDoesNotTurnCachedBandwidthIntoALongerWait() {
        val config = NativePlaybackBufferPolicy.resolve(
            isTelevision = true,
            memoryClassMb = 192,
            isHeavyPlayback = false,
            cachedBandwidthBytesPerSecond = 1_000_000L,
            isRemoteEpisodeSwitch = true,
        )

        assertEquals("unknown", config.bandwidthProfile)
        assertEquals(1_500, config.bufferForPlaybackMs)
        assertEquals(2_000, config.bufferForPlaybackAfterRebufferMs)
    }

    @Test
    fun phoneThresholdsRemainUnchangedIncludingRemoteEpisodeSwitch() {
        for (isRemoteEpisodeSwitch in listOf(false, true)) {
            for ((bandwidth, startMs, resumeMs) in listOf(
                Triple(0L, 2_500, 5_000),
                Triple(1_000_000L, 3_000, 7_000),
                Triple(2_000_000L, 2_500, 5_000),
                Triple(5_000_000L, 1_200, 3_500),
            )) {
                val config = NativePlaybackBufferPolicy.resolve(
                    isTelevision = false,
                    memoryClassMb = 192,
                    isHeavyPlayback = false,
                    cachedBandwidthBytesPerSecond = bandwidth,
                    sourceBitrate = 10_000_000L,
                    isRemoteEpisodeSwitch = isRemoteEpisodeSwitch,
                )

                assertEquals(startMs, config.bufferForPlaybackMs)
                assertEquals(resumeMs, config.bufferForPlaybackAfterRebufferMs)
                assertEquals(50_000, config.minBufferMs)
                assertEquals(90_000, config.maxBufferMs)
                assertEquals(-1, config.targetBufferBytes)
                assertTrue(config.prioritizeTimeOverSizeThresholds)
                assertFalse(config.episodeSwitchWarmup)
            }
        }
    }
}
