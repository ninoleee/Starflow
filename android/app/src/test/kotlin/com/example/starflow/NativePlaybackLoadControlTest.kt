package com.example.starflow

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.analytics.PlayerId
import androidx.media3.exoplayer.source.MediaSource.MediaPeriodId
import androidx.media3.exoplayer.source.SinglePeriodTimeline
import androidx.media3.exoplayer.upstream.DefaultAllocator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackLoadControlTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()

    @Test
    fun televisionCanStartAndResumeBeforeReadAheadBufferIsFull() {
        val uri = mock(Uri::class.java)
        `when`(uri.scheme).thenReturn("https")
        val timeline = SinglePeriodTimeline(
            120_000_000L, true, false, false, null,
            MediaItem.Builder().setUri(uri).build(),
        )
        val periodId = MediaPeriodId(timeline.getUidOfPeriod(0))
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
                    val allocator = DefaultAllocator(true, C.DEFAULT_BUFFER_SEGMENT_SIZE)
                    val control = DefaultLoadControl.Builder()
                        .setAllocator(allocator)
                        .setBufferDurationsMs(
                            config.minBufferMs,
                            config.maxBufferMs,
                            config.bufferForPlaybackMs,
                            config.bufferForPlaybackAfterRebufferMs,
                        )
                        .setTargetBufferBytes(config.targetBufferBytes)
                        .setPrioritizeTimeOverSizeThresholds(config.prioritizeTimeOverSizeThresholds)
                        .build()
                    val playerId = PlayerId.UNSET
                    control.onPrepared(playerId)
                    try {
                        for (rebuffering in listOf(false, true)) {
                            val thresholdMs = if (rebuffering) {
                                config.bufferForPlaybackAfterRebufferMs
                            } else {
                                config.bufferForPlaybackMs
                            }
                            fun parameters(bufferedMs: Int) = LoadControl.Parameters(
                                playerId, timeline, periodId,
                                0L, bufferedMs * 1_000L, 1f, true, rebuffering,
                                C.TIME_UNSET, C.TIME_UNSET,
                            )

                            assertEquals(0, allocator.totalBytesAllocated)
                            assertFalse(control.shouldStartPlayback(parameters(thresholdMs - 1)))
                            assertTrue(control.shouldStartPlayback(parameters(thresholdMs)))
                            assertTrue(control.shouldContinueLoading(parameters(thresholdMs)))
                        }
                    } finally {
                        control.onReleased(playerId)
                    }
                }
            }
        }
    }
}
