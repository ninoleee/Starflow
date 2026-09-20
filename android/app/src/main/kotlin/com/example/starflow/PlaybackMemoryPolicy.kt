package com.example.starflow

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

internal object PlaybackMemoryPolicy {
    fun resume(positionMs: Long, durationMs: Long, progress: Double, completed: Boolean): Long {
        if (completed || positionMs < PlaybackPolicyValues.memoryResumeMinimumMs ||
            (durationMs > 0 && durationMs - positionMs <= PlaybackPolicyValues.memoryResumeRemainingMs) ||
            progress >= PlaybackPolicyValues.memoryCompletedPermille / 1000.0) return 0
        return positionMs
    }

    fun completed(positionMs: Long, durationMs: Long, progress: Double): Boolean =
        if (durationMs <= 0) progress >= PlaybackPolicyValues.memoryUnknownCompletedPermille / 1000.0
        else progress >= PlaybackPolicyValues.memoryCompletedPermille / 1000.0 ||
            durationMs - positionMs <= PlaybackPolicyValues.memoryCompletedRemainingMs

    fun timestamp(raw: String): Long {
        val match = Regex("""^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})?$""")
            .matchEntire(raw) ?: return 0
        val fraction = match.groupValues[2].padEnd(3, '0').take(3)
        val zone = match.groupValues[3]
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS" + if (zone.isEmpty()) "" else "Z", Locale.US)
        format.isLenient = false
        val suffix = if (zone == "Z") "+0000" else zone.replace(":", "")
        return runCatching { format.parse("${match.groupValues[1]}.$fraction$suffix")?.time ?: 0 }.getOrDefault(0)
    }

    fun nextTimestamp(now: String, existing: Iterable<String>): String {
        var next = timestamp(now)
        for (raw in existing) next = maxOf(next, timestamp(raw) + 1)
        return formatTimestamp(next)
    }

    fun formatTimestamp(value: Long): String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date(value))
}
