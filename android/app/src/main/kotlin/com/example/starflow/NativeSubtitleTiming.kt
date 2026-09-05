package com.example.starflow

import androidx.media3.common.MimeTypes
import java.util.Locale

internal object NativeSubtitleTiming {
    fun shiftSubtitleContent(content: String, mimeType: String, delayMs: Long): String {
        return when (mimeType) {
            MimeTypes.APPLICATION_SUBRIP -> shiftSubRip(content, delayMs)
            MimeTypes.TEXT_VTT -> shiftWebVtt(content, delayMs)
            MimeTypes.TEXT_SSA -> shiftAssSsa(content, delayMs)
            else -> content
        }
    }

    fun shiftSubRip(content: String, delayMs: Long): String {
        val regex = Regex("(\\d{2}:\\d{2}:\\d{2},\\d{3})\\s-->\\s(\\d{2}:\\d{2}:\\d{2},\\d{3})")
        return regex.replace(content) { match ->
            val startMs = parseSubRipTimestamp(match.groupValues[1])
            val endMs = parseSubRipTimestamp(match.groupValues[2])
            val shiftedStart = shiftTimestamp(startMs, delayMs)
            val shiftedEnd = shiftTimestamp(endMs, delayMs, minimum = shiftedStart)
            "${formatSubRipTimestamp(shiftedStart)} --> ${formatSubRipTimestamp(shiftedEnd)}"
        }
    }

    fun shiftWebVtt(content: String, delayMs: Long): String {
        val regex =
            Regex(
                "((?:\\d{2}:)?\\d{2}:\\d{2}\\.\\d{3})\\s-->\\s((?:\\d{2}:)?\\d{2}:\\d{2}\\.\\d{3})(.*)"
            )
        return regex.replace(content) { match ->
            val startMs = parseWebVttTimestamp(match.groupValues[1])
            val endMs = parseWebVttTimestamp(match.groupValues[2])
            val shiftedStart = shiftTimestamp(startMs, delayMs)
            val shiftedEnd = shiftTimestamp(endMs, delayMs, minimum = shiftedStart)
            "${formatWebVttTimestamp(shiftedStart)} --> ${formatWebVttTimestamp(shiftedEnd)}${match.groupValues[3]}"
        }
    }

    fun shiftAssSsa(content: String, delayMs: Long): String {
        val regex = Regex("^(Dialogue:\\s*[^,]*,)([^,]+),([^,]+)(,.*)$", RegexOption.MULTILINE)
        return regex.replace(content) { match ->
            val startMs = parseAssTimestamp(match.groupValues[2])
            val endMs = parseAssTimestamp(match.groupValues[3])
            val shiftedStart = shiftTimestamp(startMs, delayMs)
            val shiftedEnd = shiftTimestamp(endMs, delayMs, minimum = shiftedStart)
            "${match.groupValues[1]}${formatAssTimestamp(shiftedStart)},${formatAssTimestamp(shiftedEnd)}${match.groupValues[4]}"
        }
    }

    fun shiftTimestamp(originalMs: Long, delayMs: Long, minimum: Long = 0L): Long {
        return (originalMs + delayMs).coerceAtLeast(minimum.coerceAtLeast(0L))
    }

    fun parseSubRipTimestamp(value: String): Long {
        val parts = value.split(":", ",")
        if (parts.size != 4) {
            return 0L
        }
        val hours = parts[0].toLongOrNull() ?: 0L
        val minutes = parts[1].toLongOrNull() ?: 0L
        val seconds = parts[2].toLongOrNull() ?: 0L
        val millis = parts[3].toLongOrNull() ?: 0L
        return (((hours * 60 + minutes) * 60) + seconds) * 1_000L + millis
    }

    fun formatSubRipTimestamp(valueMs: Long): String {
        val totalSeconds = valueMs / 1_000L
        val millis = valueMs % 1_000L
        val seconds = totalSeconds % 60L
        val minutes = (totalSeconds / 60L) % 60L
        val hours = totalSeconds / 3_600L
        return String.format(Locale.US, "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }

    fun parseWebVttTimestamp(value: String): Long {
        val parts = value.split(":", ".")
        return when (parts.size) {
            4 -> {
                val hours = parts[0].toLongOrNull() ?: 0L
                val minutes = parts[1].toLongOrNull() ?: 0L
                val seconds = parts[2].toLongOrNull() ?: 0L
                val millis = parts[3].toLongOrNull() ?: 0L
                (((hours * 60 + minutes) * 60) + seconds) * 1_000L + millis
            }

            3 -> {
                val minutes = parts[0].toLongOrNull() ?: 0L
                val seconds = parts[1].toLongOrNull() ?: 0L
                val millis = parts[2].toLongOrNull() ?: 0L
                ((minutes * 60) + seconds) * 1_000L + millis
            }

            else -> 0L
        }
    }

    fun formatWebVttTimestamp(valueMs: Long): String {
        val totalSeconds = valueMs / 1_000L
        val millis = valueMs % 1_000L
        val seconds = totalSeconds % 60L
        val minutes = (totalSeconds / 60L) % 60L
        val hours = totalSeconds / 3_600L
        return if (hours > 0L) {
            String.format(Locale.US, "%02d:%02d:%02d.%03d", hours, minutes, seconds, millis)
        } else {
            String.format(Locale.US, "%02d:%02d.%03d", minutes, seconds, millis)
        }
    }

    fun parseAssTimestamp(value: String): Long {
        val parts = value.trim().split(":", ".")
        if (parts.size != 4) {
            return 0L
        }
        val hours = parts[0].toLongOrNull() ?: 0L
        val minutes = parts[1].toLongOrNull() ?: 0L
        val seconds = parts[2].toLongOrNull() ?: 0L
        val centiseconds = parts[3].toLongOrNull() ?: 0L
        return (((hours * 60 + minutes) * 60) + seconds) * 1_000L + centiseconds * 10L
    }

    fun formatAssTimestamp(valueMs: Long): String {
        val totalSeconds = valueMs / 1_000L
        val centiseconds = (valueMs % 1_000L) / 10L
        val seconds = totalSeconds % 60L
        val minutes = (totalSeconds / 60L) % 60L
        val hours = totalSeconds / 3_600L
        return String.format(Locale.US, "%d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
    }
}
