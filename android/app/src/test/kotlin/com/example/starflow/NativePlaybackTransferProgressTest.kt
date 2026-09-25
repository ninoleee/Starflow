package com.example.starflow

import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.mock

class NativePlaybackTransferProgressTest {
    private val source = mock(DataSource::class.java)
    private val spec = mock(DataSpec::class.java)
    private var time = 1_000L
    private val progress = NativePlaybackTransferProgress { time }

    @Test
    fun openingAndRetryingConnectionsWithoutBytesDoesNotCountAsProgress() {
        progress.onTransferInitializing(source, spec, true)
        progress.onTransferStart(source, spec, true)
        progress.onBytesTransferred(source, spec, true, 0)
        progress.onTransferEnd(source, spec, true)
        time += 10_000L
        progress.onTransferStart(source, spec, true)
        assertEquals(-1L, progress.lastProgressAtMs)
    }

    @Test
    fun bytesAreVisibleBeforeTheTransferCompletes() {
        progress.onTransferStart(source, spec, true)
        progress.onBytesTransferred(source, spec, true, 1_024)
        assertEquals(1_000L, progress.lastProgressAtMs)
        time += 20_000L
        progress.onBytesTransferred(source, spec, true, 64)
        assertEquals(21_000L, progress.lastProgressAtMs)
        time += 5_000L
        progress.onTransferEnd(source, spec, true)
        assertEquals(21_000L, progress.lastProgressAtMs)
    }

    @Test
    fun nonNetworkAndInvalidSamplesDoNotAdvanceTheTimestamp() {
        progress.onBytesTransferred(source, spec, true, 1)
        time += 20_000L
        progress.onBytesTransferred(source, spec, false, 1_024)
        progress.onBytesTransferred(source, spec, true, -1)
        assertEquals(1_000L, progress.lastProgressAtMs)
    }

    @Test
    fun listenersDoNotShareProgressBetweenPlayers() {
        val next = NativePlaybackTransferProgress { time }
        progress.onBytesTransferred(source, spec, true, 4_096)
        assertEquals(-1L, next.lastProgressAtMs)
        assertNull(next.networkBytesPerSecond)
    }

    @Test
    fun samplesOngoingReadsByElapsedTimeAndClearsIdleImmediately() {
        assertNull(progress.networkBytesPerSecond)
        progress.onBytesTransferred(source, spec, true, 1024)
        progress.onBytesTransferred(source, spec, true, 3072)
        progress.onBytesTransferred(source, spec, false, 99999)
        progress.onBytesTransferred(source, spec, true, -1)
        time += 500L
        progress.sampleNetworkSpeed()
        assertNull(progress.networkBytesPerSecond)
        time += 1500L
        progress.sampleNetworkSpeed()
        assertEquals(2048L, progress.networkBytesPerSecond)
        progress.onBytesTransferred(source, spec, true, 4096)
        progress.sampleNetworkSpeed()
        assertEquals(2048L, progress.networkBytesPerSecond)
        time += 1000L
        progress.sampleNetworkSpeed()
        assertEquals(3072L, progress.networkBytesPerSecond)
        time += 1000L
        progress.sampleNetworkSpeed()
        assertEquals(0L, progress.networkBytesPerSecond)
        progress.onBytesTransferred(source, spec, true, 1024)
        time += 1000L
        progress.sampleNetworkSpeed()
        assertEquals(1024L, progress.networkBytesPerSecond)
        assertEquals(5000L, progress.lastProgressAtMs)
    }
}
