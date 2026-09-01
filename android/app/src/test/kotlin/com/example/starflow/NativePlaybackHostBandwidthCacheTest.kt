package com.example.starflow

import org.junit.Assert.assertEquals
import org.junit.Test

class NativePlaybackHostBandwidthCacheTest {
    @Test
    fun `reuses recent bandwidth for the same host and expires it`() {
        var now = 1_000L
        val cache = NativePlaybackHostBandwidthCache(
            ttlMs = 10_000L,
            clock = { now },
        )

        cache.record("MEDIA.EXAMPLE.COM", 2_500_000L)
        assertEquals(2_500_000L, cache.resolve("media.example.com"))
        now += 10_001L
        assertEquals(0L, cache.resolve("media.example.com"))
    }
}
