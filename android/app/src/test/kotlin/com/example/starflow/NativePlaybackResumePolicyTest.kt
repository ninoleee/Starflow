package com.example.starflow

import org.junit.Assert.assertEquals
import org.junit.Test

class NativePlaybackResumePolicyTest {
    @Test
    fun `from start ignores stored resume position`() {
        assertEquals(
            0L,
            NativePlaybackResumePolicy.resolveResumePositionMs(
                allowResume = false,
                pendingOverrideMs = null,
                storedResumeMs = 720_000L,
            ),
        )
    }

    @Test
    fun `continue uses stored resume position`() {
        assertEquals(
            720_000L,
            NativePlaybackResumePolicy.resolveResumePositionMs(
                allowResume = true,
                pendingOverrideMs = null,
                storedResumeMs = 720_000L,
            ),
        )
    }

    @Test
    fun `runtime override wins for player rebuilds`() {
        assertEquals(
            125_000L,
            NativePlaybackResumePolicy.resolveResumePositionMs(
                allowResume = false,
                pendingOverrideMs = 125_000L,
                storedResumeMs = 720_000L,
            ),
        )
    }
}
