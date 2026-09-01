package com.example.starflow

import androidx.media3.common.C
import org.junit.Assert.assertEquals
import org.junit.Test

class NativePlaybackLoadErrorPolicyTest {
    @Test
    fun `classifies permanent and transient HTTP statuses`() {
        assertEquals(
            NativeLoadFailureKind.PERMANENT,
            NativePlaybackLoadErrorClassifier.classifyHttpStatus(404),
        )
        assertEquals(
            NativeLoadFailureKind.TRANSIENT,
            NativePlaybackLoadErrorClassifier.classifyHttpStatus(429),
        )
        assertEquals(
            NativeLoadFailureKind.TRANSIENT,
            NativePlaybackLoadErrorClassifier.classifyHttpStatus(503),
        )
        assertEquals(
            NativeLoadFailureKind.UNKNOWN,
            NativePlaybackLoadErrorClassifier.classifyHttpStatus(418),
        )
    }

    @Test
    fun `backs off transient failures and stops after bounded retries`() {
        assertEquals(500L, NativePlaybackLoadErrorClassifier.retryDelayMs(1))
        assertEquals(1_000L, NativePlaybackLoadErrorClassifier.retryDelayMs(2))
        assertEquals(8_000L, NativePlaybackLoadErrorClassifier.retryDelayMs(6))
        assertEquals(C.TIME_UNSET, NativePlaybackLoadErrorClassifier.retryDelayMs(7))
    }
}
