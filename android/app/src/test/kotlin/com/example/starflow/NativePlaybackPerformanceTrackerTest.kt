package com.example.starflow

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NativePlaybackPerformanceTrackerTest {
    @Test
    fun `summarizes first frame buffering bandwidth and recovery`() {
        var now = 1_000L
        val tracker = NativePlaybackPerformanceTracker(clock = { now })
        tracker.begin(sourceBitrate = 8_000_000L)
        tracker.configureBuffer(targetBufferBytes = 48 * 1024 * 1024, memoryClassMb = 192)
        tracker.onBufferingChanged(buffering = true, playWhenReady = true)
        now += 750L
        tracker.onBufferingChanged(buffering = false, playWhenReady = true)
        now += 250L
        assertEquals(1_000L, tracker.onFirstFrame())
        tracker.onBandwidthSample(2_000_000L)
        tracker.onBandwidthSample(1_000_000L)
        tracker.onDroppedVideoFrames(3)
        tracker.onAudioUnderrun()
        tracker.onRecovery()
        now += 4_000L

        val summary = tracker.finish("destroyed")!!

        assertEquals(1_000L, summary.firstFrameMs)
        assertEquals(1, summary.bufferingCount)
        assertEquals(750L, summary.bufferingDurationMs)
        assertEquals(1, summary.recoveryCount)
        assertEquals(3, summary.droppedVideoFrames)
        assertEquals(1, summary.audioUnderrunCount)
        assertEquals(1_500_000L, summary.averageNetworkBytesPerSecond)
        assertTrue((summary.bandwidthToBitrateRatio ?: 0.0) > 1.0)
        assertEquals(192, summary.memoryClassMb)
    }
}
