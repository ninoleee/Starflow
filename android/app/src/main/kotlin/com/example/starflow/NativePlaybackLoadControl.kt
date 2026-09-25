package com.example.starflow

import android.os.SystemClock
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.analytics.PlayerId
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
    private val policy = NativePlaybackReadAheadPolicy(config, limitBytes, bitrate)
    @Volatile private var pressureUntil = 0L
    @Volatile var currentTargetBytes = config.targetBufferBytes
        private set

    fun onMemoryPressure() {
        pressureUntil = clock() + 60_000
        allocator.trim()
    }

    override fun shouldContinueLoading(parameters: LoadControl.Parameters): Boolean {
        val normal = delegate.shouldContinueLoading(parameters)
        val (target, refillMs) = policy.evaluate(
            clock(), parameters.playbackPositionUs / 1_000,
            parameters.bufferedDurationUs / 1_000, parameters.playbackSpeed,
            parameters.playWhenReady, transfer?.isNetworkTransferActive == true,
            transfer?.rawBytesPerSecond, clock() < pressureUntil,
        )
        currentTargetBytes = target
        // Resume thresholds remain owned by Media3; only read-ahead admission changes.
        if (allocator.totalBytesAllocated >= target ||
            parameters.bufferedDurationUs >= config.maxBufferMs * 1_000L) return false
        return normal || parameters.bufferedDurationUs <
            refillMs * 1_000L * parameters.playbackSpeed.coerceAtLeast(1f)
    }

    override fun onStopped(playerId: PlayerId) {
        policy.reset()
        delegate.onStopped(playerId)
    }

    override fun onReleased(playerId: PlayerId) {
        policy.reset()
        delegate.onReleased(playerId)
    }
}
