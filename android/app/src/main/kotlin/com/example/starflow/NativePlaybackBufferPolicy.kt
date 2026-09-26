package com.example.starflow

data class NativePlaybackBufferConfig(
    val minBufferMs: Int,
    val maxBufferMs: Int,
    val bufferForPlaybackMs: Int,
    val bufferForPlaybackAfterRebufferMs: Int,
    val targetBufferBytes: Int,
    val prioritizeTimeOverSizeThresholds: Boolean,
    val bandwidthProfile: String = "unknown",
    val episodeSwitchWarmup: Boolean = false,
)

object NativePlaybackBufferPolicy {
    private const val MEBIBYTE = 1024 * 1024

    fun resolve(
        isTelevision: Boolean,
        memoryClassMb: Int,
        isHeavyPlayback: Boolean,
        cachedBandwidthBytesPerSecond: Long = 0L,
        sourceBitrate: Long = 0L,
        isRemoteEpisodeSwitch: Boolean = false,
        memoryCacheMiB: Int = 0,
    ): NativePlaybackBufferConfig {
        val base = if (!isTelevision) {
            NativePlaybackBufferConfig(
                minBufferMs = 50_000,
                maxBufferMs = 120_000,
                bufferForPlaybackMs = 2_500,
                bufferForPlaybackAfterRebufferMs = 5_000,
                targetBufferBytes = -1,
                prioritizeTimeOverSizeThresholds = true,
            )
        } else when {
            memoryClassMb <= 256 -> NativePlaybackBufferConfig(
                minBufferMs = 20_000,
                maxBufferMs = 120_000,
                bufferForPlaybackMs = 1_500,
                bufferForPlaybackAfterRebufferMs = 2_000,
                targetBufferBytes = 64 * MEBIBYTE,
                prioritizeTimeOverSizeThresholds = false,
            )

            memoryClassMb <= 512 -> NativePlaybackBufferConfig(
                minBufferMs = 30_000,
                maxBufferMs = 120_000,
                bufferForPlaybackMs = 2_000,
                bufferForPlaybackAfterRebufferMs = 2_000,
                targetBufferBytes = (if (isHeavyPlayback) 112 else 96) * MEBIBYTE,
                prioritizeTimeOverSizeThresholds = false,
            )

            else -> NativePlaybackBufferConfig(
                minBufferMs = 45_000,
                maxBufferMs = 120_000,
                bufferForPlaybackMs = 2_500,
                bufferForPlaybackAfterRebufferMs = 2_000,
                targetBufferBytes = 160 * MEBIBYTE,
                prioritizeTimeOverSizeThresholds = false,
            )
        }

        val bandwidthAdjusted = if (
            cachedBandwidthBytesPerSecond <= 0L || sourceBitrate <= 0L
        ) {
            base
        } else {
            val bandwidthRatio = (cachedBandwidthBytesPerSecond * 8.0) / sourceBitrate
            when {
                bandwidthRatio >= 2.5 -> base.copy(
                    bufferForPlaybackMs = minOf(base.bufferForPlaybackMs, 1_200),
                    bufferForPlaybackAfterRebufferMs = minOf(
                        base.bufferForPlaybackAfterRebufferMs,
                        if (isTelevision) 1_500 else 3_500,
                    ),
                    bandwidthProfile = "fast",
                )
                bandwidthRatio < 1.25 -> base.copy(
                    bufferForPlaybackMs = minOf(
                        base.minBufferMs,
                        base.bufferForPlaybackMs + 500,
                    ),
                    bufferForPlaybackAfterRebufferMs = minOf(
                        base.minBufferMs,
                        base.bufferForPlaybackAfterRebufferMs +
                            (if (isTelevision) 1_000 else 2_000),
                    ),
                    bandwidthProfile = "constrained",
                )
                else -> base.copy(bandwidthProfile = "balanced")
            }
        }

        val manualBytes = manualTargetBytes(memoryCacheMiB, memoryClassMb)
        val selected = if (manualBytes > 0) bandwidthAdjusted.copy(
            targetBufferBytes = manualBytes,
            prioritizeTimeOverSizeThresholds = false,
        ) else bandwidthAdjusted
        if (!isTelevision || !isRemoteEpisodeSwitch) return selected
        val episodeTargetBufferBytes = when {
            memoryClassMb <= 256 -> 64 * MEBIBYTE
            memoryClassMb <= 512 -> 112 * MEBIBYTE
            else -> 160 * MEBIBYTE
        }
        return selected.copy(
            // Keep read-ahead capacity independent of startup and resume thresholds.
            minBufferMs = maxOf(bandwidthAdjusted.minBufferMs, 30_000),
            targetBufferBytes = if (manualBytes > 0) manualBytes else maxOf(
                bandwidthAdjusted.targetBufferBytes,
                episodeTargetBufferBytes,
            ),
            episodeSwitchWarmup = true,
        )
    }

    fun manualTargetBytes(memoryCacheMiB: Int, memoryClassMb: Int): Int =
        if (memoryCacheMiB in listOf(64, 128, 256, 512))
            minOf(memoryCacheMiB * MEBIBYTE, NativePlaybackBufferBudget.limit(memoryClassMb))
        else 0
}
