package com.example.starflow

import android.os.SystemClock
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.DecoderReuseEvaluation

/** Only numeric and fixed-category telemetry; never log provider labels or exception text. */
internal class LiveTvDiagnostics(
    private val generation: Long,
    private val isActive: () -> Boolean,
    private val clock: () -> Long = SystemClock::elapsedRealtime,
    private val log: (String, Map<String, Any?>) -> Unit = { message, fields ->
        NativeAppLogger.log("info", "live.exo", message, fields)
    },
) : AnalyticsListener {
    private val startedAt = clock()
    private var closed = false
    private var bufferingAt: Long? = null
    private var bufferingMs = 0L
    private var bufferingCount = 0
    private var droppedFrames = 0
    private var audioUnderruns = 0
    private var lastTracks: Map<String, Any?>? = null

    private fun record(message: String, fields: Map<String, Any?> = emptyMap()) {
        if (!closed && isActive()) log(message, mapOf("generation" to generation) + fields)
    }

    fun tracks(tracks: Tracks) {
        if (closed || !isActive()) return
        val audio = tracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO }
        val fields = mapOf<String, Any?>(
            "audioTrackCount" to audio.sumOf { it.length },
            "supportedAudioTrackCount" to audio.sumOf { group ->
                (0 until group.length).count { group.isTrackSupported(it) }
            },
            "selectedAudioTrackCount" to audio.sumOf { group ->
                (0 until group.length).count { group.isTrackSelected(it) }
            },
        )
        if (fields != lastTracks) {
            lastTracks = fields
            record("Live audio tracks changed", fields)
        }
    }

    fun state(player: Player, state: Int) {
        if (closed || !isActive()) return
        if (state == Player.STATE_BUFFERING) {
            if (bufferingAt != null) return
            bufferingAt = clock()
            bufferingCount++
            record("Live buffering started", snapshot(player))
        } else {
            val start = bufferingAt
            if (start != null) {
                val elapsed = (clock() - start).coerceAtLeast(0)
                bufferingMs += elapsed
                bufferingAt = null
                record("Live buffering finished", snapshot(player) + ("bufferingMs" to elapsed))
            }
            if (state == Player.STATE_ENDED) record("Live stream ended", snapshot(player))
        }
    }

    private fun snapshot(player: Player): Map<String, Any?> = mapOf(
        "positionMs" to player.currentPosition,
        "bufferedDurationMs" to player.totalBufferedDuration,
        "durationMs" to player.duration.takeIf { it != C.TIME_UNSET },
        "isLive" to player.isCurrentMediaItemLive,
        "isDynamic" to player.isCurrentMediaItemDynamic,
        "playWhenReady" to player.playWhenReady,
        "volume" to player.volume,
    )

    fun hlsFallback() = record("Live container retry as HLS")

    override fun onAudioInputFormatChanged(
        eventTime: AnalyticsListener.EventTime, format: Format,
        decoderReuseEvaluation: DecoderReuseEvaluation?,
    ) = record("Live audio input", mapOf(
        "audioCodec" to when (format.sampleMimeType) {
            "audio/mp4a-latm" -> "aac"
            "audio/mpeg" -> "mp3"
            "audio/mpeg-L1" -> "mp1"
            "audio/mpeg-L2" -> "mp2"
            "audio/ac3" -> "ac3"
            "audio/eac3", "audio/eac3-joc" -> "eac3"
            "audio/vnd.dts", "audio/vnd.dts.hd" -> "dts"
            "audio/true-hd" -> "truehd"
            "audio/raw" -> "pcm"
            else -> "other"
        },
        "sampleRate" to format.sampleRate, "channelCount" to format.channelCount,
    ))

    override fun onAudioDecoderInitialized(
        eventTime: AnalyticsListener.EventTime, decoderName: String,
        initializedTimestampMs: Long, initializationDurationMs: Long,
    ) = record("Live audio decoder initialized", mapOf(
        "ffmpeg" to decoderName.startsWith("ffmpeg"), "durationMs" to initializationDurationMs,
    ))

    override fun onAudioTrackInitialized(eventTime: AnalyticsListener.EventTime, config: AudioSink.AudioTrackConfig) =
        record("Live audio output initialized", mapOf(
            "encoding" to config.encoding, "sampleRate" to config.sampleRate,
            "channelMask" to config.channelConfig, "offload" to config.offload,
        ))

    override fun onAudioCodecError(eventTime: AnalyticsListener.EventTime, error: Exception) =
        record("Live audio decoder error")

    override fun onAudioSinkError(eventTime: AnalyticsListener.EventTime, error: Exception) =
        record("Live audio output error")

    override fun onDroppedVideoFrames(eventTime: AnalyticsListener.EventTime, droppedFrames: Int, elapsedMs: Long) {
        if (!closed && isActive()) this.droppedFrames += droppedFrames.coerceAtLeast(0)
    }

    override fun onAudioUnderrun(eventTime: AnalyticsListener.EventTime, bufferSize: Int, bufferSizeMs: Long, elapsedSinceLastFeedMs: Long) {
        if (!closed && isActive()) audioUnderruns++
    }

    fun close() {
        if (closed) return
        val now = clock()
        // Terminal events fence the session before release, so the final summary bypasses isActive.
        log("Live session summary", mapOf(
            "generation" to generation, "elapsedMs" to (now - startedAt).coerceAtLeast(0),
            "bufferingCount" to bufferingCount,
            "bufferingMs" to bufferingMs + (bufferingAt?.let { (now - it).coerceAtLeast(0) } ?: 0L),
            "droppedVideoFrames" to droppedFrames, "audioUnderruns" to audioUnderruns,
        ))
        closed = true
    }
}
