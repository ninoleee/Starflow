package com.example.starflow

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackCacheDiagnosticsTest {
    private val host = mock(NativePlaybackDiagnostics.Host::class.java, RETURNS_DEEP_STUBS)
    private data class Call(val method: String, val args: Map<String, Any?>,
        val reply: (Map<String, Any?>) -> Unit)
    private val calls = mutableListOf<Call>()
    private var time = 100L
    private val diagnostics = NativePlaybackDiagnostics(host,
        { method, args, reply -> calls += Call(method, args, reply) }, { time })

    @Before
    fun setup() {
        `when`(host.target.resolverSessionId).thenReturn("session")
        diagnostics.beginCacheTransport("http://127.0.0.1/playback-relay/one", true)
        diagnostics.networkSpeedVisible = true
        calls.clear()
    }

    @Test
    fun diskVisibilityFollowsValidatedSnapshotAndResetsOnTransportChange() {
        assertFalse(diagnostics.showDiskCache)
        diagnostics.sampleRelayCacheIfVisible()
        val enabled = calls.last()
        enabled.reply(enabled.args + mapOf("ok" to true, "showDiskCache" to true, "storedBytes" to 2048L))
        assertTrue(diagnostics.showDiskCache)
        time += 2000
        diagnostics.sampleRelayCacheIfVisible()
        val disabled = calls.last()
        disabled.reply(disabled.args + mapOf("ok" to true, "showDiskCache" to false, "storedBytes" to 2048L))
        assertFalse(diagnostics.showDiskCache)
        enabled.reply(enabled.args + mapOf("ok" to true, "showDiskCache" to true))
        assertFalse(diagnostics.showDiskCache)
        diagnostics.beginCacheTransport("https://example.test/direct.mp4", true)
        assertFalse(diagnostics.showDiskCache)
    }

    @Test
    fun visibleSamplingIsLocalSingleFlightAndLowFrequency() {
        diagnostics.sampleRelayCacheIfVisible()
        repeat(5) { diagnostics.sampleRelayCacheIfVisible() }
        val sample = calls.single()
        assertEquals("nativePlaybackCacheSnapshot", sample.method)
        sample.reply(sample.args + mapOf("ok" to true, "storedBytes" to 2048L))
        assertEquals(2048L, diagnostics.relayStoredBytes)
        time += 1999
        diagnostics.sampleRelayCacheIfVisible()
        assertEquals(1, calls.size)
        time++
        diagnostics.sampleRelayCacheIfVisible()
        assertEquals(2, calls.size)
    }

    @Test
    fun hiddenBackgroundAndReleasedTransportIgnoreLateSamples() {
        for (hide in listOf<() -> Unit>(
            { diagnostics.networkSpeedVisible = false },
            { diagnostics.displayActive = false },
            { diagnostics.endCacheTransport() },
        )) {
            diagnostics.beginCacheTransport("http://127.0.0.1/playback-relay/one", true)
            diagnostics.networkSpeedVisible = true
            diagnostics.displayActive = true
            calls.clear()
            diagnostics.sampleRelayCacheIfVisible()
            val stale = calls.single()
            hide()
            stale.reply(stale.args + mapOf("ok" to true, "storedBytes" to 9999L))
            assertNull(diagnostics.relayStoredBytes)
            val count = calls.size
            time += 5000
            diagnostics.sampleRelayCacheIfVisible()
            assertEquals(count, calls.size)
        }
    }

    @Test
    fun seekAndPauseCarryIncreasingGenerationAndCurrentTransport() {
        diagnostics.setPlaybackActive(false)
        diagnostics.cancelReadAhead()
        diagnostics.setPlaybackActive(true)
        assertEquals(listOf("setNativePlaybackActive", "cancelNativePlaybackReadAhead",
            "setNativePlaybackActive"), calls.map { it.method })
        assertEquals(false, calls.first().args["active"])
        assertEquals(true, calls.last().args["active"])
        val generations = calls.map { (it.args["generation"] as Number).toLong() }
        assertTrue(generations.zipWithNext().all { (a, b) -> a < b })
        assertTrue(calls.all { it.args["resolverSessionId"] == "session" &&
            it.args["currentURL"] == "http://127.0.0.1/playback-relay/one" })
    }

    @Test
    fun sameUrlRebuildRejectsPreviousGeneration() {
        diagnostics.sampleRelayCacheIfVisible()
        val stale = calls.single()
        diagnostics.endCacheTransport()
        diagnostics.beginCacheTransport(stale.args["currentURL"] as String, true)
        diagnostics.sampleRelayCacheIfVisible()
        val current = calls.last()
        assertTrue((current.args["generation"] as Long) > (stale.args["generation"] as Long))
        stale.reply(stale.args + mapOf("ok" to true, "storedBytes" to 9999L))
        assertNull(diagnostics.relayStoredBytes)
        current.reply(current.args + mapOf("ok" to true, "storedBytes" to 4096L))
        assertEquals(4096L, diagnostics.relayStoredBytes)
    }

    @Test
    fun hiddenResumeAndTimeoutDoNotBlockOrClearReplacementSample() {
        diagnostics.sampleRelayCacheIfVisible()
        val hidden = calls.single()
        diagnostics.networkSpeedVisible = false
        diagnostics.networkSpeedVisible = true
        diagnostics.sampleRelayCacheIfVisible()
        val resumed = calls.last()
        hidden.reply(mapOf("ok" to false))
        diagnostics.sampleRelayCacheIfVisible()
        assertEquals(2, calls.size)
        time += 2_000
        diagnostics.sampleRelayCacheIfVisible()
        val replacement = calls.last()
        assertEquals(3, calls.size)
        resumed.reply(resumed.args + mapOf("ok" to true, "storedBytes" to 9999L))
        assertNull(diagnostics.relayStoredBytes)
        replacement.reply(replacement.args + mapOf("ok" to true, "storedBytes" to 4096L))
        assertEquals(4096L, diagnostics.relayStoredBytes)
        resumed.reply(mapOf("ok" to false))
        assertEquals(4096L, diagnostics.relayStoredBytes)
    }

    @Test
    fun previousTransportAndMismatchedReplyCannotPublish() {
        diagnostics.sampleRelayCacheIfVisible()
        val stale = calls.single()
        diagnostics.beginCacheTransport("http://127.0.0.1/playback-relay/two", true)
        stale.reply(stale.args + mapOf("ok" to true, "storedBytes" to 9999L))
        assertNull(diagnostics.relayStoredBytes)
        diagnostics.sampleRelayCacheIfVisible()
        val current = calls.last()
        current.reply(current.args + mapOf("ok" to true, "storedBytes" to 4096L,
            "currentURL" to "old"))
        assertNull(diagnostics.relayStoredBytes)
    }

    @Test
    fun memoryLeaseRefreshesEverySecondWithoutVisibleDiagnostics() {
        diagnostics.networkSpeedVisible = false
        diagnostics.displayActive = false
        `when`(host.session.isMemoryBufferReady()).thenReturn(true)
        diagnostics.reportMemoryBufferState()
        assertEquals(true, calls.single().args["memoryReady"])
        time += 999
        diagnostics.reportMemoryBufferState()
        assertEquals(1, calls.size)
        time++
        diagnostics.reportMemoryBufferState()
        assertEquals(2, calls.size)
        assertTrue(calls.all { it.method == "setNativePlaybackBufferState" })
        assertTrue((calls.last().args["generation"] as Long) >
            (calls.first().args["generation"] as Long))
        diagnostics.reportMemoryBufferState(forceNotReady = true)
        assertEquals(false, calls.last().args["memoryReady"])
    }

    @Test
    fun startupReleaseAndReplacementPlayerCannotPublishStaleReadiness() {
        diagnostics.beginCacheTransport("same", true)
        assertEquals(false, calls.last().args["memoryReady"])
        `when`(host.session.isMemoryBufferReady()).thenReturn(true)
        diagnostics.reportMemoryBufferState()
        val stale = calls.last()
        assertEquals(true, stale.args["memoryReady"])
        val replacement = mock(androidx.media3.exoplayer.ExoPlayer::class.java)
        `when`(host.session.player).thenReturn(replacement)
        diagnostics.reportMemoryBufferState()
        assertEquals(false, calls.last().args["memoryReady"])
        val count = calls.size
        stale.reply(stale.args + mapOf("ok" to true, "memoryReady" to true))
        assertEquals(count, calls.size)
        diagnostics.endCacheTransport()
        assertEquals(false, calls.last { it.method == "setNativePlaybackBufferState" }.args["memoryReady"])
        calls.clear()
        time += 1_000
        diagnostics.reportMemoryBufferState()
        assertTrue(calls.isEmpty())
    }

    @Test
    fun memoryReportsDoNotInvalidatePendingUiSnapshot() {
        diagnostics.sampleRelayCacheIfVisible()
        val sample = calls.single()
        `when`(host.session.isMemoryBufferReady()).thenReturn(true)
        diagnostics.reportMemoryBufferState()
        sample.reply(sample.args + mapOf("ok" to true, "storedBytes" to 2048L))
        assertEquals(2048L, diagnostics.relayStoredBytes)
    }
}
