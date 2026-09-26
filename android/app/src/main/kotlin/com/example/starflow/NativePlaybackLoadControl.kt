package com.example.starflow

import android.os.SystemClock
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.analytics.PlayerId
import androidx.media3.exoplayer.source.TrackGroupArray
import androidx.media3.exoplayer.trackselection.ExoTrackSelection
import androidx.media3.exoplayer.upstream.DefaultAllocator

internal class NativePlaybackLoadControl(
    private val delegate: DefaultLoadControl,
    private val allocator: DefaultAllocator,
    private val config: NativePlaybackBufferConfig,
    limitBytes: Int,
    bitrate: Long,
    private val transfer: NativePlaybackTransferProgress?,
    private val clock: () -> Long = SystemClock::elapsedRealtime,
) : LoadControl by delegate {
    init {
        require(config.targetBufferBytes > 0) { "Adaptive load control requires a byte target" }
        require(limitBytes > 0) { "Adaptive load control requires a positive byte limit" }
    }

    private val policy = NativePlaybackReadAheadPolicy(config, limitBytes, bitrate)
    private val baseTargetBytes = config.targetBufferBytes.coerceAtMost(limitBytes)
    private var pressureUntil = 0L
    private var isLoading = false
    private val refill = NativePlaybackRefillPolicy()
    private var lastEvaluationAt = -1L
    private var lastPositionMs = 0L
    private var lastSpeed = 1f
    private var lastPlayWhenReady = false
    @Volatile var currentTargetBytes = baseTargetBytes
        private set

    // Java default interface methods are not forwarded by Kotlin delegation.
    override fun shouldStartPlayback(parameters: LoadControl.Parameters): Boolean =
        delegate.shouldStartPlayback(parameters)

    override fun getBackBufferDurationUs(playerId: PlayerId): Long =
        delegate.getBackBufferDurationUs(playerId)

    override fun retainBackBufferFromKeyframe(playerId: PlayerId): Boolean =
        delegate.retainBackBufferFromKeyframe(playerId)

    @Synchronized
    fun onMemoryPressure() {
        pressureUntil = clock() + 60_000
        invalidateMemoryBuffer()
        currentTargetBytes = baseTargetBytes
        allocator.setTargetBufferSize(baseTargetBytes)
        allocator.trim()
    }

    @Synchronized
    fun invalidateMemoryBuffer() {
        policy.reset()
        refill.reset()
        isLoading = true
        lastEvaluationAt = -1L
    }

    @Synchronized
    fun isMemoryReady(bufferedMs: Long): Boolean = clock() >= pressureUntil &&
        refill.memoryReady(bufferedMs)

    @Synchronized
    override fun shouldContinueLoading(parameters: LoadControl.Parameters): Boolean {
        val nowMs = clock()
        val memoryPressure = nowMs < pressureUntil
        val positionMs = parameters.playbackPositionUs / 1_000
        if (lastEvaluationAt >= 0 && (nowMs < lastEvaluationAt ||
                parameters.playbackSpeed != lastSpeed ||
                parameters.playWhenReady != lastPlayWhenReady ||
                positionMs < lastPositionMs ||
                positionMs - lastPositionMs >
                    (nowMs - lastEvaluationAt) * parameters.playbackSpeed + 2_000)) {
            invalidateMemoryBuffer()
        }
        lastEvaluationAt = nowMs
        lastPositionMs = positionMs
        lastSpeed = parameters.playbackSpeed
        lastPlayWhenReady = parameters.playWhenReady
        val network = transfer?.readAheadSnapshot()
        val (target, _) = policy.evaluate(
            nowMs, parameters.playbackPositionUs / 1_000,
            parameters.bufferedDurationUs / 1_000, parameters.playbackSpeed,
            parameters.playWhenReady, isLoading && network?.active == true,
            network?.bytesPerSecond, memoryPressure,
        )
        if (target > currentTargetBytes) refill.reset()
        currentTargetBytes = target
        allocator.setTargetBufferSize(target)
        if (memoryPressure) allocator.trim()
        // Resume thresholds remain owned by Media3; only read-ahead admission changes.
        isLoading = refill.evaluate(parameters.bufferedDurationUs / 1_000,
            allocator.totalBytesAllocated >= target ||
                parameters.bufferedDurationUs >= config.maxBufferMs * 1_000L)
        return isLoading
    }

    @Synchronized
    override fun onPrepared(playerId: PlayerId) {
        reset()
        delegate.onPrepared(playerId)
        allocator.setTargetBufferSize(currentTargetBytes)
    }

    @Synchronized
    override fun onTracksSelected(
        parameters: LoadControl.Parameters,
        trackGroups: TrackGroupArray,
        trackSelections: Array<out ExoTrackSelection?>,
    ) {
        delegate.onTracksSelected(parameters, trackGroups, trackSelections)
        allocator.setTargetBufferSize(currentTargetBytes)
    }

    @Synchronized
    override fun onStopped(playerId: PlayerId) {
        reset()
        delegate.onStopped(playerId)
    }

    @Synchronized
    override fun onReleased(playerId: PlayerId) {
        reset()
        delegate.onReleased(playerId)
    }

    private fun reset() {
        invalidateMemoryBuffer()
        pressureUntil = 0L
        currentTargetBytes = baseTargetBytes
    }
}
