package com.example.starflow

import android.app.Activity
import android.app.ActivityManager
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.TextView
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.upstream.DefaultAllocator
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter
import androidx.media3.ui.PlayerView
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_DECODE_MODE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_HEADERS_JSON
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_MEDIA_MIME_TYPE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_TITLE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_URL
import org.json.JSONObject

internal class NativePlaybackSession(private val host: Host) {
    interface Host {
        val controllerView: NativePlaybackControllerView
        val externalSubtitles: NativePlaybackExternalSubtitleController
        val subtitles: NativePlaybackTrackController
        val memory: NativePlaybackMemoryStore
        val target: NativePlaybackTarget
        val recovery: NativePlaybackRecoveryController
        val diagnostics: NativePlaybackDiagnostics
        val systemSession: NativePlaybackSystemController
        val runtime: NativePlaybackRuntimeController
        val launch: NativePlaybackLaunchController
        val subtitleStyle: NativePlaybackSubtitleStyleController
        val activity: Activity
        val isTelevisionDevice: Boolean
        val playerListener: Player.Listener
        val playerView: PlayerView

        fun showToast(message: String)

        val isPlayerViewInitialized: Boolean
    }

    var player: ExoPlayer? = null

    var playbackBandwidthMeter: DefaultBandwidthMeter? = null

    var baseMediaItem: MediaItem? = null

    var restoredResumePositionMs: Long = 0L

    var pendingResumePositionOverrideMs: Long? = null

    var nextInitializePlayWhenReady: Boolean? = null

    var audioOutputMode = NativeAudioOutputMode.AUTO

    var internalEpisodeSwitchPlayback = false

    fun initializePlayer() {
        if (player != null) {
            return
        }

        if (host.externalSubtitles.externalSubtitleSource == null) {
            host.subtitles.subtitleSessionPreference =
                host.memory.loadSeriesSubtitlePreference(host.target.seriesKey)
        }

        val url = host.activity.intent.getStringExtra(EXTRA_URL)?.trim().orEmpty()
        if (url.isEmpty()) {
            host.activity.finish()
            return
        }
        val title = host.activity.intent.getStringExtra(EXTRA_TITLE)?.trim().orEmpty()
        val headersJson = host.activity.intent.getStringExtra(EXTRA_HEADERS_JSON)?.trim().orEmpty()
        val targetObject = host.target.decodePlaybackTargetObject()
        NativePlaybackFormatting.logPlayback(
            "native.initialize.begin " +
                "url=${NativePlaybackSource.summarizeUrl(url)} " +
                "actual=${NativePlaybackSource.summarizeUrl(targetObject.optString("actualAddress").trim())} " +
                "source=${targetObject.optString("sourceName").trim()} " +
                "container=${targetObject.optString("container").trim()} " +
                "headers=${NativePlaybackSource.summarizeHeaderKeys(headersJson)}"
        )
        val decodeMode =
            PlaybackDecodeMode.fromRaw(
                host.activity.intent.getStringExtra(EXTRA_DECODE_MODE)?.trim().orEmpty()
            )
        val audioCodec = targetObject.optString("audioCodec").trim()
        val videoCodec = targetObject.optString("videoCodec").trim()
        val forcePcmAudioOutput =
            NativePlaybackAudioPolicy.shouldForcePcmOutput(
                isTelevision = host.isTelevisionDevice,
                audioCodec = audioCodec,
                outputMode = audioOutputMode,
            )
        val enableFfmpegAudioDecoder =
            NativePlaybackAudioPolicy.shouldEnableFfmpegAudioDecoder(
                forcePcmAudioOutput = forcePcmAudioOutput,
                audioCodec = audioCodec,
            )
        val explicitMimeType =
            host.activity.intent.getStringExtra(EXTRA_MEDIA_MIME_TYPE)?.trim().orEmpty()
        if (explicitMimeType == MimeTypes.APPLICATION_M3U8) {
            host.recovery.smartStrmHlsFallbackAttempted = true
        }
        val guessedMimeType =
            explicitMimeType
                .ifEmpty {
                    if (
                        host.recovery.smartStrmHlsFallbackAttempted &&
                            NativePlaybackHlsFallbackPolicy.isSmartStrmUrl(url)
                    ) {
                        MimeTypes.APPLICATION_M3U8
                    } else {
                        NativePlaybackSource.guessVideoMimeType(targetObject, url)
                            .takeIf { it != "-" }
                            .orEmpty()
                    }
                }
                .takeIf { it.isNotEmpty() }

        val allowResume = targetObject.optBoolean("allowResume", true)
        restoredResumePositionMs =
            NativePlaybackResumePolicy.resolveResumePositionMs(
                allowResume = allowResume,
                pendingOverrideMs = pendingResumePositionOverrideMs,
                storedResumeMs =
                    if (allowResume) host.memory.loadResumePositionMs(host.target.playbackItemKey)
                    else 0L,
            )
        pendingResumePositionOverrideMs = null

        val bandwidthMeter =
            DefaultBandwidthMeter.Builder(host.activity).build().also { meter ->
                meter.addEventListener(
                    Handler(Looper.getMainLooper()),
                    host.diagnostics.bandwidthEventListener,
                )
            }
        playbackBandwidthMeter = bandwidthMeter
        host.diagnostics.latestNetworkBytesPerSecond = 0L
        host.diagnostics.latestNetworkSampleAtMs = 0L
        val dataSourceFactory =
            DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(NATIVE_HTTP_CONNECT_TIMEOUT_MS)
                .setReadTimeoutMs(NATIVE_HTTP_READ_TIMEOUT_MS)
                .setUserAgent("Starflow")

        if (headersJson.isNotEmpty()) {
            try {
                val json = JSONObject(headersJson)
                val headers = mutableMapOf<String, String>()
                val keys = json.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    headers[key] = json.optString(key)
                }
                dataSourceFactory.setDefaultRequestProperties(headers)
            } catch (error: Throwable) {
                NativePlaybackFormatting.logPlayback(
                    "native.initialize.headers-parse-failed",
                    error,
                )
            }
        }

        val renderersFactory =
            NativePlaybackRenderersFactory(
                    context = host.activity,
                    forcePcmAudioOutput = forcePcmAudioOutput,
                    enableFfmpegAudioDecoder = enableFfmpegAudioDecoder,
                    dualSubtitleController = host.subtitles.dualSubtitleController,
                )
                .apply {
                    setEnableDecoderFallback(true)
                    when (decodeMode) {
                        PlaybackDecodeMode.AUTO -> Unit
                        PlaybackDecodeMode.HARDWARE_PREFERRED -> {
                            setMediaCodecSelector(buildMediaCodecSelector(preferSoftware = false))
                        }

                        PlaybackDecodeMode.SOFTWARE_PREFERRED -> {
                            setMediaCodecSelector(buildMediaCodecSelector(preferSoftware = true))
                        }
                    }
                }

        val trackSelector =
            DefaultTrackSelector(host.activity).apply {
                parameters =
                    buildUponParameters()
                        .setAllowInvalidateSelectionsOnRendererCapabilitiesChange(true)
                        .build()
            }
        val exoPlayer =
            ExoPlayer.Builder(host.activity)
                .setRenderersFactory(renderersFactory)
                .setTrackSelector(trackSelector)
                .setBandwidthMeter(bandwidthMeter)
                .setLoadControl(buildLoadControl())
                .setMediaSourceFactory(
                    DefaultMediaSourceFactory(dataSourceFactory)
                        .setLoadErrorHandlingPolicy(NativePlaybackLoadErrorPolicy())
                )
                .build()
        host.subtitles.automaticSubtitleSelectionApplied = false
        host.diagnostics.playbackFirstFrameRendered = false
        host.diagnostics.playbackLastRuntimeLogAtMs = 0L
        val sessionSubtitleMode = host.subtitles.subtitleSessionPreference?.mode
        if (
            sessionSubtitleMode == NativeSubtitleSessionMode.OFF ||
                (sessionSubtitleMode == null && host.subtitles.subtitlePreferenceIsOff())
        ) {
            exoPlayer.trackSelectionParameters =
                exoPlayer.trackSelectionParameters
                    .buildUpon()
                    .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                    .build()
        }
        player = exoPlayer
        exoPlayer.addListener(host.playerListener)
        exoPlayer.addAnalyticsListener(host.diagnostics.playbackPerformanceAnalyticsListener)
        val initialMediaItemBuilder =
            MediaItem.Builder()
                .setUri(url)
                .setMediaMetadata(MediaMetadata.Builder().setTitle(title.ifEmpty { null }).build())
        if (guessedMimeType != null) {
            initialMediaItemBuilder.setMimeType(guessedMimeType)
        }
        val initialMediaItem = initialMediaItemBuilder.build()
        NativePlaybackFormatting.logPlayback(
            "native.initialize.media-item " +
                "resumeMs=$restoredResumePositionMs " +
                "allowResume=$allowResume " +
                "decodeMode=$decodeMode " +
                "audioOutputMode=${audioOutputMode.rawValue} " +
                "audioCodec=${audioCodec.ifEmpty { "-" }} " +
                "videoCodec=${videoCodec.ifEmpty { "-" }} " +
                "forcePcmAudioOutput=$forcePcmAudioOutput " +
                "ffmpegAudioDecoder=$enableFfmpegAudioDecoder " +
                "mimeGuess=${guessedMimeType ?: "-"}"
        )
        baseMediaItem = initialMediaItem

        val initialPlayWhenReady = nextInitializePlayWhenReady ?: true
        nextInitializePlayWhenReady = null
        if (initialPlayWhenReady) {
            host.systemSession.playbackSystemSessionManager.prepareForPlayback()
        }
        exoPlayer.apply {
            playWhenReady = initialPlayWhenReady
            repeatMode = Player.REPEAT_MODE_OFF
            setMediaItem(initialMediaItem)
            if (restoredResumePositionMs > 5_000L) {
                seekTo(restoredResumePositionMs)
            }
            prepare()
        }
        NativePlaybackFormatting.logPlayback(
            "native.initialize.prepare-called playWhenReady=${exoPlayer.playWhenReady}"
        )

        host.playerView.player = exoPlayer
        host.systemSession.playbackSystemSessionManager.setActive(true)
        if (host.externalSubtitles.externalSubtitleSource != null) {
            host.externalSubtitles.applyExternalSubtitleConfiguration(showFeedback = false)
        }
        host.systemSession.syncPlaybackSystemSession()
        // TV used to hide the chrome right here, which left a bare black screen
        // for the whole load with no title and no speed reading. Keep it up and
        // hide it once playback settles (see hideTelevisionControllerAfterStartup).
        host.controllerView.showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
        host.controllerView.updateControllerAutoHidePolicy()
        if (restoredResumePositionMs > 5_000L) {
            host.showToast(
                "已从 ${NativePlaybackFormatting.formatClockDuration(restoredResumePositionMs)} 继续播放"
            )
        }
        host.runtime.startPlaybackWatchdog()
        host.runtime.startPlaybackRuntimeLoop()
        host.launch.schedulePlaybackLaunchTimeout()
    }

    fun releasePlayer() {
        host.launch.cancelPlaybackLaunchTimeout()
        val dualSubtitleWasEnabled = host.subtitles.dualSubtitleController.isEnabled
        host.subtitles.dualSubtitleController.disable()
        if (dualSubtitleWasEnabled && host.isPlayerViewInitialized) {
            host.subtitleStyle.applySubtitleStyle()
        }
        host.runtime.stopPlaybackWatchdog()
        host.runtime.stopPlaybackRuntimeLoop()
        host.playerView.player = null
        player?.removeListener(host.playerListener)
        player?.removeAnalyticsListener(host.diagnostics.playbackPerformanceAnalyticsListener)
        player?.release()
        player = null
        playbackBandwidthMeter?.removeEventListener(host.diagnostics.bandwidthEventListener)
        playbackBandwidthMeter = null
        host.diagnostics.latestNetworkBytesPerSecond = 0L
        host.diagnostics.latestNetworkSampleAtMs = 0L
        host.diagnostics.networkSpeedVisible = false
        host.activity.findViewById<TextView?>(R.id.native_network_speed)?.visibility = View.GONE
        host.systemSession.playbackSystemSessionManager.setActive(false)
    }

    fun rebuildPlayer() {
        releasePlayer()
        initializePlayer()
    }

    private fun buildLoadControl(): DefaultLoadControl {
        val memoryClassMb =
            (host.activity.getSystemService(Activity.ACTIVITY_SERVICE) as ActivityManager)
                .memoryClass
        val targetObject = host.target.decodePlaybackTargetObject()
        val width = targetObject.optInt("width", 0)
        val height = targetObject.optInt("height", 0)
        val bitrate = targetObject.optInt("bitrate", 0)
        val codec = targetObject.optString("videoCodec").trim().lowercase()
        val is4k = width >= 3840 || height >= 2160
        val isHevc = codec == "hevc" || codec == "h265" || codec == "x265"
        val isHeavyPlayback = is4k || bitrate >= 25_000_000 || (isHevc && bitrate >= 18_000_000)
        val bufferConfig =
            NativePlaybackBufferPolicy.resolve(
                isTelevision = host.isTelevisionDevice,
                memoryClassMb = memoryClassMb,
                isHeavyPlayback = isHeavyPlayback,
                cachedBandwidthBytesPerSecond =
                    host.diagnostics.playbackHostBandwidthCache.resolve(
                        host.diagnostics.currentPlaybackHost()
                    ),
                sourceBitrate = bitrate.toLong(),
                isRemoteEpisodeSwitch =
                    internalEpisodeSwitchPlayback &&
                        NativePlaybackSource.isHttpPlaybackUrl(
                            host.activity.intent.getStringExtra(EXTRA_URL).orEmpty()
                        ),
            )
        NativePlaybackFormatting.logPlayback(
            "native.buffer-policy television=${host.isTelevisionDevice} " +
                "memoryClassMb=$memoryClassMb heavy=$isHeavyPlayback " +
                "minMs=${bufferConfig.minBufferMs} maxMs=${bufferConfig.maxBufferMs} " +
                "startMs=${bufferConfig.bufferForPlaybackMs} " +
                "rebufferMs=${bufferConfig.bufferForPlaybackAfterRebufferMs} " +
                "targetBytes=${bufferConfig.targetBufferBytes} " +
                "bandwidthProfile=${bufferConfig.bandwidthProfile} " +
                "episodeSwitchWarmup=${bufferConfig.episodeSwitchWarmup}"
        )
        host.diagnostics.playbackPerformanceTracker.configureBuffer(
            targetBufferBytes = bufferConfig.targetBufferBytes,
            memoryClassMb = memoryClassMb,
        )
        if (
            bufferConfig.bandwidthProfile == "constrained" &&
                !host.diagnostics.bandwidthWarningShown
        ) {
            host.diagnostics.bandwidthWarningShown = true
            host.showToast("当前网速低于片源码率，可能持续缓冲")
        }

        return DefaultLoadControl.Builder()
            .setAllocator(DefaultAllocator(true, C.DEFAULT_BUFFER_SEGMENT_SIZE))
            .setBufferDurationsMs(
                bufferConfig.minBufferMs,
                bufferConfig.maxBufferMs,
                bufferConfig.bufferForPlaybackMs,
                bufferConfig.bufferForPlaybackAfterRebufferMs,
            )
            .setTargetBufferBytes(bufferConfig.targetBufferBytes)
            .setPrioritizeTimeOverSizeThresholds(bufferConfig.prioritizeTimeOverSizeThresholds)
            .build()
    }

    private fun buildMediaCodecSelector(preferSoftware: Boolean): MediaCodecSelector {
        return MediaCodecSelector { mimeType, requiresSecureDecoder, requiresTunnelingDecoder ->
            val allInfos =
                MediaCodecUtil.getDecoderInfos(
                    mimeType,
                    requiresSecureDecoder,
                    requiresTunnelingDecoder,
                )
            val preferredInfos = allInfos.filter { info -> info.softwareOnly == preferSoftware }
            if (preferredInfos.isNotEmpty()) {
                preferredInfos
            } else {
                allInfos
            }
        }
    }

    fun restartPlayerWithAudioOutputMode(selected: NativeAudioOutputMode) {
        val currentPlayer = player ?: return
        pendingResumePositionOverrideMs = currentPlayer.currentPosition.coerceAtLeast(0L)
        nextInitializePlayWhenReady = currentPlayer.playWhenReady
        audioOutputMode = selected
        NativePlaybackFormatting.logPlayback(
            "native.audio-output.changed mode=${selected.rawValue} " +
                "resumeMs=$pendingResumePositionOverrideMs"
        )
        rebuildPlayer()
        host.showToast("已切换为${selected.displayLabel}")
    }

    fun seekBy(deltaMs: Long): Boolean {
        val currentPlayer = player ?: return false
        val durationMs = currentPlayer.duration.takeIf { it > 0L } ?: 0L
        val currentPositionMs = currentPlayer.currentPosition.coerceAtLeast(0L)
        val nextPositionMs =
            if (durationMs > 0L) {
                (currentPositionMs + deltaMs).coerceIn(0L, durationMs)
            } else {
                (currentPositionMs + deltaMs).coerceAtLeast(0L)
            }
        if (nextPositionMs == currentPositionMs) {
            return false
        }
        currentPlayer.seekTo(nextPositionMs)
        host.runtime.resetPlaybackWatchdogProgress(nextPositionMs)
        host.runtime.syncSkipFlagsWithCurrentPosition()
        host.controllerView.showControllerForRemoteFocus(ControllerFocusTarget.PLAYER)
        return true
    }

    fun togglePlayback(): Boolean {
        val currentPlayer = player ?: return false
        return setPlayWhenReady(!currentPlayer.playWhenReady)
    }

    fun setPlayWhenReady(playWhenReady: Boolean): Boolean {
        val currentPlayer = player ?: return false
        if (playWhenReady) {
            host.systemSession.playbackSystemSessionManager.prepareForPlayback()
        } else {
            host.runtime.resetPlaybackWatchdogProgress(currentPlayer.currentPosition)
        }
        currentPlayer.playWhenReady = playWhenReady
        if (playWhenReady) {
            host.playerView.post { host.runtime.maybeApplyAutoSkip() }
        }
        return true
    }
}
