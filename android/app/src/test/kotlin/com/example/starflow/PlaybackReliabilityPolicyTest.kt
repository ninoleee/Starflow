package com.example.starflow

import org.junit.Assert.*
import org.junit.Test

class PlaybackReliabilityPolicyTest {
    @Test fun statePrecedenceAndLoading() {
        for (mask in 0 until 64) {
            val phase = PlaybackReliabilityPolicy.phase(
                ready = mask and 1 != 0,
                playing = mask and 2 != 0,
                buffering = mask and 4 != 0,
                recovering = mask and 8 != 0,
                ended = mask and 16 != 0,
                failed = mask and 32 != 0,
            )
            val expected = when {
                mask and 32 != 0 -> PlaybackPhase.failed
                mask and 16 != 0 -> PlaybackPhase.ended
                mask and 8 != 0 -> PlaybackPhase.recovering
                mask and 1 == 0 -> PlaybackPhase.preparing
                mask and 4 != 0 -> PlaybackPhase.buffering
                mask and 2 != 0 -> PlaybackPhase.playing
                else -> PlaybackPhase.paused
            }
            assertEquals(expected, phase)
            assertEquals(phase in listOf(PlaybackPhase.preparing, PlaybackPhase.buffering, PlaybackPhase.recovering), phase.showsLoading)
        }
    }

    @Test fun progressAccumulatesWithoutOscillation() {
        val progress = PlaybackBufferProgress()
        assertFalse(progress.observe(500L, 0))
        assertTrue(progress.observe(1_000L, 1))
        assertFalse(progress.observe(0L, 0))
        assertFalse(progress.observe(1_000L, 1))
        progress.reset()
        assertTrue(progress.observe(1_000L, 1))
    }

    @Test fun rebuildBudgetOnlyResetsExplicitly() {
        val budget = PlaybackRecoveryBudget()
        assertTrue(budget.take())
        assertTrue(budget.take())
        assertFalse(budget.take())
        assertEquals(2, budget.attempts)
        budget.reset()
        assertTrue(budget.take())
    }

    @Test fun refreshOnlyForExpiredPreparedAddresses() {
        for (code in listOf(401, 403, 404, 410)) {
            assertTrue(PlaybackReliabilityPolicy.isAddressRefreshable(code))
            assertEquals(NativeLoadFailureKind.PERMANENT, PlaybackReliabilityPolicy.classifyHttpStatus(code))
        }
        for (code in listOf(408, 425, 429, 500, 503, 599)) {
            assertFalse(PlaybackReliabilityPolicy.isAddressRefreshable(code))
            assertEquals(NativeLoadFailureKind.TRANSIENT, PlaybackReliabilityPolicy.classifyHttpStatus(code))
        }
    }
}
