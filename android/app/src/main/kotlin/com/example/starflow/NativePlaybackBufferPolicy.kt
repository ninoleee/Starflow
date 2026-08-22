package com.example.starflow

data class NativePlaybackBufferConfig(
    val minBufferMs: Int,
    val maxBufferMs: Int,
    val bufferForPlaybackMs: Int,
    val bufferForPlaybackAfterRebufferMs: Int,
    val targetBufferBytes: Int,
    val prioritizeTimeOverSizeThresholds: Boolean,
)

object NativePlaybackBufferPolicy {
    private const val MEBIBYTE = 1024 * 1024

    fun resolve(
        isTelevision: Boolean,
        memoryClassMb: Int,
        isHeavyPlayback: Boolean,
    ): NativePlaybackBufferConfig {
        if (!isTelevision) {
            return NativePlaybackBufferConfig(
                minBufferMs = 50_000,
                maxBufferMs = 90_000,
                bufferForPlaybackMs = 2_500,
                bufferForPlaybackAfterRebufferMs = 5_000,
                targetBufferBytes = -1,
                prioritizeTimeOverSizeThresholds = true,
            )
        }

        return when {
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
    }
}
