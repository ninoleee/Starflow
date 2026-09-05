package com.example.starflow

import org.junit.Assert.*
import org.junit.Test

class NativePlaybackStartPolicyTest {
    private fun start(
        allowResume: Boolean = true,
        overrideMs: Long? = null,
        stored: Long = 0L,
        automatic: Boolean = false,
        enabled: Boolean = true,
        intro: Long = 90_000L,
    ) =
        NativePlaybackStartPolicy.resolve(
            allowResume,
            overrideMs,
            stored,
            automatic,
            enabled,
            intro,
        )

    @Test
    fun automaticNextIgnoresOldHistoryAndStartsAtIntro() {
        assertEquals(
            NativePlaybackStartPosition(90_000L, introPositionMs = 90_000L),
            start(stored = 600_000L, automatic = true),
        )
        assertEquals(90_000L, start(allowResume = false, automatic = true).positionMs)
    }

    @Test
    fun explicitFromStartIgnoresHistoryAndIntro() {
        assertEquals(NativePlaybackStartPosition(0L), start(allowResume = false, stored = 600_000L))
    }

    @Test
    fun continuePreservesPositionEvenInsideIntro() {
        assertEquals(NativePlaybackStartPosition(10_000L, isResume = true), start(stored = 10_000L))
    }

    @Test
    fun runtimeOverrideIncludingZeroAlwaysWins() {
        assertEquals(
            NativePlaybackStartPosition(0L),
            start(overrideMs = 0L, stored = 500_000L, automatic = true),
        )
        assertEquals(
            NativePlaybackStartPosition(1_000L),
            start(overrideMs = 1_000L, allowResume = false),
        )
    }

    @Test
    fun noHistoryStartsAtIntroAndDisabledSkipStartsAtZero() {
        assertEquals(90_000L, start().positionMs)
        assertEquals(0L, start(enabled = false, automatic = true).positionMs)
        assertEquals(0L, start(intro = -1L).positionMs)
        assertEquals(3_000L, start(intro = 3_000L).positionMs)
    }

    @Test
    fun preparationWindowUsesOutroOrNaturalEndAndExcludesBoundary() {
        val boundary = NativePlaybackSkipPolicy.endBoundaryMs(100_000L, true, 10_000L)
        assertEquals(90_000L, boundary)
        assertFalse(NativePlaybackSkipPolicy.shouldPrepareNext(59_999L, boundary))
        assertTrue(NativePlaybackSkipPolicy.shouldPrepareNext(60_000L, boundary))
        assertFalse(NativePlaybackSkipPolicy.shouldPrepareNext(90_000L, boundary))
        assertEquals(100_000L, NativePlaybackSkipPolicy.endBoundaryMs(100_000L, false, 10_000L))
        assertEquals(100_000L, NativePlaybackSkipPolicy.endBoundaryMs(100_000L, true, 100_000L))
        assertFalse(NativePlaybackSkipPolicy.shouldPrepareNext(0L, 0L))
    }
}
