package com.example.starflow

internal class NativePlaybackHealthPolicy {
    private val lastEventAtMs = mutableMapOf<String, Long>()

    fun reset() { lastEventAtMs.clear() }

    fun admit(reason: String, nowMs: Long): Boolean {
        val previous = lastEventAtMs[reason]
        if (previous != null && nowMs - previous < 10_000) return false
        lastEventAtMs[reason] = nowMs
        return true
    }

    companion object {
        fun classify(bufferedMs: Long, reading: Boolean, buffering: Boolean): String = when {
            bufferedMs >= 5_000 -> "buffer-available-check-decode-output"
            buffering && reading -> "buffer-low-reading"
            buffering -> "buffer-low-not-reading"
            else -> "output-event"
        }
    }
}
