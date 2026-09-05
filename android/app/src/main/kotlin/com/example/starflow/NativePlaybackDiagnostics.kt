package com.example.starflow

import android.app.Activity
import android.net.Uri
import android.os.SystemClock
import android.view.View
import android.widget.TextView
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.upstream.BandwidthMeter
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_URL
import java.util.Locale
import org.json.JSONObject

internal class NativePlaybackDiagnostics(private val host: Host) {
    interface Host {
        val session: NativePlaybackSession
        val target: NativePlaybackTarget
        val activity: Activity
    }

    var latestNetworkBytesPerSecond = 0L

    var latestNetworkSampleAtMs = 0L

    var networkSpeedVisible = false

    var bandwidthWarningShown = false

    val playbackPerformanceTracker = NativePlaybackPerformanceTracker()

    val playbackHostBandwidthCache = NativePlaybackHostBandwidthCache()

    var playbackFirstFrameRendered = false

    var playbackLastRuntimeLogAtMs = 0L

    val bandwidthEventListener =
        BandwidthMeter.EventListener { elapsedMs, bytesTransferred, bitrateEstimate ->
            latestNetworkBytesPerSecond =
                when {
                    elapsedMs > 0 && bytesTransferred > 0L ->
                        (bytesTransferred * 1_000L / elapsedMs).coerceAtLeast(0L)
                    bitrateEstimate > 0L -> bitrateEstimate / 8L
                    else -> 0L
                }
            latestNetworkSampleAtMs = SystemClock.elapsedRealtime()
            playbackPerformanceTracker.onBandwidthSample(latestNetworkBytesPerSecond)
            playbackHostBandwidthCache.record(currentPlaybackHost(), latestNetworkBytesPerSecond)
            updateNetworkSpeedLabelIfVisible()
        }

    val playbackPerformanceAnalyticsListener =
        object : AnalyticsListener {
            override fun onVideoDecoderInitialized(
                eventTime: AnalyticsListener.EventTime,
                decoderName: String,
                initializedTimestampMs: Long,
                initializationDurationMs: Long,
            ) {
                playbackPerformanceTracker.onVideoDecoder(decoderName)
            }

            override fun onAudioDecoderInitialized(
                eventTime: AnalyticsListener.EventTime,
                decoderName: String,
                initializedTimestampMs: Long,
                initializationDurationMs: Long,
            ) {
                playbackPerformanceTracker.onAudioDecoder(decoderName)
            }

            override fun onDroppedVideoFrames(
                eventTime: AnalyticsListener.EventTime,
                droppedFrames: Int,
                elapsedMs: Long,
            ) {
                playbackPerformanceTracker.onDroppedVideoFrames(droppedFrames)
            }

            override fun onAudioUnderrun(
                eventTime: AnalyticsListener.EventTime,
                bufferSize: Int,
                bufferSizeMs: Long,
                elapsedSinceLastFeedMs: Long,
            ) {
                playbackPerformanceTracker.onAudioUnderrun()
            }
        }

    fun logAudioTracks(tracks: Tracks) {
        val groups = tracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO }
        if (groups.isEmpty()) {
            NativePlaybackFormatting.logPlayback("native.audio.tracks none")
            return
        }
        val summaries =
            groups.flatMapIndexed { groupIndex, group ->
                (0 until group.length).map { trackIndex ->
                    val format = group.getTrackFormat(trackIndex)
                    "g$groupIndex:t$trackIndex" +
                        ":mime=${format.sampleMimeType ?: "-"}" +
                        ":codecs=${format.codecs ?: "-"}" +
                        ":channels=${format.channelCount}" +
                        ":rate=${format.sampleRate}" +
                        ":language=${format.language ?: "-"}" +
                        ":supported=${group.isTrackSupported(trackIndex)}" +
                        ":selected=${group.isTrackSelected(trackIndex)}"
                }
            }
        NativePlaybackFormatting.logPlayback("native.audio.tracks ${summaries.joinToString("|")}")
    }

    fun logVideoTracks(tracks: Tracks) {
        val groups = tracks.groups.filter { it.type == C.TRACK_TYPE_VIDEO }
        if (groups.isEmpty()) {
            NativePlaybackFormatting.logPlayback("native.video.tracks none")
            return
        }
        val summaries =
            groups.flatMapIndexed { groupIndex, group ->
                (0 until group.length).map { trackIndex ->
                    val format = group.getTrackFormat(trackIndex)
                    "g$groupIndex:t$trackIndex" +
                        ":mime=${format.sampleMimeType ?: "-"}" +
                        ":codecs=${format.codecs ?: "-"}" +
                        ":width=${format.width}" +
                        ":height=${format.height}" +
                        ":color=${format.colorInfo?.toString() ?: "-"}" +
                        ":supported=${group.isTrackSupported(trackIndex)}" +
                        ":selected=${group.isTrackSelected(trackIndex)}"
                }
            }
        NativePlaybackFormatting.logPlayback("native.video.tracks ${summaries.joinToString("|")}")
    }

    fun logPlaybackRuntimeIfNeeded() {
        val currentPlayer = host.session.player ?: return
        if (!currentPlayer.playWhenReady && currentPlayer.playbackState != Player.STATE_BUFFERING) {
            return
        }
        val nowMs = SystemClock.elapsedRealtime()
        if (nowMs - playbackLastRuntimeLogAtMs < PLAYBACK_RUNTIME_LOG_INTERVAL_MS) {
            return
        }
        logPlaybackRuntime(reason = "sample")
    }

    fun logPlaybackRuntime(reason: String) {
        val currentPlayer = host.session.player ?: return
        playbackLastRuntimeLogAtMs = SystemClock.elapsedRealtime()
        val videoSize = currentPlayer.videoSize
        NativePlaybackFormatting.logPlayback(
            "native.playback.runtime reason=$reason " +
                "state=${NativePlaybackFormatting.playbackStateLabel(currentPlayer.playbackState)} " +
                "positionMs=${currentPlayer.currentPosition.coerceAtLeast(0L)} " +
                "durationMs=${currentPlayer.duration.takeIf { it > 0L } ?: 0L} " +
                "bufferedPositionMs=${currentPlayer.bufferedPosition.coerceAtLeast(0L)} " +
                "bufferedPercentage=${currentPlayer.bufferedPercentage.coerceIn(0, 100)} " +
                "playing=${currentPlayer.isPlaying} " +
                "playWhenReady=${currentPlayer.playWhenReady} " +
                "firstFrame=$playbackFirstFrameRendered " +
                "videoSize=${videoSize.width}x${videoSize.height}"
        )
    }

    fun updateNetworkSpeedLabelIfVisible() {
        if (!networkSpeedVisible) {
            return
        }
        val label = host.activity.findViewById<TextView?>(R.id.native_network_speed) ?: return
        label.text = resolveNetworkSpeedText()
        label.visibility = View.VISIBLE
    }

    private fun resolveNetworkSpeedText(): String {
        // No sample has arrived yet (startup, before the first transfer
        // completes). Reporting 0 B/s there reads as "the download is dead",
        // so say the speed is still being measured instead.
        if (latestNetworkSampleAtMs == 0L) {
            return host.activity.getString(R.string.native_network_speed_probing)
        }
        val sampleIsFresh =
            SystemClock.elapsedRealtime() - latestNetworkSampleAtMs <= NETWORK_SPEED_STALE_AFTER_MS
        if (sampleIsFresh) {
            return NativePlaybackFormatting.formatNetworkSpeed(latestNetworkBytesPerSecond)
        }
        // Bandwidth samples arrive per finished transfer, which on a long-lived
        // progressive stream is often further apart than the staleness window.
        // Fall back to the meter's running estimate rather than dropping to 0.
        val estimatedBytesPerSecond =
            host.session.playbackBandwidthMeter?.bitrateEstimate?.takeIf { it > 0L }?.div(8L)
        return NativePlaybackFormatting.formatNetworkSpeed(
            estimatedBytesPerSecond ?: latestNetworkBytesPerSecond
        )
    }

    fun currentPlaybackHost(): String {
        val rawUrl = host.activity.intent.getStringExtra(EXTRA_URL)?.trim().orEmpty()
        return try {
            Uri.parse(rawUrl).host?.trim().orEmpty()
        } catch (_: Throwable) {
            ""
        }
    }

    fun beginPlaybackPerformanceSession() {
        val targetObject =
            try {
                JSONObject(host.target.playbackTargetJson)
            } catch (_: Throwable) {
                JSONObject()
            }
        playbackPerformanceTracker.begin(sourceBitrate = targetObject.optLong("bitrate", 0L))
        bandwidthWarningShown = false
    }

    fun isCurrentBandwidthInsufficient(): Boolean {
        val bitrate = host.target.decodePlaybackTargetObject().optLong("bitrate", 0L)
        val bytesPerSecond = playbackHostBandwidthCache.resolve(currentPlaybackHost())
        return bitrate > 0L && bytesPerSecond > 0L && bytesPerSecond * 8 < bitrate * 0.9
    }

    fun finishPlaybackPerformanceSession(reason: String) {
        val summary = playbackPerformanceTracker.finish(reason) ?: return
        NativeAppLogger.info(
            "playback.performance",
            "Playback session completed engine=exo " +
                "reason=${summary.reason} " +
                "sessionMs=${summary.sessionDurationMs} " +
                "firstFrameMs=${summary.firstFrameMs} " +
                "bufferingCount=${summary.bufferingCount} " +
                "bufferingMs=${summary.bufferingDurationMs} " +
                "recoveries=${summary.recoveryCount} " +
                "droppedFrames=${summary.droppedVideoFrames} " +
                "audioUnderruns=${summary.audioUnderrunCount} " +
                "avgBytesPerSecond=${summary.averageNetworkBytesPerSecond} " +
                "minBytesPerSecond=${summary.minimumNetworkBytesPerSecond} " +
                "maxBytesPerSecond=${summary.maximumNetworkBytesPerSecond} " +
                "sourceBitrate=${summary.sourceBitrate} " +
                "bandwidthRatio=${summary.bandwidthToBitrateRatio?.let {
                    String.format(Locale.US, "%.2f", it)
                } ?: "-"} " +
                "videoDecoder=${summary.videoDecoder.ifBlank { "-" }} " +
                "audioDecoder=${summary.audioDecoder.ifBlank { "-" }} " +
                "targetBufferBytes=${summary.targetBufferBytes} " +
                "memoryClassMb=${summary.memoryClassMb}",
        )
    }
}
