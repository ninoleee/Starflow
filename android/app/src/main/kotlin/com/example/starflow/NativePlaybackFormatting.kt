package com.example.starflow

import androidx.media3.common.Player
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.json.JSONObject

internal object NativePlaybackFormatting {
    fun formatSubtitleScaleLabel(value: Double): String {
        return "${value.toInt()}号"
    }

    fun formatSubtitlePercentLabel(value: Double): String {
        return "${value.toInt()}%"
    }

    fun formatPlaybackSpeedLabel(value: Float): String {
        val normalized =
            if (value == value.toInt().toFloat()) {
                "${value.toInt()}.0"
            } else {
                String.format(Locale.US, "%.2f", value).trimEnd('0').trimEnd('.')
            }
        return "${normalized}x"
    }

    fun formatNetworkSpeed(bytesPerSecond: Long): String {
        val safeValue = bytesPerSecond.coerceAtLeast(0L)
        return when {
            safeValue >= 1024L * 1024L ->
                String.format(Locale.US, "%.1f MB/s", safeValue / (1024.0 * 1024.0))
            safeValue >= 1024L -> String.format(Locale.US, "%.0f KB/s", safeValue / 1024.0)
            else -> "$safeValue B/s"
        }
    }

    fun formatClockDuration(valueMs: Long): String {
        val totalSeconds = valueMs / 1_000L
        val hours = totalSeconds / 3_600L
        val minutes = (totalSeconds % 3_600L) / 60L
        val seconds = totalSeconds % 60L
        return if (hours > 0L) {
            String.format(Locale.US, "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format(Locale.US, "%d:%02d", minutes, seconds)
        }
    }

    fun formatSubtitleDelayLabel(valueMs: Long): String {
        if (valueMs == 0L) {
            return "0s"
        }
        val seconds = valueMs / 1_000.0
        val formatted =
            if (seconds == seconds.toLong().toDouble()) {
                seconds.toLong().toString()
            } else {
                String.format(Locale.US, "%.1f", seconds).trimEnd('0').trimEnd('.')
            }
        return if (valueMs > 0L) "+${formatted}s" else "${formatted}s"
    }

    fun formatEpisodeSelectionLabel(index: Int, entry: NativeEpisodeQueueEntry): String {
        val targetObject =
            try {
                JSONObject(entry.playbackTargetJson)
            } catch (_: Throwable) {
                JSONObject()
            }
        val title = entry.title().ifBlank { "第 ${index + 1} 集" }
        val seasonNumber = targetObject.optInt("seasonNumber", 0)
        val episodeNumber = targetObject.optInt("episodeNumber", 0)
        if (seasonNumber > 0 && episodeNumber > 0) {
            return "S${seasonNumber.toString().padStart(2, '0')}" +
                "E${episodeNumber.toString().padStart(2, '0')} · $title"
        }
        if (episodeNumber > 0) {
            return "第 $episodeNumber 集 · $title"
        }
        return title
    }

    fun isoNow(): String {
        val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        formatter.timeZone = TimeZone.getTimeZone("UTC")
        return formatter.format(Date())
    }

    fun logPlayback(message: String, error: Throwable? = null) {
        if (error == null) {
            NativeAppLogger.info("native.playback", message)
        } else {
            NativeAppLogger.error("native.playback", message, error)
        }
    }

    fun playbackStateLabel(playbackState: Int): String {
        return when (playbackState) {
            Player.STATE_IDLE -> "IDLE"
            Player.STATE_BUFFERING -> "BUFFERING"
            Player.STATE_READY -> "READY"
            Player.STATE_ENDED -> "ENDED"
            else -> playbackState.toString()
        }
    }
}
