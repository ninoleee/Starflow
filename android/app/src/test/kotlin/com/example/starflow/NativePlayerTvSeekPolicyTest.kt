package com.example.starflow

import org.junit.Assert.assertEquals
import org.junit.Test

class NativePlayerTvSeekPolicyTest {
    private var time = 100_000L
    private val policy = NativePlayerTvSeekPolicy { time }

    @Test
    fun durationThresholds() {
        assertEquals(10_000L, policy.stepMs(1, 0))
        time += 1_499L
        assertEquals(10_000L, policy.stepMs(1, 0))
        time += 1L
        assertEquals(30_000L, policy.stepMs(1, 0))
        time += 1_500L
        assertEquals(60_000L, policy.stepMs(1, 0))
        time += 2_000L
        assertEquals(120_000L, policy.stepMs(1, 0))
    }

    @Test
    fun repeatThresholdsNeverRegress() {
        assertEquals(10_000L, policy.stepMs(1, 12))
        assertEquals(10_000L, policy.stepMs(1, 2))
        assertEquals(30_000L, policy.stepMs(1, 3))
        assertEquals(60_000L, policy.stepMs(1, 7))
        assertEquals(60_000L, policy.stepMs(1, 0))
        assertEquals(120_000L, policy.stepMs(1, 12))
    }

    @Test
    fun directionChangeStartsNewHold() {
        policy.stepMs(1, 0)
        time += 10_000L
        assertEquals(120_000L, policy.stepMs(1, 20))
        assertEquals(10_000L, policy.stepMs(2, 20))
    }

    @Test
    fun unrelatedKeyReleaseDoesNotResetHold() {
        policy.stepMs(1, 0)
        time += 5_000L
        policy.reset(2)
        assertEquals(120_000L, policy.stepMs(1, 0))
        policy.reset(1)
        assertEquals(10_000L, policy.stepMs(1, 0))
        time += 5_000L
        policy.reset()
        assertEquals(10_000L, policy.stepMs(1, 0))
    }
}
