package com.example.starflow

import android.os.SystemClock

data class NativePlaybackPerformanceSummary(
    val reason: String,
    val sessionDurationMs: Long,
    val firstFrameMs: Long,
    val bufferingCount: Int,
    val bufferingDurationMs: Long,
    val recoveryCount: Int,
    val droppedVideoFrames: Int,
    val audioUnderrunCount: Int,
    val averageNetworkBytesPerSecond: Long,
    val minimumNetworkBytesPerSecond: Long,
    val maximumNetworkBytesPerSecond: Long,
    val sourceBitrate: Long,
    val bandwidthToBitrateRatio: Double?,
    val videoDecoder: String,
    val audioDecoder: String,
    val targetBufferBytes: Int,
    val memoryClassMb: Int,
)

class NativePlaybackPerformanceTracker(
    private val clock: () -> Long = SystemClock::elapsedRealtime,
) {
    private var startedAtMs = 0L
    private var firstFrameAtMs = 0L
    private var bufferingStartedAtMs = 0L
    private var bufferingDurationMs = 0L
    private var bufferingCount = 0
    private var recoveryCount = 0
    private var droppedVideoFrames = 0
    private var audioUnderrunCount = 0
    private var networkSampleCount = 0L
    private var networkBytesPerSecondSum = 0L
    private var minimumNetworkBytesPerSecond = 0L
    private var maximumNetworkBytesPerSecond = 0L
    private var sourceBitrate = 0L
    private var videoDecoder = ""
    private var audioDecoder = ""
    private var targetBufferBytes = 0
    private var memoryClassMb = 0
    private var active = false

    fun begin(sourceBitrate: Long) {
        startedAtMs = clock()
        firstFrameAtMs = 0L
        bufferingStartedAtMs = 0L
        bufferingDurationMs = 0L
        bufferingCount = 0
        recoveryCount = 0
        droppedVideoFrames = 0
        audioUnderrunCount = 0
        networkSampleCount = 0L
        networkBytesPerSecondSum = 0L
        minimumNetworkBytesPerSecond = 0L
        maximumNetworkBytesPerSecond = 0L
        this.sourceBitrate = sourceBitrate.coerceAtLeast(0L)
        videoDecoder = ""
        audioDecoder = ""
        targetBufferBytes = 0
        memoryClassMb = 0
        active = true
    }

    fun configureBuffer(targetBufferBytes: Int, memoryClassMb: Int) {
        this.targetBufferBytes = targetBufferBytes.coerceAtLeast(0)
        this.memoryClassMb = memoryClassMb.coerceAtLeast(0)
    }

    fun onBufferingChanged(buffering: Boolean, playWhenReady: Boolean) {
        if (!active) return
        val now = clock()
        if (buffering && playWhenReady) {
            if (bufferingStartedAtMs == 0L) {
                bufferingStartedAtMs = now
                bufferingCount += 1
            }
            return
        }
        closeBufferingWindow(now)
    }

    fun onFirstFrame(): Long {
        if (!active) return 0L
        if (firstFrameAtMs != 0L) return -1L
        firstFrameAtMs = clock()
        return (firstFrameAtMs - startedAtMs).coerceAtLeast(0L)
    }

    fun onBandwidthSample(bytesPerSecond: Long) {
        if (!active || bytesPerSecond <= 0L) return
        networkSampleCount += 1L
        networkBytesPerSecondSum += bytesPerSecond
        if (minimumNetworkBytesPerSecond == 0L ||
            bytesPerSecond < minimumNetworkBytesPerSecond
        ) {
            minimumNetworkBytesPerSecond = bytesPerSecond
        }
        maximumNetworkBytesPerSecond = maxOf(
            maximumNetworkBytesPerSecond,
            bytesPerSecond,
        )
    }

    fun onRecovery() {
        if (active) recoveryCount += 1
    }

    fun onDroppedVideoFrames(count: Int) {
        if (active) droppedVideoFrames += count.coerceAtLeast(0)
    }

    fun onAudioUnderrun() {
        if (active) audioUnderrunCount += 1
    }

    fun onVideoDecoder(name: String) {
        if (active && name.isNotBlank()) videoDecoder = name.trim()
    }

    fun onAudioDecoder(name: String) {
        if (active && name.isNotBlank()) audioDecoder = name.trim()
    }

    fun finish(reason: String): NativePlaybackPerformanceSummary? {
        if (!active) return null
        val now = clock()
        closeBufferingWindow(now)
        active = false
        val averageBytesPerSecond = if (networkSampleCount > 0L) {
            networkBytesPerSecondSum / networkSampleCount
        } else {
            0L
        }
        val ratio = if (sourceBitrate > 0L && averageBytesPerSecond > 0L) {
            (averageBytesPerSecond * 8.0) / sourceBitrate
        } else {
            null
        }
        return NativePlaybackPerformanceSummary(
            reason = reason,
            sessionDurationMs = (now - startedAtMs).coerceAtLeast(0L),
            firstFrameMs = if (firstFrameAtMs > 0L) {
                (firstFrameAtMs - startedAtMs).coerceAtLeast(0L)
            } else {
                0L
            },
            bufferingCount = bufferingCount,
            bufferingDurationMs = bufferingDurationMs,
            recoveryCount = recoveryCount,
            droppedVideoFrames = droppedVideoFrames,
            audioUnderrunCount = audioUnderrunCount,
            averageNetworkBytesPerSecond = averageBytesPerSecond,
            minimumNetworkBytesPerSecond = minimumNetworkBytesPerSecond,
            maximumNetworkBytesPerSecond = maximumNetworkBytesPerSecond,
            sourceBitrate = sourceBitrate,
            bandwidthToBitrateRatio = ratio,
            videoDecoder = videoDecoder,
            audioDecoder = audioDecoder,
            targetBufferBytes = targetBufferBytes,
            memoryClassMb = memoryClassMb,
        )
    }

    private fun closeBufferingWindow(now: Long) {
        if (bufferingStartedAtMs <= 0L) return
        bufferingDurationMs += (now - bufferingStartedAtMs).coerceAtLeast(0L)
        bufferingStartedAtMs = 0L
    }
}
