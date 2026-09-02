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
    ): NativePlaybackBufferConfig {
        val base = if (!isTelevision) {
            NativePlaybackBufferConfig(
                minBufferMs = 50_000,
                maxBufferMs = 90_000,
                bufferForPlaybackMs = 2_500,
                bufferForPlaybackAfterRebufferMs = 5_000,
                targetBufferBytes = -1,
                prioritizeTimeOverSizeThresholds = true,
            )
        } else when {
            memoryClassMb <= 256 -> NativePlaybackBufferConfig(
                minBufferMs = 20_000,
                maxBufferMs = 60_000,
                bufferForPlaybackMs = 1_500,
                bufferForPlaybackAfterRebufferMs = 4_000,
                targetBufferBytes = (if (isHeavyPlayback) 48 else 32) * MEBIBYTE,
                prioritizeTimeOverSizeThresholds = false,
            )

            memoryClassMb <= 512 -> NativePlaybackBufferConfig(
                minBufferMs = 30_000,
                maxBufferMs = 90_000,
                bufferForPlaybackMs = 2_000,
                bufferForPlaybackAfterRebufferMs = 6_000,
                targetBufferBytes = (if (isHeavyPlayback) 80 else 64) * MEBIBYTE,
                prioritizeTimeOverSizeThresholds = false,
            )

            else -> NativePlaybackBufferConfig(
                minBufferMs = 45_000,
                maxBufferMs = 120_000,
                bufferForPlaybackMs = 2_500,
                bufferForPlaybackAfterRebufferMs = 8_000,
                targetBufferBytes = (if (isHeavyPlayback) 128 else 96) * MEBIBYTE,
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
                        3_500,
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
                        base.bufferForPlaybackAfterRebufferMs + 2_000,
                    ),
                    bandwidthProfile = "constrained",
                )
                else -> base.copy(bandwidthProfile = "balanced")
            }
        }

        if (!isTelevision || !isRemoteEpisodeSwitch) {
            return bandwidthAdjusted
        }
        val episodeTargetBufferBytes = when {
            memoryClassMb <= 256 -> 48 * MEBIBYTE
            memoryClassMb <= 512 -> 80 * MEBIBYTE
            else -> 96 * MEBIBYTE
        }
        return bandwidthAdjusted.copy(
            minBufferMs = maxOf(bandwidthAdjusted.minBufferMs, 30_000),
            bufferForPlaybackMs = maxOf(
                bandwidthAdjusted.bufferForPlaybackMs,
                6_000,
            ),
            bufferForPlaybackAfterRebufferMs = maxOf(
                bandwidthAdjusted.bufferForPlaybackAfterRebufferMs,
                12_000,
            ),
            targetBufferBytes = maxOf(
                bandwidthAdjusted.targetBufferBytes,
                episodeTargetBufferBytes,
            ),
            episodeSwitchWarmup = true,
        )
    }
}
