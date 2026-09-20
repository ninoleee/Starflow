package com.example.starflow

import org.junit.Assert.*
import org.junit.Test

class LiveTvPolicyTest {
    @Test
    fun `audio selection requires current native token and caller generation`() {
        val session = LiveTvSessionPolicy()
        val first = session.open(7)
        assertTrue(session.acceptsAudio(7, first))
        val second = session.open(7)
        assertFalse(session.acceptsAudio(7, first))
        assertFalse(session.acceptsAudio(6, second))
        assertTrue(session.acceptsAudio(7, second))
        session.invalidate()
        assertFalse(session.acceptsAudio(7, second))
    }

    @Test
    fun `pause reason and transient suppression are bridged separately`() {
        assertEquals("paused:3", LiveTvPausePolicy.state(false, 0, 3))
        assertEquals("paused:2", LiveTvPausePolicy.state(false, 0, 2))
        assertEquals("suppressed:1", LiveTvPausePolicy.state(true, 1, 2))
        assertEquals("resumed", LiveTvPausePolicy.state(true, 0, 2))
    }
    @Test
    fun `reused caller generation cannot revive old callbacks`() {
        val session = LiveTvSessionPolicy()
        val old = session.open(7)
        val current = session.open(7)
        assertFalse(session.event(old, "error"))
        assertFalse(session.progress(old, 2000, true))
        assertTrue(session.event(current, "frame"))
        session.invalidate()
        assertFalse(session.event(current, "ready"))
    }

    @Test
    fun `terminal callback is delivered once and suppresses all later telemetry`() {
        for (terminal in listOf("error", "ended")) {
            val session = LiveTvSessionPolicy()
            val token = session.open(1L shl 40)
            assertEquals(1L shl 40, session.generation)
            assertTrue(session.event(token, terminal))
            for (state in listOf("error", "ended", "ready", "buffering", "frame")) {
                assertFalse(session.event(token, state))
            }
            assertFalse(session.progress(token, 3000, true))
            assertTrue(session.event(session.open(8), "ready"))
        }
    }

    @Test
    fun `progress requires two advancing playing samples`() {
        val session = LiveTvSessionPolicy()
        val token = session.open(1)
        assertFalse(session.progress(token, 3000, true))
        assertFalse(session.progress(token, 3000, true))
        assertTrue(session.progress(token, 4000, true))
        assertFalse(session.progress(token, 5000, false))
        assertFalse(session.progress(token, 6000, true))
        assertTrue(session.progress(token, 7000, true))
    }

    @Test
    fun `timeline resets and seeks do not fabricate progress`() {
        val session = LiveTvSessionPolicy()
        val token = session.open(1)
        session.progress(token, 6000, true)
        session.resetProgress()
        assertFalse(session.progress(token, 20000, true))
        assertFalse(session.progress(token, 0, true))
        assertTrue(session.progress(token, 1000, true))
        assertFalse(session.progress(token, -1, true))
        assertFalse(session.progress(token, 1000, true))
    }

    @Test
    fun `video scales letterbox pillarbox and anamorphic inputs`() {
        val (pillarX, pillarY) = LiveTvVideoPolicy.scale(1920, 1080, 4f / 3f)
        assertEquals(0.75f, pillarX, 0.0001f)
        assertEquals(1f, pillarY, 0.0001f)
        val (letterX, letterY) = LiveTvVideoPolicy.scale(1080, 1920, 16f / 9f)
        assertEquals(1f, letterX, 0.0001f)
        assertEquals(0.31640625f, letterY, 0.0001f)
        assertEquals(16f / 9f, LiveTvVideoPolicy.ratio(720, 576, 64f / 45f)!!, 0.0001f)
    }

    @Test
    fun `invalid video metadata and unmeasured texture keep finite transform`() {
        for (ratio in listOf(0f, -1f, Float.NaN, Float.POSITIVE_INFINITY)) {
            assertNull(LiveTvVideoPolicy.ratio(720, 576, ratio))
            assertEquals(1f to 1f, LiveTvVideoPolicy.scale(1920, 1080, ratio))
        }
        assertNull(LiveTvVideoPolicy.ratio(0, 576, 1f))
        assertNull(LiveTvVideoPolicy.ratio(720, 0, 1f))
        assertEquals(1f to 1f, LiveTvVideoPolicy.scale(0, 0, 1f))
    }

    @Test
    fun `credentials and arbitrary custom headers are restricted to exact origin`() {
        val headers = mapOf("Authorization" to "secret", "Cookie" to "session=secret", "X-Token" to "secret", "Referer" to "https://source.test/private", "User-Agent" to "Provider")
        val policy = LiveTvHttpPolicy("https://source.test/master", headers)
        for (path in listOf("variant", "key", "segment.ts")) {
            assertEquals(5, policy.requestHeaders("HTTPS://SOURCE.TEST:443/$path").size)
            assertTrue(policy.requestHeaders("https://cdn.test/$path").isEmpty())
            assertTrue(policy.requestHeaders("https://source.test:8443/$path").isEmpty())
            assertTrue(policy.requestHeaders("https://source.test.evil.test/$path").isEmpty())
        }
    }

    @Test
    fun `header sanitation rejects injection transport overrides and malformed codec data`() {
        val policy = LiveTvHttpPolicy("http://source.test/live", mapOf(
            "Authorization" to "old", "authorization" to "new",
            "Bad\rName" to "x", "Bad Name" to "x", "X-CR" to "x\ry", "X-LF" to "x\ny",
            "X-Nul" to "x\u0000", "Host" to "evil.test", "Range" to "bytes=10-20",
            "Proxy-Authorization" to "secret", "Connection" to "keep-alive", "Content-Length" to "20",
            "Transfer-Encoding" to "chunked", "Accept-Encoding" to "br", 12 to "bad", "X-NonString" to 123,
        ))
        assertEquals(mapOf("authorization" to "new"), policy.requestHeaders("http://source.test/live"))
    }

    @Test
    fun `redirects resolve relative locations but block downgrade and embedded credentials`() {
        val policy = LiveTvHttpPolicy("https://source.test/a/master", emptyMap<String, String>())
        assertEquals("https://source.test/b", policy.redirect("https://source.test/a/master", "../b"))
        for (target in listOf("http://source.test/b", "file:///tmp/live", "https://user:pass@source.test/b")) {
            assertThrows(IllegalArgumentException::class.java) { policy.redirect("https://source.test/a", target) }
        }
        assertThrows(IllegalArgumentException::class.java) { policy.requestHeaders("http://cdn.test/segment") }
        val upgraded = LiveTvHttpPolicy("http://source.test/live", mapOf("Cookie" to "secret"))
        assertEquals("https://source.test/live", upgraded.redirect("http://source.test/live", "https://source.test/live"))
        assertTrue(upgraded.requestHeaders("https://source.test/live").isEmpty())
        assertThrows(IllegalArgumentException::class.java) { upgraded.redirect("https://source.test/live", "http://source.test/live") }
    }

    @Test
    fun `invalid URLs are rejected without returning credentials in the error`() {
        for (url in listOf("file:///secret", "https://user:secret@host/live", "http:///live", "http://host:99999/a", "http://host:0/a", "https://host/\rsecret")) {
            val error = assertThrows(IllegalArgumentException::class.java) { LiveTvHttpPolicy.parse(url) }
            assertFalse(error.message.orEmpty().contains("secret"))
        }
    }

    @Test
    fun `extensionless HLS fallback is one shot and only on unrecognized container`() {
        for (url in listOf("https://source.test/live?token=secret.m3u8", "https://source.test/live/")) {
            val policy = LiveTvHlsFallbackPolicy(url)
            assertFalse(policy.tryFallback(false)) // TS, HTTP and decoder failures keep their original path.
            assertTrue(policy.tryFallback(true))
            assertFalse(policy.tryFallback(true))
        }
        for (path in listOf("live.ts", "live.mp4", "live.m3u8", "live.mpd")) {
            assertFalse(LiveTvHlsFallbackPolicy("https://source.test/$path").tryFallback(true))
        }
    }
}
