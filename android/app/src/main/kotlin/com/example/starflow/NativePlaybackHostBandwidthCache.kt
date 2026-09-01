package com.example.starflow

import android.os.SystemClock

class NativePlaybackHostBandwidthCache(
    private val ttlMs: Long = 10 * 60 * 1_000L,
    private val clock: () -> Long = SystemClock::elapsedRealtime,
) {
    private data class Entry(
        val bytesPerSecond: Long,
        val recordedAtMs: Long,
    )

    private val entries = mutableMapOf<String, Entry>()

    fun record(host: String, bytesPerSecond: Long) {
        val key = host.trim().lowercase()
        if (key.isEmpty() || bytesPerSecond <= 0L) return
        val now = clock()
        val previous = entries[key]
        val smoothedBytesPerSecond = if (
            previous == null || now - previous.recordedAtMs > ttlMs
        ) {
            bytesPerSecond
        } else {
            ((previous.bytesPerSecond * 3L) + bytesPerSecond) / 4L
        }
        entries[key] = Entry(smoothedBytesPerSecond, now)
    }

    fun resolve(host: String): Long {
        val key = host.trim().lowercase()
        if (key.isEmpty()) return 0L
        val entry = entries[key] ?: return 0L
        if (clock() - entry.recordedAtMs > ttlMs) {
            entries.remove(key)
            return 0L
        }
        return entry.bytesPerSecond
    }
}
