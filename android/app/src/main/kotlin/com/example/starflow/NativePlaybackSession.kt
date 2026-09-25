package com.example.starflow

import android.app.Activity
import android.app.ActivityManager
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.TextView
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Tracks
import androidx.media3.decoder.ffmpeg.FfmpegLibrary
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.DecoderReuseEvaluation
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.upstream.DefaultAllocator
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.ui.PlayerView
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_DECODE_MODE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_HEADERS_JSON
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_MEDIA_MIME_TYPE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_TITLE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_URL

internal class NativePlaybackSession(private val host: Host) {
    interface Host {
        val remote: NativePlaybackRemoteController
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

    var playbackTransferProgress: NativePlaybackTransferProgress? = null
        private set

    private var playbackAllocator: DefaultAllocator? = null
    val cachedMediaBytes: Long?
        get() = playbackAllocator?.totalBytesAllocated?.toLong()

    var baseMediaItem: MediaItem? = null

    var restoredResumePositionMs: Long = 0L

    var pendingResumePositionOverrideMs: Long? = null

    var nextInitializePlayWhenReady: Boolean? = null

    var audioOutputMode = NativeAudioOutputMode.AUTO
    var audioFallbackMime: String? = null
    var pcm16Fallback = false
    internal var highPrecisionPcmEnabled = false
        private set
    internal var audioOutputState = NativeAudioOutputState()
        private set
    @Volatile private var requestedAudioParameters = PlaybackParameters.DEFAULT
    private var speedForcedDecode = false
    private val audioPrecisionHistory = NativeAudioPrecisionHistory()
    private var audioStateListener: AnalyticsListener? = null
    private var audioParametersListener: Player.Listener? = null
    private var pendingAudioFormat: Format? = null
    private var pendingPlaybackParameters: PlaybackParameters? = null
    private var pendingVolume: Float? = null
    private var pendingAudioItemKey: String? = null

    fun resetAudioRecovery() {
        audioFallbackMime = null
        pcm16Fallback = false
        speedForcedDecode = false
        audioPrecisionHistory.clear()
        pendingAudioFormat = null
        pendingPlaybackParameters = null
        pendingVolume = null
        pendingAudioItemKey = null
    }

    fun preserveAudioSession() {
        val current = player ?: return
        discardAudioStateForDifferentMedia()
        // A replacement player can be rebuilt again before publishing its audio tracks.
        if (pendingAudioFormat == null) {
            val tracks = NativePlaybackAudioTracks.list(current.currentTracks)
            val overrides = current.trackSelectionParameters?.overrides
            // Selection overrides are synchronous; selected flags arrive in a later event batch.
            pendingAudioFormat = (tracks.firstOrNull { track ->
                track.supported && overrides?.get(track.override.mediaTrackGroup)
                    ?.trackIndices?.containsAll(track.override.trackIndices) == true
            } ?: tracks.firstOrNull { it.selected })?.format
        }
        pendingPlaybackParameters = current.playbackParameters
        pendingVolume = current.volume
        pendingAudioItemKey = host.target.playbackItemKey
        pendingResumePositionOverrideMs = current.currentPosition.coerceAtLeast(0L)
        nextInitializePlayWhenReady = current.playWhenReady
    }

    fun restoreAudioTrack(tracks: Tracks): Boolean {
        discardAudioStateForDifferentMedia()
        val previous = pendingAudioFormat ?: return false
        val choices = NativePlaybackAudioTracks.list(tracks)
        if (choices.isEmpty()) return true
        pendingAudioFormat = null
        val match = NativePlaybackAudioTracks.match(choices, previous) ?: return false
        val current = player ?: return false
        current.trackSelectionParameters = current.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
            .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
            .addOverride(match.override).build()
        return true
    }

    internal fun restoreAudioPlaybackParameters(current: ExoPlayer) {
        discardAudioStateForDifferentMedia()
        pendingPlaybackParameters?.let { current.playbackParameters = it }
        pendingVolume?.let { current.volume = it }
        pendingPlaybackParameters = null
        pendingVolume = null
    }

    private fun useHighPrecisionPcm(parameters: PlaybackParameters): Boolean =
        NativePlaybackAudioPolicy.useHighPrecisionPcm(
            audioOutputMode, parameters, pcm16Fallback || audioFallbackMime != null,
        )

    fun stagePlaybackParameters(parameters: PlaybackParameters) {
        discardAudioStateForDifferentMedia()
        pendingPlaybackParameters = parameters
        pendingAudioItemKey = host.target.playbackItemKey
    }

    fun setPlaybackParameters(parameters: PlaybackParameters) {
        val current = player ?: return
        discardAudioStateForDifferentMedia()
        requestedAudioParameters = parameters
        val rebuild = needsAudioRebuild(parameters)
        NativeAppLogger.info("playback.audio", "Audio parameters speed=${parameters.speed} " +
            "pitch=${parameters.pitch} action=${if (rebuild) "rebuild" else "in-place"} " +
            "passthrough=${audioOutputState.isPassthrough()} " +
            "output=${NativePlaybackAudioPolicy.encodingLabel(audioOutputState.outputEncoding)}")
        if (rebuild) {
            rememberAudioTransition(parameters)
            // Decide before setting speed: a float sink may reject/reset non-default parameters.
            preserveAudioSession()
            stagePlaybackParameters(parameters)
            rebuildPlayer()
        } else {
            current.playbackParameters = parameters
        }
    }

    internal fun reconcileAudioPrecision(current: ExoPlayer, parameters: PlaybackParameters) {
        if (player !== current || current.playbackParameters != parameters ||
            !needsAudioRebuild(parameters)) return
        discardAudioStateForDifferentMedia()
        requestedAudioParameters = parameters
        rememberAudioTransition(parameters)
        preserveAudioSession()
        NativeAppLogger.info("playback.audio", "Audio precision changed speed=${parameters.speed} " +
            "pitch=${parameters.pitch} highPrecision=${useHighPrecisionPcm(parameters)}")
        rebuildPlayer()
    }

    private fun needsAudioRebuild(parameters: PlaybackParameters): Boolean =
        (parameters != PlaybackParameters.DEFAULT && audioOutputState.isPassthrough()) ||
            (parameters == PlaybackParameters.DEFAULT && speedForcedDecode) ||
            (useHighPrecisionPcm(parameters) && !highPrecisionPcmEnabled &&
                audioPrecisionHistory.shouldRestore(currentAudioSource())) ||
            audioOutputState.needsPrecisionChange(highPrecisionPcmEnabled, useHighPrecisionPcm(parameters))

    private fun currentAudioSource(): Format? = player?.audioFormat ?: audioOutputState.sourceInput ?:
        player?.currentTracks?.let { NativePlaybackAudioTracks.list(it).firstOrNull { track -> track.selected }?.format }

    private fun rememberAudioTransition(parameters: PlaybackParameters) {
        if (parameters != PlaybackParameters.DEFAULT) {
            if (audioOutputState.isPassthrough()) speedForcedDecode = true
            if (highPrecisionPcmEnabled && (audioOutputState.hasHighResolutionInput() ||
                    audioOutputState.outputEncoding == C.ENCODING_PCM_FLOAT)) {
                audioPrecisionHistory.recordSpeedDowngrade(currentAudioSource())
            }
        } else {
            speedForcedDecode = false
            audioPrecisionHistory.clear()
        }
    }

    private fun requiresDecodedAudio(mime: String?): Boolean =
        NativePlaybackAudioPolicy.requiresDecodedOutput(mime, host.isTelevisionDevice,
            audioOutputMode, audioFallbackMime, requestedAudioParameters, pcm16Fallback)

    var internalEpisodeSwitchPlayback = false
    var nextEpisodeIsAutomatic = false
    private var initialIntroPositionMs = 0L

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
        discardAudioStateForDifferentMedia()
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
        val skipPreference = host.memory.loadSeriesSkipPreference(host.target.seriesKey)
        val startPosition =
            NativePlaybackStartPolicy.resolve(
                allowResume = allowResume,
                runtimeOverrideMs = pendingResumePositionOverrideMs,
                storedResumeMs =
                    if (allowResume) host.memory.loadResumePositionMs(host.target.playbackItemKey)
                    else 0L,
                automaticNext = nextEpisodeIsAutomatic,
                skipEnabled = skipPreference?.optBoolean("enabled", false) == true,
                introDurationMs = skipPreference?.optLong("introDurationMs", 0L) ?: 0L,
            )
        restoredResumePositionMs = startPosition.positionMs
        initialIntroPositionMs = startPosition.introPositionMs
        host.runtime.introSkipApplied = true
        nextEpisodeIsAutomatic = false
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
        // Each player owns its listener so a released stream cannot keep the next startup alive.
        val transferProgress = NativePlaybackTransferProgress()
        playbackTransferProgress = transferProgress
        val dataSourceFactory = NativePlaybackHttpDataSource.factory(
            host.activity, url, NativePlaybackSource.buildRequestHeaders(headersJson), transferProgress,
        )

        requestedAudioParameters = pendingPlaybackParameters ?: PlaybackParameters.DEFAULT
        highPrecisionPcmEnabled = useHighPrecisionPcm(requestedAudioParameters)
        if (pcm16Fallback || audioFallbackMime != null || audioOutputMode == NativeAudioOutputMode.PCM_COMPATIBILITY) {
            audioPrecisionHistory.clear()
        }
        val outputState = NativeAudioOutputState()
        audioOutputState = outputState
        val audioHandler = Handler(Looper.getMainLooper())
        val renderersFactory =
            NativePlaybackRenderersFactory(
                    context = host.activity,
                    requiresDecodedOutput = ::requiresDecodedAudio,
                    dualSubtitleController = host.subtitles.dualSubtitleController,
                    onAudioSinkConfigured = { format ->
                        outputState.onSinkConfigured(format)
                        audioHandler.post {
                            if (audioOutputState === outputState) {
                                player?.let { reconcileAudioPrecision(it, it.playbackParameters) }
                            }
                        }
                    },
                )
                .apply {
                    setEnableDecoderFallback(true)
                    setEnableAudioFloatOutput(highPrecisionPcmEnabled)
                    setEnableAudioOutputPlaybackParameters(false)
                    setMediaCodecSelector(buildMediaCodecSelector(decodeMode))
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
                    DefaultMediaSourceFactory(dataSourceFactory, buildExtractorsFactory(audioCodec))
                        .setSubtitleParserFactory(NativeSubtitleParserFactory())
                        .setLoadErrorHandlingPolicy(NativePlaybackLoadErrorPolicy())
                )
                .build()
        host.subtitles.automaticSubtitleSelectionApplied = false
        host.subtitles.pendingExternalSubtitleSelection = false
        host.diagnostics.playbackFirstFrameRendered = false
        host.diagnostics.awaitingVideoFrameAfterSeek = false
        host.diagnostics.subtitleLastCueLogAtMs = -1L
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
        audioStateListener = object : AnalyticsListener {
            override fun onAudioDecoderInitialized(eventTime: AnalyticsListener.EventTime,
                decoderName: String, initializedTimestampMs: Long, initializationDurationMs: Long) {
                outputState.onDecoderInitialized(decoderName)
            }
            override fun onAudioDecoderReleased(eventTime: AnalyticsListener.EventTime, decoderName: String) {
                outputState.onDecoderReleased(decoderName)
            }
            override fun onAudioInputFormatChanged(eventTime: AnalyticsListener.EventTime,
                format: Format, decoderReuseEvaluation: DecoderReuseEvaluation?) {
                outputState.onSourceInputChanged(format)
            }
            override fun onAudioTrackInitialized(eventTime: AnalyticsListener.EventTime, config: AudioSink.AudioTrackConfig) {
                outputState.onAudioTrackInitialized(config)
            }
            override fun onAudioTrackReleased(eventTime: AnalyticsListener.EventTime, config: AudioSink.AudioTrackConfig) {
                outputState.onAudioTrackReleased(config)
            }
        }.also(exoPlayer::addAnalyticsListener)
        restoreAudioPlaybackParameters(exoPlayer)
        audioParametersListener = object : Player.Listener {
            override fun onPlaybackParametersChanged(playbackParameters: PlaybackParameters) {
                if (player !== exoPlayer) return
                requestedAudioParameters = playbackParameters
                // Rebuild outside the event batch and retain the originating player identity.
                audioHandler.post { reconcileAudioPrecision(exoPlayer, playbackParameters) }
            }
        }.also(exoPlayer::addListener)
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
                "metadataPcmHint=$forcePcmAudioOutput " +
                "ffmpegConfigured=$enableFfmpegAudioDecoder " +
                "ffmpegAvailable=${FfmpegLibrary.isAvailable()} " +
                "audioFallbackMime=${audioFallbackMime ?: "-"} " +
                "highPrecisionPcm=$highPrecisionPcmEnabled pcm16Fallback=$pcm16Fallback " +
                "mimeGuess=${guessedMimeType ?: "-"}"
        )
        baseMediaItem = initialMediaItem

        val initialPlayWhenReady = nextInitializePlayWhenReady ?: true
        nextInitializePlayWhenReady = null
        host.launch.schedulePlaybackLaunchTimeout()
        if (player !== exoPlayer) return
        if (initialPlayWhenReady) {
            host.systemSession.playbackSystemSessionManager.prepareForPlayback()
        }
        exoPlayer.apply {
            playWhenReady = initialPlayWhenReady
            repeatMode = Player.REPEAT_MODE_OFF
            setMediaItem(initialMediaItem, restoredResumePositionMs)
            prepare()
        }
        if (player !== exoPlayer) return
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
        if (startPosition.isResume) {
            host.showToast(
                "已从 ${NativePlaybackFormatting.formatClockDuration(restoredResumePositionMs)} 继续播放"
            )
        }
        host.runtime.startPlaybackWatchdog()
        host.runtime.startPlaybackRuntimeLoop()
    }

    fun releasePlayer() {
        host.remote.resetInputState()
        host.controllerView.cancelPendingControllerFocus()
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
        audioParametersListener?.let { player?.removeListener(it) }
        audioParametersListener = null
        player?.removeAnalyticsListener(host.diagnostics.playbackPerformanceAnalyticsListener)
        audioStateListener?.let { player?.removeAnalyticsListener(it) }
        audioStateListener = null
        player?.release()
        player = null
        audioOutputState = NativeAudioOutputState()
        playbackBandwidthMeter?.removeEventListener(host.diagnostics.bandwidthEventListener)
        playbackBandwidthMeter = null
        playbackTransferProgress = null
        playbackAllocator = null
        host.diagnostics.latestNetworkBytesPerSecond = 0L
        host.diagnostics.latestNetworkSampleAtMs = 0L
        host.diagnostics.networkSpeedVisible = false
        host.activity.findViewById<TextView?>(R.id.native_network_speed)?.visibility = View.GONE
        host.systemSession.playbackSystemSessionManager.setActive(false)
    }

    private fun discardAudioStateForDifferentMedia() {
        if (pendingAudioItemKey == host.target.playbackItemKey) return
        audioPrecisionHistory.clear()
        pendingAudioFormat = null
        pendingPlaybackParameters = null
        pendingVolume = null
        pendingAudioItemKey = host.target.playbackItemKey
    }

    fun rebuildPlayer() {
        releasePlayer()
        initializePlayer()
    }

    fun validateInitialIntroPosition() {
        val current = player ?: return
        if (initialIntroPositionMs <= 0L || current.duration <= 0L) return
        val invalidIntro = initialIntroPositionMs >= current.duration
        initialIntroPositionMs = 0L
        if (invalidIntro) {
            restoredResumePositionMs = 0L
            current.seekTo(0L)
        }
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

        val allocator = DefaultAllocator(true, C.DEFAULT_BUFFER_SEGMENT_SIZE)
        playbackAllocator = allocator
        return DefaultLoadControl.Builder()
            .setAllocator(allocator)
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

    internal fun buildExtractorsFactory(audioCodec: String = ""): ExtractorsFactory =
        NativePlaybackExtractorsFactory(audioCodec)

    private fun buildMediaCodecSelector(mode: PlaybackDecodeMode): MediaCodecSelector {
        return MediaCodecSelector { mimeType, requiresSecureDecoder, requiresTunnelingDecoder ->
            val allInfos =
                MediaCodecUtil.getDecoderInfos(
                    mimeType,
                    requiresSecureDecoder,
                    requiresTunnelingDecoder,
                )
            if (!requiresSecureDecoder && !requiresTunnelingDecoder &&
                NativePlaybackAudioPolicy.requiresDecodedOutput(mimeType, host.isTelevisionDevice,
                    audioOutputMode, audioFallbackMime) && FfmpegLibrary.supportsFormat(mimeType)) {
                emptyList()
            } else if (mode == PlaybackDecodeMode.AUTO) {
                allInfos
            } else {
                allInfos.sortedBy { it.softwareOnly != (mode == PlaybackDecodeMode.SOFTWARE_PREFERRED) }
            }
        }
    }

    fun restartPlayerWithAudioOutputMode(selected: NativeAudioOutputMode) {
        if (player == null) return
        preserveAudioSession()
        audioFallbackMime = null
        pcm16Fallback = false
        audioPrecisionHistory.clear()
        speedForcedDecode = false
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
        return seekTo(currentPlayer.currentPosition.coerceAtLeast(0L) + deltaMs)
    }

    fun seekTo(positionMs: Long): Boolean {
        val currentPlayer = player ?: return false
        val durationMs = currentPlayer.duration.takeIf { it > 0L } ?: 0L
        val currentPositionMs = currentPlayer.currentPosition.coerceAtLeast(0L)
        val nextPositionMs =
            if (durationMs > 0L) {
                positionMs.coerceIn(0L, durationMs)
            } else {
                positionMs.coerceAtLeast(0L)
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
