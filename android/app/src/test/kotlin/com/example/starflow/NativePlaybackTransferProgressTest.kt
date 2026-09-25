package com.example.starflow

import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
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
    fun readAheadSnapshotOnlyReportsSpeedWhileAReadIsActive() {
        progress.onTransferStart(source, spec, true)
        time += 2_000L
        progress.onBytesTransferred(source, spec, true, 2_000)

        assertTrue(progress.readAheadSnapshot().active)
        assertEquals(1_000L, progress.readAheadSnapshot().bytesPerSecond)

        progress.onTransferEnd(source, spec, true)
        assertFalse(progress.readAheadSnapshot().active)
        assertNull(progress.readAheadSnapshot().bytesPerSecond)
    }

    @Test
    fun overlappingNetworkTransfersRemainActiveUntilTheLastOneEnds() {
        progress.onTransferStart(source, spec, true)
        progress.onTransferStart(source, spec, true)
        assertTrue(progress.isNetworkTransferActive)

        progress.onTransferEnd(source, spec, true)
        assertTrue(progress.isNetworkTransferActive)

        progress.onTransferEnd(source, spec, true)
        assertFalse(progress.isNetworkTransferActive)
        progress.onTransferEnd(source, spec, true)
        assertFalse(progress.isNetworkTransferActive)
    }

    @Test
    fun networkSpeedExcludesIdleTimeAndDoesNotReuseIdleZeroOnRestart() {
        time += 10_000L
        progress.sampleNetworkSpeed()
        assertEquals(0L, progress.networkBytesPerSecond)
        progress.onTransferStart(source, spec, true)
        assertNull(progress.readAheadSnapshot().bytesPerSecond)
        progress.onBytesTransferred(source, spec, true, 4_000)
        time += 500L
        progress.onTransferEnd(source, spec, true)
        time += 1_500L
        progress.sampleNetworkSpeed()
        assertEquals(8_000L, progress.rawBytesPerSecond)
        assertEquals(2_000L, progress.networkBytesPerSecond)
        assertNull(progress.readAheadSnapshot().bytesPerSecond)
        progress.onTransferStart(source, spec, true)
        assertNull(progress.readAheadSnapshot().bytesPerSecond)
        time += 1_000L
        assertEquals(0L, progress.readAheadSnapshot().bytesPerSecond)
    }

    @Test
    fun overlappingTransfersUseUnionOfActiveTimeNotSumOfDurations() {
        progress.onTransferStart(source, spec, true)
        time += 500L
        progress.onTransferStart(source, spec, true)
        progress.onBytesTransferred(source, spec, true, 4_000)
        time += 500L
        progress.onTransferEnd(source, spec, true)
        assertTrue(progress.readAheadSnapshot().active)
        assertEquals(4_000L, progress.rawBytesPerSecond)
        progress.onTransferEnd(source, spec, true)
    }

    @Test
    fun localTransferCallbacksDoNotAffectNetworkActivityOrSpeed() {
        progress.onTransferStart(source, spec, false)
        assertFalse(progress.isNetworkTransferActive)
        progress.onTransferStart(source, spec, true)
        progress.onBytesTransferred(source, spec, true, 1_000)
        progress.onBytesTransferred(source, spec, false, 99_000)
        progress.onTransferEnd(source, spec, false)
        time += 1_000L
        assertTrue(progress.readAheadSnapshot().active)
        assertEquals(1_000L, progress.rawBytesPerSecond)
    }

    @Test
    fun parallelCallbacksDoNotLoseBytesOrFinishAnotherActiveTransfer() {
        val workers = Executors.newFixedThreadPool(4)
        val start = CountDownLatch(1)
        progress.onTransferStart(source, spec, true)
        try {
            val futures = List(4) {
                workers.submit {
                    start.await()
                    progress.onTransferStart(source, spec, true)
                    repeat(1_000) {
                        progress.onBytesTransferred(source, spec, true, 128)
                        progress.readAheadSnapshot()
                    }
                    progress.onTransferEnd(source, spec, true)
                }
            }
            start.countDown()
            futures.forEach { it.get(10, TimeUnit.SECONDS) }
            time += 1_000L
            assertTrue(progress.readAheadSnapshot().active)
            assertEquals(512_000L, progress.rawBytesPerSecond)
            assertEquals(512_000L, progress.networkBytesPerSecond)
            progress.onTransferEnd(source, spec, true)
            assertFalse(progress.isNetworkTransferActive)
        } finally {
            workers.shutdownNow()
            assertTrue(workers.awaitTermination(10, TimeUnit.SECONDS))
        }
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
