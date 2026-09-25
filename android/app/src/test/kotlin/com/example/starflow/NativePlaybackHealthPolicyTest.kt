package com.example.starflow

import org.junit.Assert.*
import org.junit.Test

class NativePlaybackHealthPolicyTest {
    @Test fun diagnosesSignalsWithoutClaimingNetworkOrDecoderRootCause() {
        assertEquals("buffer-available-check-decode-output",
            NativePlaybackHealthPolicy.classify(5_000, true, true))
        assertEquals("buffer-low-reading", NativePlaybackHealthPolicy.classify(0, true, true))
        assertEquals("buffer-low-not-reading", NativePlaybackHealthPolicy.classify(0, false, true))
        assertEquals("output-event", NativePlaybackHealthPolicy.classify(2_000, false, false))
    }

    @Test fun limitsEachEventSeparatelyAndResetsForANewSession() {
        val policy = NativePlaybackHealthPolicy()
        assertTrue(policy.admit("buffering", 0))
        assertFalse(policy.admit("buffering", 9_999))
        assertTrue(policy.admit("dropped-frames", 9_999))
        assertTrue(policy.admit("buffering", 10_000))
        policy.reset()
        assertTrue(policy.admit("buffering", 10_001))
    }
}
