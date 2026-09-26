package com.example.starflow

import androidx.media3.common.Player
import androidx.media3.common.C
import androidx.media3.common.Format
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.json.JSONObject

internal object NativePlaybackFormatting {
    fun formatTrackSupport(support: Int): String = when (support) {
        C.FORMAT_HANDLED -> "handled"
        C.FORMAT_EXCEEDS_CAPABILITIES -> "exceeds-capabilities"
        C.FORMAT_UNSUPPORTED_DRM -> "unsupported-drm"
        C.FORMAT_UNSUPPORTED_SUBTYPE -> "unsupported-subtype"
        C.FORMAT_UNSUPPORTED_TYPE -> "unsupported-type"
        else -> "unknown"
    }

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

    fun formatNetworkSpeed(bytesPerSecond: Long?): String {
        val size = formatCacheBytes(bytesPerSecond)
        return if (size == "--") size else "$size/s"
    }

    fun formatCacheBytes(bytes: Long?): String {
        if (bytes == null || bytes < 0L) return "--"
        val units = arrayOf("B", "KB", "MB", "GB")
        var value = bytes.toDouble()
        var unit = 0
        while (value >= 1024 && unit < units.lastIndex) {
            value /= 1024
            unit++
        }
        if (unit > 0 && unit < units.lastIndex && value >= 1023.95) {
            value /= 1024
            unit++
        }
        return String.format(Locale.US, if (unit == 0) "%.0f %s" else "%.1f %s", value, units[unit])
    }

    fun formatBufferDuration(durationMs: Long?): String {
        if (durationMs == null || durationMs < 0L) return "--"
        val totalSeconds = durationMs / 1_000L + if (durationMs % 1_000L >= 500L) 1L else 0L
        return "${totalSeconds}s"
    }

    fun formatPlaybackMetrics(
        bytesPerSecond: Long?,
        cacheBytes: Long?,
        bufferDurationMs: Long?,
    ): String = listOf(
        formatNetworkSpeed(bytesPerSecond),
        formatCacheBytes(cacheBytes),
        formatBufferDuration(bufferDurationMs),
    ).joinToString(" · ")

    fun formatVideoFormat(video: Format?, audio: Format?): String? {
        val parts = buildList {
            if (video != null && video.width > 0 && video.height > 0) {
                add("${video.width}x${video.height}")
            }
            mediaMimeLabel(video?.sampleMimeType)?.let { add(it) }
            mediaMimeLabel(audio?.sampleMimeType)?.let { add(it) }
        }
        return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
    }

    private fun mediaMimeLabel(mime: String?): String? = when (mime) {
        null, "" -> null
        "video/avc" -> "H.264"
        "video/hevc" -> "HEVC"
        "video/av01" -> "AV1"
        "video/x-vnd.on2.vp9" -> "VP9"
        "video/x-vnd.on2.vp8" -> "VP8"
        "video/mpeg2" -> "MPEG-2"
        "video/dolby-vision" -> "Dolby Vision"
        "audio/mp4a-latm" -> "AAC"
        "audio/mpeg" -> "MP3"
        "audio/true-hd" -> "TrueHD"
        "audio/vnd.dts" -> "DTS"
        "audio/vnd.dts.hd" -> "DTS-HD"
        else -> mime.substringAfter('/').uppercase(Locale.ROOT)
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
