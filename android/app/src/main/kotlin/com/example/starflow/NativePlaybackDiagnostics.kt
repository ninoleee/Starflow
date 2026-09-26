package com.example.starflow

import android.app.Activity
import android.net.Uri
import android.os.SystemClock
import android.os.Build
import android.os.PowerManager
import android.view.View
import android.widget.TextView
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.exoplayer.DecoderReuseEvaluation
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.text.CueGroup
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.upstream.BandwidthMeter
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_URL
import java.util.Locale
import java.util.concurrent.atomic.AtomicLong
import org.json.JSONObject

internal class NativePlaybackDiagnostics(
    private val host: Host,
    private val invokeResolver: (String, Map<String, Any?>, (Map<String, Any?>) -> Unit) -> Unit =
        MainActivity::invokeNativeFntv,
    private val now: () -> Long = SystemClock::elapsedRealtime,
) {
    private companion object {
        // Activity recreation may retain the Flutter resolver session.
        val nextCacheGeneration = AtomicLong()
    }

    interface Host {
        val session: NativePlaybackSession
        val target: NativePlaybackTarget
        val activity: Activity
    }

    var latestNetworkBytesPerSecond = 0L

    var latestNetworkSampleAtMs = 0L

    var networkSpeedVisible = false
        set(value) {
            if (field != value) invalidateCacheSample()
            field = value
        }

    var displayActive = true
        set(value) {
            if (field != value) invalidateCacheSample()
            field = value
        }

    private var cacheGeneration = 0L
    private var cacheSession = ""
    private var cacheURL = ""
    private var cacheSampleAt: Long? = null
    private var pendingCacheGeneration: Long? = null
    private var bufferPlayer: Player? = null
    private var bufferReportedAt: Long? = null
    private var bufferReportedReady = false
    internal var relayStoredBytes: Long? = null
        private set

    private fun invalidateCacheSample() {
        cacheGeneration = nextCacheGeneration.incrementAndGet()
        pendingCacheGeneration = null
        cacheSampleAt = null
        relayStoredBytes = null
    }

    fun beginCacheTransport(url: String, active: Boolean) {
        if (cacheURL.isNotBlank()) reportMemoryBufferState(forceNotReady = true, force = true)
        cacheSession = host.target.resolverSessionId
        cacheURL = url
        bufferPlayer = host.session.player
        bufferReportedAt = null
        invalidateCacheSample()
        setPlaybackActive(active)
        reportMemoryBufferState(forceNotReady = true, force = true)
    }

    fun endCacheTransport() {
        reportMemoryBufferState(forceNotReady = true, force = true)
        setPlaybackActive(false)
        cancelReadAhead()
        cacheURL = ""
        cacheSession = ""
        bufferPlayer = null
        bufferReportedAt = null
        invalidateCacheSample()
    }

    // Independent of diagnostics visibility. Main expires this readiness lease after four seconds.
    internal fun reportMemoryBufferState(forceNotReady: Boolean = false, force: Boolean = false) {
        if (cacheURL.isBlank() || cacheSession.isBlank()) return
        val timestamp = now()
        val ready = !forceNotReady && bufferPlayer != null &&
            bufferPlayer === host.session.player && host.session.isMemoryBufferReady()
        val age = bufferReportedAt?.let { timestamp - it }
        if (!force && ready == bufferReportedReady && age != null && age in 0 until 1_000L) return
        bufferReportedReady = ready
        bufferReportedAt = timestamp
        // Do not invalidate the separate UI snapshot or consume any asynchronous reply.
        val args = cacheArguments() + mapOf(
            "generation" to nextCacheGeneration.incrementAndGet(), "memoryReady" to ready,
        )
        invokeResolver("setNativePlaybackBufferState", args) {}
    }

    private fun cacheArguments(): Map<String, Any?> = mapOf(
        "resolverSessionId" to cacheSession,
        "currentURL" to cacheURL,
        "generation" to cacheGeneration,
    )

    fun setPlaybackActive(active: Boolean) {
        if (cacheURL.isBlank() || cacheSession.isBlank()) return
        invalidateCacheSample()
        invokeResolver("setNativePlaybackActive", cacheArguments() + ("active" to active)) {}
    }

    fun cancelReadAhead() {
        if (cacheURL.isBlank() || cacheSession.isBlank()) return
        invalidateCacheSample()
        invokeResolver("cancelNativePlaybackReadAhead", cacheArguments()) {}
    }

    internal fun sampleRelayCacheIfVisible() {
        if (!networkSpeedVisible || !displayActive || cacheURL.isBlank() || cacheSession.isBlank()) return
        val timestamp = now()
        if (cacheSampleAt?.let { timestamp - it < 2_000L } == true) return
        if (pendingCacheGeneration != null) invalidateCacheSample()
        cacheSampleAt = timestamp
        val generation = nextCacheGeneration.incrementAndGet()
        cacheGeneration = generation
        val args = cacheArguments()
        pendingCacheGeneration = generation
        invokeResolver("nativePlaybackCacheSnapshot", args) { result ->
            if (pendingCacheGeneration != generation) return@invokeResolver
            if (pendingCacheGeneration == generation) pendingCacheGeneration = null
            if (!networkSpeedVisible || !displayActive || generation != cacheGeneration) return@invokeResolver
            relayStoredBytes = null
            if (now() - timestamp >= 2_000L) {
                invalidateCacheSample()
                return@invokeResolver
            }
            if (result["resolverSessionId"] != cacheSession || result["currentURL"] != cacheURL ||
                (result["generation"] as? Number)?.toLong() != generation) return@invokeResolver
            relayStoredBytes = if (result["ok"] == true)
                (result["storedBytes"] as? Number)?.toLong()?.takeIf { it >= 0L } else null
        }
    }

    var bandwidthWarningShown = false

    val playbackPerformanceTracker = NativePlaybackPerformanceTracker()

    val playbackHostBandwidthCache = NativePlaybackHostBandwidthCache()

    var playbackFirstFrameRendered = false
    var awaitingVideoFrameAfterSeek = false

    var playbackLastRuntimeLogAtMs = 0L
    var subtitleLastCueLogAtMs = -1L
    private var lastAudioTracks = ""
    private val healthPolicy = NativePlaybackHealthPolicy()
    private var currentVideoDecoder = ""
    private var currentAudioDecoder = ""

    fun logPlaybackHealth(reason: String, eventCount: Int = 0) {
        val current = host.session.player ?: return
        if (!healthPolicy.admit(reason, SystemClock.elapsedRealtime())) return
        val bufferMs = current.totalBufferedDuration.coerceAtLeast(0L)
        val transfer = host.session.playbackTransferProgress
        val buffering = current.playbackState == Player.STATE_BUFFERING
        val reading = transfer?.isNetworkTransferActive == true
        NativeAppLogger.info("playback.health", "Playback health engine=exo reason=$reason " +
            "signal=${NativePlaybackHealthPolicy.classify(bufferMs, reading, buffering)} " +
            "eventCount=$eventCount positionMs=${current.currentPosition.coerceAtLeast(0)} " +
            "bufferedMs=$bufferMs cacheBytes=${host.session.cachedMediaBytes ?: -1} " +
            "targetBytes=${host.session.bufferTargetBytes ?: -1} loading=${current.isLoading} " +
            "reading=$reading bytesPerSecond=${transfer?.rawBytesPerSecond ?: -1} " +
            "speed=${current.playbackParameters.speed} " +
            "videoDecoder=${currentVideoDecoder.ifBlank { "unknown" }} " +
            "audioDecoder=${currentAudioDecoder.ifBlank { "unknown" }} " +
            "frameRate=${current.videoFormat?.frameRate ?: -1} " +
            "thermalStatus=${thermalStatus()} " +
            "width=${current.videoSize.width} height=${current.videoSize.height}")
    }

    private fun thermalStatus(): Int = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            (host.activity.getSystemService(Activity.POWER_SERVICE) as? PowerManager)
                ?.currentThermalStatus ?: -1
        } else -1
    } catch (_: RuntimeException) { -1 }

    fun logSubtitleCues(cueGroup: CueGroup) {
        if (cueGroup.cues.isEmpty()) return
        val now = SystemClock.elapsedRealtime()
        val positionMs = host.session.player?.currentPosition ?: 0L
        val lagMs = if (cueGroup.presentationTimeUs == C.TIME_UNSET) null
            else positionMs - cueGroup.presentationTimeUs / 1_000L
        val intervalMs = if (lagMs != null && lagMs > 1_000L) 5_000L else 30_000L
        if (subtitleLastCueLogAtMs >= 0 && now - subtitleLastCueLogAtMs < intervalMs) return
        subtitleLastCueLogAtMs = now
        NativePlaybackFormatting.logPlayback(
            "native.subtitle.cues count=${cueGroup.cues.size} " +
                "bitmapCount=${cueGroup.cues.count { it.bitmap != null }} " +
                "presentationTimeUs=${cueGroup.presentationTimeUs} " +
                "positionMs=$positionMs lagMs=${lagMs ?: "unknown"}",
        )
    }

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
                currentVideoDecoder = decoderName
                logPlaybackHealth("video-decoder")
            }

            override fun onAudioDecoderInitialized(
                eventTime: AnalyticsListener.EventTime,
                decoderName: String,
                initializedTimestampMs: Long,
                initializationDurationMs: Long,
            ) {
                playbackPerformanceTracker.onAudioDecoder(decoderName)
                currentAudioDecoder = decoderName
                NativeAppLogger.info("playback.audio", "Audio decoder initialized name=$decoderName durationMs=$initializationDurationMs")
            }

            override fun onAudioTrackInitialized(eventTime: AnalyticsListener.EventTime, config: AudioSink.AudioTrackConfig) {
                NativeAppLogger.info("playback.audio", "Audio output initialized encoding=${config.encoding} " +
                    "format=${NativePlaybackAudioPolicy.encodingLabel(config.encoding)} " +
                    "sampleRate=${config.sampleRate} channelMask=${config.channelConfig} " +
                    "offload=${config.offload} tunneling=${config.tunneling} bufferBytes=${config.bufferSize}")
            }

            override fun onAudioInputFormatChanged(
                eventTime: AnalyticsListener.EventTime,
                format: Format,
                decoderReuseEvaluation: DecoderReuseEvaluation?,
            ) {
                NativeAppLogger.info("playback.audio", "Audio input mime=${format.sampleMimeType} " +
                    "pcmEncoding=${format.pcmEncoding} format=${NativePlaybackAudioPolicy.encodingLabel(format.pcmEncoding)} " +
                    "sampleRate=${format.sampleRate} channels=${format.channelCount}")
            }

            override fun onAudioCodecError(eventTime: AnalyticsListener.EventTime, error: Exception) {
                NativeAppLogger.warning("playback.audio", "Audio decoder error type=${error.javaClass.simpleName}")
            }

            override fun onAudioSinkError(eventTime: AnalyticsListener.EventTime, error: Exception) {
                NativeAppLogger.warning("playback.audio", "Audio output error type=${error.javaClass.simpleName}")
            }

            override fun onDroppedVideoFrames(
                eventTime: AnalyticsListener.EventTime,
                droppedFrames: Int,
                elapsedMs: Long,
            ) {
                playbackPerformanceTracker.onDroppedVideoFrames(droppedFrames)
                logPlaybackHealth("dropped-frames", droppedFrames)
            }

            override fun onAudioUnderrun(
                eventTime: AnalyticsListener.EventTime,
                bufferSize: Int,
                bufferSizeMs: Long,
                elapsedSinceLastFeedMs: Long,
            ) {
                playbackPerformanceTracker.onAudioUnderrun()
                logPlaybackHealth("audio-underrun", 1)
            }
        }

    fun logAudioTracks(tracks: Tracks) {
        val groups = tracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO }
        if (groups.isEmpty()) {
            if (lastAudioTracks != "none") NativePlaybackFormatting.logPlayback("native.audio.tracks none")
            lastAudioTracks = "none"
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
        val summary = summaries.joinToString("|")
        if (summary == lastAudioTracks) return
        lastAudioTracks = summary
        NativePlaybackFormatting.logPlayback("native.audio.tracks $summary")
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

    fun logSubtitleTracks(tracks: Tracks) {
        val groups = tracks.groups.filter { it.type == C.TRACK_TYPE_TEXT }
        if (groups.isEmpty()) {
            NativePlaybackFormatting.logPlayback("native.subtitle.tracks none")
            return
        }
        val summaries =
            groups.flatMapIndexed { groupIndex, group ->
                (0 until group.length).map { trackIndex ->
                    val format = group.getTrackFormat(trackIndex)
                    "g$groupIndex:t$trackIndex" +
                        ":mime=${format.sampleMimeType ?: "-"}" +
                        ":codecs=${format.codecs ?: "-"}" +
                        ":language=${format.language ?: "-"}" +
                        ":roleFlags=${format.roleFlags}" +
                        ":supported=${group.isTrackSupported(trackIndex)}" +
                        ":selected=${group.isTrackSelected(trackIndex)}"
                }
            }
        NativePlaybackFormatting.logPlayback(
            "native.subtitle.tracks ${summaries.joinToString("|")}",
        )
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
                "awaitingVideoFrameAfterSeek=$awaitingVideoFrameAfterSeek " +
                "videoSize=${videoSize.width}x${videoSize.height}"
        )
    }

    fun updateNetworkSpeedLabelIfVisible() {
        if (!networkSpeedVisible || !displayActive) {
            return
        }
        sampleRelayCacheIfVisible()
        val label = host.activity.findViewById<TextView?>(R.id.native_network_speed) ?: return
        val current = host.session.player
        val bufferDurationMs = current?.let {
            (it.bufferedPosition - it.currentPosition).coerceAtLeast(0L)
        }
        val text = listOf(
            NativePlaybackFormatting.formatNetworkSpeed(host.session.playbackTransferProgress?.networkBytesPerSecond),
            NativePlaybackFormatting.formatCacheBytes(host.session.cachedMediaBytes) + " | " +
                NativePlaybackFormatting.formatCacheBytes(relayStoredBytes),
            NativePlaybackFormatting.formatBufferDuration(bufferDurationMs),
        ).joinToString(" · ") + "\n" + (NativePlaybackFormatting.formatVideoFormat(
            current?.videoFormat, current?.audioFormat,
        ) ?: "识别中")
        if (label.text.toString() != text) label.text = text
        label.visibility = View.VISIBLE
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
        lastAudioTracks = ""
        healthPolicy.reset()
        currentVideoDecoder = ""
        currentAudioDecoder = ""
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
