package com.example.starflow

internal object NativePlaybackBufferBudget {
    fun limit(memoryClassMb: Int): Int = when {
        memoryClassMb <= 256 -> 48
        memoryClassMb <= 512 -> 80
        else -> 128
    } * 1024 * 1024

    fun target(baseBytes: Int, limitBytes: Int, bitrate: Long, seconds: Int): Int {
        if (bitrate <= 0) return baseBytes.coerceAtMost(limitBytes)
        return (bitrate.toDouble() / 8 * seconds).coerceIn(
            baseBytes.coerceAtMost(limitBytes).toDouble(), limitBytes.toDouble(),
        ).toInt()
    }
}

// Owned by the playback thread; UI memory-pressure signals enter through the load control.
internal class NativePlaybackReadAheadPolicy(
    private val config: NativePlaybackBufferConfig,
    private val limitBytes: Int,
    private val bitrate: Long,
) {
    private var lastSampleAt = -1L
    private var lastPositionMs = 0L
    private var lastBufferMs = 0L
    private var fallingSamples = 0
    private var boostUntil = 0L

    fun reset() {
        lastSampleAt = -1L
        fallingSamples = 0
        boostUntil = 0L
    }

    fun evaluate(
        nowMs: Long, positionMs: Long, bufferedMs: Long, speed: Float,
        playWhenReady: Boolean, reading: Boolean, bytesPerSecond: Long?,
        memoryPressure: Boolean,
    ): Pair<Int, Int> {
        val discontinuity = lastSampleAt >= 0 &&
            (positionMs < lastPositionMs ||
                positionMs - lastPositionMs > (nowMs - lastSampleAt) * speed + 2_000)
        if (!playWhenReady || discontinuity) reset()
        if (playWhenReady && (lastSampleAt < 0 || nowMs - lastSampleAt >= 1_000)) {
            // An idle loader with a full buffer is not evidence of a slow connection.
            val slowRead = reading && bytesPerSecond != null && bitrate > 0 &&
                bytesPerSecond * 8.0 < bitrate * speed * 1.3
            fallingSamples = if (lastSampleAt >= 0 && slowRead &&
                bufferedMs < lastBufferMs - 250) fallingSamples + 1 else 0
            if (fallingSamples >= 2) boostUntil = nowMs + 30_000
            lastSampleAt = nowMs
            lastPositionMs = positionMs
            lastBufferMs = bufferedMs
        }
        val boosted = playWhenReady && nowMs < boostUntil && !memoryPressure
        val target = if (memoryPressure) config.targetBufferBytes else
            NativePlaybackBufferBudget.target(config.targetBufferBytes, limitBytes, bitrate,
                if (boosted) 20 else 12)
        val refillMs = if (boosted) maxOf(config.minBufferMs, config.maxBufferMs * 3 / 4)
            else config.minBufferMs
        return target to refillMs
    }
}
