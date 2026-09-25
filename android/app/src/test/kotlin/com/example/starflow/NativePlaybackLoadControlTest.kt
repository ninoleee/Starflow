package com.example.starflow

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.analytics.PlayerId
import androidx.media3.exoplayer.source.MediaSource.MediaPeriodId
import androidx.media3.exoplayer.source.SinglePeriodTimeline
import androidx.media3.exoplayer.source.TrackGroupArray
import androidx.media3.exoplayer.upstream.Allocation
import androidx.media3.exoplayer.upstream.DefaultAllocator
import java.io.Closeable
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackLoadControlTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()

    @Test
    fun televisionCanStartAndResumeBeforeReadAheadBufferIsFull() {
        for (memoryClassMb in listOf(192, 512, 1024)) {
            for (isRemoteEpisodeSwitch in listOf(false, true)) {
                for (bandwidth in listOf(0L, 1_000_000L, 2_000_000L, 5_000_000L)) {
                    val config = NativePlaybackBufferPolicy.resolve(
                        isTelevision = true,
                        memoryClassMb = memoryClassMb,
                        isHeavyPlayback = false,
                        cachedBandwidthBytesPerSecond = bandwidth,
                        sourceBitrate = 10_000_000L,
                        isRemoteEpisodeSwitch = isRemoteEpisodeSwitch,
                    )
                    Fixture(config, NativePlaybackBufferBudget.limit(memoryClassMb)).use { f ->
                        assertEquals(0, f.allocator.totalBytesAllocated)
                        assertPlaybackThresholds(f)
                        assertTrue(f.control.shouldContinueLoading(f.parameters(2_000)))
                    }
                }
            }
        }
    }

    @Test
    fun dynamicExpansionDoesNotRaiseStartupOrRebufferThresholdsAtAnyPlaybackSpeed() {
        Fixture().use { f ->
            f.boost()
            assertTrue(f.control.currentTargetBytes > f.normalTarget)
            assertEquals(0, f.allocator.totalBytesAllocated)
            for (speed in listOf(0.5f, 1f, 2f)) assertPlaybackThresholds(f, speed)
        }
    }

    @Test
    fun loadingContinuesPastNormalTargetUntilDynamicTargetAndRetainsTimeHysteresis() {
        Fixture().use { f ->
            f.boost()
            val boostedTarget = f.control.currentTargetBytes
            assertEquals(10 * C.DEFAULT_BUFFER_SEGMENT_SIZE, boostedTarget)
            assertTrue(f.control.shouldContinueLoading(f.parameters(19_000)))
            f.allocate(f.config.targetBufferBytes / C.DEFAULT_BUFFER_SEGMENT_SIZE)
            assertTrue(f.control.shouldContinueLoading(f.parameters(25_000)))
            f.allocate((f.normalTarget - f.config.targetBufferBytes) / C.DEFAULT_BUFFER_SEGMENT_SIZE)
            assertEquals(6 * C.DEFAULT_BUFFER_SEGMENT_SIZE, f.normalTarget)
            assertTrue(f.control.shouldContinueLoading(f.parameters(25_000)))
            f.allocate((boostedTarget - f.normalTarget) / C.DEFAULT_BUFFER_SEGMENT_SIZE)
            assertFalse(f.control.shouldContinueLoading(f.parameters(25_000)))
            f.releaseAll()
            assertFalse(f.control.shouldContinueLoading(f.parameters(45_000)))
            assertTrue(f.control.shouldContinueLoading(f.parameters(44_999)))
            assertTrue(f.control.shouldContinueLoading(f.parameters(59_999)))
            assertFalse(f.control.shouldContinueLoading(f.parameters(60_000)))
            assertFalse(f.control.shouldContinueLoading(f.parameters(45_000)))
        }
    }

    @Test
    fun higherPlaybackSpeedRefillsEarlierButNeverBeyondTheMaximumDuration() {
        Fixture().use { f ->
            assertFalse(f.control.shouldContinueLoading(f.parameters(60_000, speed = 4f)))
            assertTrue(f.control.shouldContinueLoading(f.parameters(59_999, speed = 4f)))
            assertFalse(f.control.shouldContinueLoading(f.parameters(60_000, speed = 4f)))
        }
    }

    @Test
    fun activeHttpConnectionDuringIntentionalStopIsNotTreatedAsSlowNetwork() {
        Fixture().use { f ->
            f.transfer.onTransferStart(f.source, f.spec, true)
            assertTrue(f.control.shouldContinueLoading(f.parameters(19_000)))
            assertFalse(f.control.shouldContinueLoading(f.parameters(60_000)))
            for (bufferMs in listOf(59_000L, 58_000L, 40_000L)) {
                f.time += 1_000L
                assertFalse(f.control.shouldContinueLoading(f.parameters(bufferMs)))
                assertEquals(f.normalTarget, f.control.currentTargetBytes)
                assertTrue(f.transfer.isNetworkTransferActive)
            }
        }
    }

    @Test
    fun finishedTransferWithFallingBufferDoesNotTriggerSlowNetworkBoost() {
        Fixture().use { f ->
            f.transfer.onTransferStart(f.source, f.spec, true)
            assertTrue(f.control.shouldContinueLoading(f.parameters(19_000)))
            f.transfer.onTransferEnd(f.source, f.spec, true)
            repeat(3) { index ->
                f.time += 1_000L
                assertTrue(f.control.shouldContinueLoading(f.parameters(18_000L - index * 1_000L)))
                assertEquals(f.normalTarget, f.control.currentTargetBytes)
            }
        }
    }

    @Test
    fun pauseAndForwardOrBackwardSeekClearBoostWithoutChangingResumeThresholds() {
        for (scenario in listOf("pause", "forward", "backward")) {
            Fixture().use { f ->
                f.boost()
                f.time += 100L
                val position = when (scenario) {
                    "forward" -> 100_000L
                    "backward" -> 0L
                    else -> f.time
                }
                f.control.shouldContinueLoading(f.parameters(
                    16_000, positionMs = position, playWhenReady = scenario != "pause",
                ))
                assertEquals(scenario, f.normalTarget, f.control.currentTargetBytes)
                assertPlaybackThresholds(f)
            }
        }
    }

    @Test
    fun memoryPressureTrimsFreeBlocksButDoesNotDiscardQueuedMedia() {
        Fixture().use { f ->
            f.boost()
            val count = f.control.currentTargetBytes / C.DEFAULT_BUFFER_SEGMENT_SIZE
            val blocks = f.allocate(count)
            val retained = blocks.first()
            f.releaseAllExcept(retained)
            assertEquals(C.DEFAULT_BUFFER_SEGMENT_SIZE, f.allocator.totalBytesAllocated)

            f.control.onMemoryPressure()
            assertEquals(f.config.targetBufferBytes, f.control.currentTargetBytes)
            assertEquals(C.DEFAULT_BUFFER_SEGMENT_SIZE, f.allocator.totalBytesAllocated)

            // The allocator's byte counter excludes its free pool. Reuse identity tests trimming.
            val reused = f.allocate(count - 1).count { allocation -> blocks.any { it === allocation } }
            assertEquals(f.config.targetBufferBytes / C.DEFAULT_BUFFER_SEGMENT_SIZE - 1, reused)
            assertFalse(f.control.shouldContinueLoading(f.parameters(10_000)))
            f.releaseAll()
            f.time += 59_999L
            assertTrue(f.control.shouldContinueLoading(f.parameters(1_000)))
            assertEquals(f.config.targetBufferBytes, f.control.currentTargetBytes)
            f.time += 1L
            f.control.shouldContinueLoading(f.parameters(1_000))
            assertEquals(f.normalTarget, f.control.currentTargetBytes)
        }
    }

    @Test
    fun stoppedOrReleasedControlDropsLoadingHistoryBeforeBeingPreparedAgain() {
        for (release in listOf(false, true)) {
            Fixture().use { f ->
                f.boost()
                if (release) f.control.onReleased(PlayerId.UNSET) else f.control.onStopped(PlayerId.UNSET)
                assertEquals(f.config.targetBufferBytes, f.control.currentTargetBytes)
                f.control.onPrepared(PlayerId.UNSET)
                assertFalse(f.control.shouldContinueLoading(f.parameters(40_000)))
                assertEquals(f.normalTarget, f.control.currentTargetBytes)
            }
        }
    }

    private fun assertPlaybackThresholds(f: Fixture, speed: Float = 1f) {
        for (rebuffering in listOf(false, true)) {
            val threshold = if (rebuffering) f.config.bufferForPlaybackAfterRebufferMs
                else f.config.bufferForPlaybackMs
            val durationUs = (threshold * 1_000L * speed).toLong()
            assertFalse(f.control.shouldStartPlayback(f.parameters(
                0, bufferedUs = durationUs - 1_000, rebuffering = rebuffering, speed = speed,
            )))
            assertTrue(f.control.shouldStartPlayback(f.parameters(
                0, bufferedUs = durationUs, rebuffering = rebuffering, speed = speed,
            )))
        }
    }

    private class Fixture(
        val config: NativePlaybackBufferConfig = NativePlaybackBufferConfig(
            20_000, 60_000, 1_500, 2_000, 4 * C.DEFAULT_BUFFER_SEGMENT_SIZE, false,
        ),
        limitBytes: Int = 12 * C.DEFAULT_BUFFER_SEGMENT_SIZE,
        bitrate: Long = 4L * C.DEFAULT_BUFFER_SEGMENT_SIZE,
    ) : Closeable {
        var time = 0L
        val transfer = NativePlaybackTransferProgress { time }
        val source = mock(DataSource::class.java)
        val spec = mock(DataSpec::class.java)
        val allocator = DefaultAllocator(true, C.DEFAULT_BUFFER_SEGMENT_SIZE)
        private val uri = mock(Uri::class.java).also { `when`(it.scheme).thenReturn("https") }
        private val timeline = SinglePeriodTimeline(
            120_000_000L, true, false, false, null, MediaItem.Builder().setUri(uri).build(),
        )
        private val periodId = MediaPeriodId(timeline.getUidOfPeriod(0))
        private val delegate = DefaultLoadControl.Builder()
            .setAllocator(allocator)
            .setBufferDurationsMs(config.minBufferMs, config.maxBufferMs,
                config.bufferForPlaybackMs, config.bufferForPlaybackAfterRebufferMs)
            .setTargetBufferBytes(config.targetBufferBytes)
            .setPrioritizeTimeOverSizeThresholds(config.prioritizeTimeOverSizeThresholds)
            .build()
        val control = NativePlaybackLoadControl(
            delegate, allocator, config, limitBytes, bitrate, transfer, clock = { time },
        )
        val normalTarget = NativePlaybackBufferBudget.target(config.targetBufferBytes, limitBytes, bitrate, 12)
        private val playerAllocator = control.getAllocator(PlayerId.UNSET)
        private val allocations = mutableListOf<Allocation>()

        init {
            control.onPrepared(PlayerId.UNSET)
            control.onTracksSelected(parameters(0), TrackGroupArray.EMPTY, emptyArray())
        }

        fun parameters(
            bufferedMs: Long,
            positionMs: Long = time,
            playWhenReady: Boolean = true,
            speed: Float = 1f,
            rebuffering: Boolean = false,
            bufferedUs: Long = bufferedMs * 1_000L,
        ) = LoadControl.Parameters(
            PlayerId.UNSET, timeline, periodId, positionMs * 1_000L, bufferedUs, speed,
            playWhenReady, rebuffering, C.TIME_UNSET, C.TIME_UNSET,
        )

        fun boost() {
            transfer.onTransferStart(source, spec, true)
            assertTrue(control.shouldContinueLoading(parameters(19_000)))
            repeat(2) { index ->
                time += 1_000L
                transfer.onBytesTransferred(source, spec, true, 1_000)
                assertTrue(control.shouldContinueLoading(parameters(18_000L - index * 1_000L)))
            }
            assertTrue(control.currentTargetBytes > normalTarget)
        }

        fun allocate(count: Int): List<Allocation> = List(count) {
            playerAllocator.allocate().also(allocations::add)
        }

        fun releaseAllExcept(retained: Allocation? = null) {
            allocations.filter { it !== retained }.forEach { playerAllocator.release(it) }
            allocations.removeAll { it !== retained }
        }

        fun releaseAll() = releaseAllExcept()

        override fun close() {
            releaseAll()
            control.onReleased(PlayerId.UNSET)
        }
    }
}
