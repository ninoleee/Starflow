package com.example.starflow

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NativePlaybackReadAheadPolicyTest {
    private val config = NativePlaybackBufferPolicy.resolve(
        isTelevision = true,
        memoryClassMb = 192,
        isHeavyPlayback = false,
    )

    @Test
    fun targetIsBoundedAndNeverFallsBelowTheConfiguredBase() {
        assertEquals(
            config.targetBufferBytes,
            NativePlaybackBufferBudget.target(
                config.targetBufferBytes, NativePlaybackBufferBudget.limit(192), 0L, 12,
            ),
        )
        assertEquals(
            NativePlaybackBufferBudget.limit(192),
            NativePlaybackBufferBudget.target(
                config.targetBufferBytes, NativePlaybackBufferBudget.limit(192),
                Long.MAX_VALUE, 20,
            ),
        )
    }

    @Test
    fun twoConsecutiveFallingSamplesEnableTemporaryReadAheadBoost() {
        val policy = NativePlaybackReadAheadPolicy(config, NativePlaybackBufferBudget.limit(192), 20_000_000L)
        val normal = policy.evaluate(0L, 0L, 10_000L, 1f, true, true, 100_000L, false)
        val stillNormal = policy.evaluate(1_000L, 1_000L, 9_500L, 1f, true, true, 100_000L, false)
        val boosted = policy.evaluate(2_000L, 2_000L, 8_900L, 1f, true, true, 100_000L, false)

        assertEquals(config.minBufferMs, normal.second)
        assertEquals(config.minBufferMs, stillNormal.second)
        assertTrue(boosted.first > normal.first)
        assertTrue(boosted.second > normal.second)
    }

    @Test
    fun speedChangeAndMemoryPressureClearTheTemporaryBoost() {
        val policy = NativePlaybackReadAheadPolicy(config, NativePlaybackBufferBudget.limit(192), 20_000_000L)
        policy.evaluate(0L, 0L, 10_000L, 1f, true, true, 100_000L, false)
        policy.evaluate(1_000L, 1_000L, 9_500L, 1f, true, true, 100_000L, false)
        policy.evaluate(2_000L, 2_000L, 8_900L, 1f, true, true, 100_000L, false)

        val afterSpeedChange = policy.evaluate(2_100L, 2_100L, 8_800L, 1.25f, true, true, 100_000L, false)
        val afterPressure = policy.evaluate(3_100L, 3_100L, 8_700L, 1f, true, true, 100_000L, true)

        assertEquals(config.minBufferMs, afterSpeedChange.second)
        assertEquals(config.targetBufferBytes, afterPressure.first)
        assertEquals(config.minBufferMs, afterPressure.second)
    }

    @Test
    fun idleUnknownInvalidOrFastSamplesCannotBoost() {
        for ((reading, bytesPerSecond) in listOf(
            false to 0L, true to null, true to -1L, true to 10_000_000L,
        )) {
            val policy = NativePlaybackReadAheadPolicy(config, NativePlaybackBufferBudget.limit(192), 20_000_000L)
            repeat(5) { index ->
                val result = policy.evaluate(index * 1_000L, index * 1_000L,
                    20_000L - index * 1_000L, 1f, true, reading, bytesPerSecond, false)
                assertEquals(config.minBufferMs, result.second)
            }
        }
    }

    @Test
    fun subSecondCallbacksDoNotCountAsIndependentFallingSamples() {
        val policy = NativePlaybackReadAheadPolicy(config, NativePlaybackBufferBudget.limit(192), 20_000_000L)
        repeat(10) { index ->
            val result = policy.evaluate(index * 100L, index * 100L,
                20_000L - index * 300L, 1f, true, true, 0L, false)
            assertEquals(config.minBufferMs, result.second)
        }
    }

    @Test
    fun boostExpiresAtThirtySecondsWithoutFurtherFallingSamples() {
        val policy = NativePlaybackReadAheadPolicy(config, NativePlaybackBufferBudget.limit(192), 20_000_000L)
        repeat(3) { index ->
            policy.evaluate(index * 1_000L, index * 1_000L,
                20_000L - index * 1_000L, 1f, true, true, 0L, false)
        }
        val beforeExpiry = policy.evaluate(31_999, 31_999, 18_000, 1f, true, false, null, false)
        val expired = policy.evaluate(32_000, 32_000, 18_000, 1f, true, false, null, false)
        assertTrue(beforeExpiry.second > config.minBufferMs)
        assertEquals(config.minBufferMs, expired.second)
    }

    @Test
    fun clockRollbackClearsBoostAndAllowsNewSamples() {
        val policy = NativePlaybackReadAheadPolicy(config, NativePlaybackBufferBudget.limit(192), 20_000_000L)
        repeat(3) { index ->
            policy.evaluate(index * 1_000L, index * 1_000L,
                20_000L - index * 1_000L, 1f, true, true, 0L, false)
        }
        assertEquals(config.minBufferMs,
            policy.evaluate(1_000, 2_000, 18_000, 1f, true, true, 0L, false).second)
    }

    @Test
    fun pressureTargetStillHonorsLimitSmallerThanBaseAndMemoryTiersHaveExactBoundaries() {
        for ((memory, limitMb) in listOf(256 to 48, 257 to 80, 512 to 80, 513 to 192)) {
            assertEquals(limitMb * 1024 * 1024, NativePlaybackBufferBudget.limit(memory))
        }
        val policy = NativePlaybackReadAheadPolicy(config, 16 * 1024 * 1024, Long.MAX_VALUE)
        assertEquals(16 * 1024 * 1024,
            policy.evaluate(0, 0, 0, 1f, true, true, 0L, true).first)
    }

    @Test
    fun highMemoryBudgetGrowsFrom128To192MiBAndPressureRestoresBase() {
        val highMemoryConfig = NativePlaybackBufferPolicy.resolve(true, 513, false)
        val limit = NativePlaybackBufferBudget.limit(513)
        val mib = 1024 * 1024
        for (bitrate in listOf(0L, 10_000_000L)) {
            assertEquals(128 * mib, NativePlaybackBufferBudget.target(
                highMemoryConfig.targetBufferBytes, limit, bitrate, 12,
            ))
        }
        assertEquals(192 * mib, NativePlaybackBufferBudget.target(
            highMemoryConfig.targetBufferBytes, limit, Long.MAX_VALUE, 12,
        ))
        val policy = NativePlaybackReadAheadPolicy(highMemoryConfig, limit, 100_000_000L)
        val normal = policy.evaluate(0, 0, 20_000, 1f, true, true, 0L, false)
        assertEquals(150_000_000, normal.first)
        policy.evaluate(1_000, 1_000, 19_000, 1f, true, true, 0L, false)
        val boosted = policy.evaluate(2_000, 2_000, 18_000, 1f, true, true, 0L, false)
        assertEquals(192 * mib, boosted.first)
        val pressure = policy.evaluate(3_000, 3_000, 17_000, 1f, true, true, 0L, true)
        assertEquals(128 * mib, pressure.first)
        assertEquals(highMemoryConfig.minBufferMs, pressure.second)
    }
}
