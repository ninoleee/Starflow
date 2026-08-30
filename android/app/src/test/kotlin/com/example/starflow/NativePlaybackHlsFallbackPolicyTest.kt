package com.example.starflow

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativePlaybackHlsFallbackPolicyTest {
    @Test
    fun `retries smartstrm container parse failures as hls`() {
        assertTrue(
            NativePlaybackHlsFallbackPolicy.shouldRetryAsHls(
                errorCode = 3003,
                url = "https://smartstrm.example.com/smartstrm/my/movie.mp4",
                alreadyAttempted = false,
            ),
        )
    }

    @Test
    fun `does not retry normal mp4 urls as hls`() {
        assertFalse(
            NativePlaybackHlsFallbackPolicy.shouldRetryAsHls(
                errorCode = 3003,
                url = "https://media.example.com/movie.mp4",
                alreadyAttempted = false,
            ),
        )
    }

    @Test
    fun `does not repeat hls fallback`() {
        assertFalse(
            NativePlaybackHlsFallbackPolicy.shouldRetryAsHls(
                errorCode = 3003,
                url = "https://smartstrm.example.com/smartstrm/my/movie.mp4",
                alreadyAttempted = true,
            ),
        )
    }

    @Test
    fun `does not retry unrelated playback errors`() {
        assertFalse(
            NativePlaybackHlsFallbackPolicy.shouldRetryAsHls(
                errorCode = 2001,
                url = "https://smartstrm.example.com/smartstrm/my/movie.mp4",
                alreadyAttempted = false,
            ),
        )
    }
}
