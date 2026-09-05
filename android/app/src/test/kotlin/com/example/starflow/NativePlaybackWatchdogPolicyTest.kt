package com.example.starflow

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativePlaybackWatchdogPolicyTest {
    private var timeMs = 100_000L
    private val policy = NativePlaybackWatchdogPolicy { timeMs }.apply { reset(0L, 0L, 0) }

    private fun stalled(
        position: Long = 0L,
        buffered: Long = 0L,
        percentage: Int = 0,
        buffering: Boolean = false,
        playing: Boolean = true,
    ) = policy.isStalled(position, buffered, percentage, buffering, playing)

    @Test
    fun playbackTimeoutIncludesBoundary() {
        timeMs += 14_999L
        assertFalse(stalled())
        timeMs += 1L
        assertTrue(stalled())
        assertFalse(stalled(playing = false))
    }

    @Test
    fun bufferingTimeoutIncludesBoundary() {
        timeMs += 44_999L
        assertFalse(stalled(buffering = true, playing = false))
        timeMs += 1L
        assertTrue(stalled(buffering = true, playing = false))
    }

    @Test
    fun bufferGrowthDefersBufferingTimeout() {
        timeMs += 44_000L
        assertFalse(stalled(buffered = 1_001L, buffering = true, playing = false))
        timeMs += 44_000L
        assertFalse(stalled(buffered = 1_001L, percentage = 1, buffering = true, playing = false))
        timeMs += 45_000L
        assertTrue(stalled(buffered = 1_001L, percentage = 1, buffering = true, playing = false))
    }

    @Test
    fun exactBufferAdvanceThresholdDoesNotResetTimer() {
        timeMs += 45_000L
        assertTrue(stalled(buffered = 1_000L, buffering = true, playing = false))
    }

    @Test
    fun bufferGrowthDoesNotHidePlaybackStall() {
        timeMs += 15_000L
        assertTrue(stalled(buffered = 5_000L))
    }

    @Test
    fun forwardProgressAndBackwardSeekResetTimeout() {
        timeMs += 15_000L
        assertTrue(stalled(position = 500L))
        assertFalse(stalled(position = 501L))
        policy.reset(5_000L, 5_000L, 0)
        timeMs += 15_000L
        assertTrue(stalled(position = 4_000L))
        assertFalse(stalled(position = 3_999L))
    }

    @Test
    fun twoSoftRecoveriesThenRestartWithCooldown() {
        assertEquals(NativePlaybackWatchdogPolicy.Recovery.SOFT, policy.recovery { false })
        timeMs += 9_999L
        assertEquals(
            NativePlaybackWatchdogPolicy.Recovery.NONE,
            policy.recovery { error("Bandwidth must not be checked during cooldown") },
        )
        timeMs += 1L
        assertEquals(NativePlaybackWatchdogPolicy.Recovery.SOFT, policy.recovery { false })
        timeMs += 10_000L
        assertEquals(NativePlaybackWatchdogPolicy.Recovery.RESTART, policy.recovery { false })
    }

    @Test
    fun lowBandwidthDefersBothTimersWithoutConsumingRecovery() {
        repeat(3) {
            timeMs += 45_000L
            assertEquals(
                NativePlaybackWatchdogPolicy.Recovery.WAIT_FOR_BANDWIDTH,
                policy.recovery { true },
            )
            assertFalse(stalled())
            assertFalse(stalled(buffering = true, playing = false))
        }
        timeMs += 10_000L
        assertEquals(NativePlaybackWatchdogPolicy.Recovery.SOFT, policy.recovery { false })
    }

    @Test
    fun progressClearsRecoveryBudgetAndCooldown() {
        policy.recovery { false }
        timeMs += 10_000L
        policy.recovery { false }
        assertFalse(stalled(position = 501L))
        assertEquals(NativePlaybackWatchdogPolicy.Recovery.SOFT, policy.recovery { false })
    }

    @Test
    fun activityRefreshPreservesBudgetWhileResetClearsIt() {
        policy.recovery { false }
        timeMs += 10_000L
        policy.recovery { false }
        policy.markActivity(0L, 0L, 0)
        timeMs += 10_000L
        assertEquals(NativePlaybackWatchdogPolicy.Recovery.RESTART, policy.recovery { false })
        policy.reset(0L, 0L, 0)
        assertEquals(NativePlaybackWatchdogPolicy.Recovery.SOFT, policy.recovery { false })
    }

    @Test
    fun softRecoveryAcknowledgementPreservesSynchronousReset() {
        val startedAtMs = timeMs
        policy.recovery { false }
        timeMs += 1L
        policy.reset(0L, 0L, 0)
        policy.onSoftRecoveryCompleted(startedAtMs)
        timeMs = startedAtMs + 15_000L
        assertTrue(stalled())
        assertEquals(NativePlaybackWatchdogPolicy.Recovery.SOFT, policy.recovery { false })
    }

    @Test
    fun stopClearsRecoveryBudget() {
        policy.recovery { false }
        timeMs += 10_000L
        policy.recovery { false }
        policy.clearRecoveries()
        assertEquals(NativePlaybackWatchdogPolicy.Recovery.SOFT, policy.recovery { false })
    }
}
