package com.example.starflow

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativePlaybackBufferPolicyTest {
    @Test
    fun manualCapacityIsBoundedAndSurvivesEpisodeAndBandwidthOverrides() {
        for (tv in listOf(false, true)) {
            for (switch in listOf(false, true)) {
                for ((memory, cap) in listOf(256 to 64, 512 to 128, 1024 to 256)) {
                    for (requested in listOf(64, 128, 256, 512)) {
                        val config = NativePlaybackBufferPolicy.resolve(tv, memory, true,
                            cachedBandwidthBytesPerSecond = 50_000_000,
                            sourceBitrate = 160_000_000,
                            isRemoteEpisodeSwitch = switch, memoryCacheMiB = requested)
                        assertEquals(minOf(requested, cap) * 1024 * 1024, config.targetBufferBytes)
                        assertEquals(120_000, config.maxBufferMs)
                        assertFalse(config.prioritizeTimeOverSizeThresholds)
                    }
                }
            }
        }
        assertEquals(0, NativePlaybackBufferPolicy.manualTargetBytes(-1, 1024))
        assertEquals(0, NativePlaybackBufferPolicy.manualTargetBytes(1024, 1024))
    }

    @Test
    fun lowMemoryTelevisionUsesSmallBoundedBuffer() {
        val config = NativePlaybackBufferPolicy.resolve(
            isTelevision = true,
            memoryClassMb = 192,
            isHeavyPlayback = false,
        )

        assertEquals(20_000, config.minBufferMs)
        assertEquals(120_000, config.maxBufferMs)
        assertEquals(1_500, config.bufferForPlaybackMs)
        assertEquals(2_000, config.bufferForPlaybackAfterRebufferMs)
        assertEquals(64 * 1024 * 1024, config.targetBufferBytes)
        assertFalse(config.prioritizeTimeOverSizeThresholds)
    }

    @Test
    fun mediumMemoryHeavyPlaybackUsesTheRaisedBudget() {
        val config = NativePlaybackBufferPolicy.resolve(
            isTelevision = true,
            memoryClassMb = 512,
            isHeavyPlayback = true,
        )

        assertEquals(112 * 1024 * 1024, config.targetBufferBytes)
        assertEquals(2_000, config.bufferForPlaybackMs)
        assertEquals(2_000, config.bufferForPlaybackAfterRebufferMs)
        assertFalse(config.prioritizeTimeOverSizeThresholds)
    }

    @Test
    fun highMemoryTelevisionUsesRaisedBoundedBuffer() {
        val config = NativePlaybackBufferPolicy.resolve(
            isTelevision = true,
            memoryClassMb = 1024,
            isHeavyPlayback = true,
        )

        assertEquals(160 * 1024 * 1024, config.targetBufferBytes)
        assertEquals(2_500, config.bufferForPlaybackMs)
        assertEquals(2_000, config.bufferForPlaybackAfterRebufferMs)
        assertEquals(120_000, config.maxBufferMs)
        assertFalse(config.prioritizeTimeOverSizeThresholds)
    }

    @Test
    fun baseBudgetKeepsLowerTiersAndUses160MiBAbove512ForAllMedia() {
        for ((memory, normalMb, heavyMb) in listOf(
            Triple(256, 64, 64), Triple(257, 96, 112), Triple(512, 96, 112),
            Triple(513, 160, 160), Triple(1024, 160, 160),
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
                    assertEquals(120_000, config.maxBufferMs)
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
        assertEquals(64 * 1024 * 1024, config.targetBufferBytes)
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
        assertEquals(64 * 1024 * 1024, config.targetBufferBytes)
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
        assertEquals(64 * 1024 * 1024, config.targetBufferBytes)
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
                assertEquals(120_000, config.maxBufferMs)
                assertEquals(-1, config.targetBufferBytes)
                assertTrue(config.prioritizeTimeOverSizeThresholds)
                assertFalse(config.episodeSwitchWarmup)
            }
        }
    }
}
