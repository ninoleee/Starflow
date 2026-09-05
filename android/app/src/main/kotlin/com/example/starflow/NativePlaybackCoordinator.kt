package com.example.starflow

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.widget.Toast
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.Tracks
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import androidx.media3.ui.R as Media3UiR
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_AUDIO_OUTPUT_MODE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_DECODE_MODE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_EPISODE_QUEUE_JSON
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_MEDIA_MIME_TYPE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_PLAYBACK_ITEM_KEY
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_PLAYBACK_TARGET_JSON
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_PRIMARY_SUBTITLE_POSITION
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_RESOLVER_SESSION_ID
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_SECONDARY_SUBTITLE_POSITION
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_SECONDARY_SUBTITLE_SCALE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_SERIES_KEY
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_SUBTITLE_SCALE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_TITLE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_URL
import com.example.starflow.NativePlaybackActivity.Companion.RESULT_PLAYBACK_CANCELLED
import com.example.starflow.NativePlaybackActivity.Companion.RESULT_PLAYBACK_READY

internal class NativePlaybackCoordinator(override val activity: Activity) :
    NativePlaybackSession.Host,
    NativePlaybackLaunchController.Host,
    NativePlaybackRecoveryController.Host,
    NativePlaybackEpisodeController.Host,
    NativePlaybackRemoteController.Host,
    NativePlaybackControllerView.Host,
    NativePlaybackSettingsController.Host,
    NativePlaybackTrackController.Host,
    NativePlaybackSubtitleStyleController.Host,
    NativePlaybackExternalSubtitleController.Host,
    NativePlaybackRuntimeController.Host,
    NativePlaybackDiagnostics.Host,
    NativePlaybackSystemController.Host {
    override val session by lazy { NativePlaybackSession(this) }
    override val launch by lazy { NativePlaybackLaunchController(this) }
    override val recovery by lazy { NativePlaybackRecoveryController(this) }
    override val episodes by lazy { NativePlaybackEpisodeController(this) }
    override val controllerView by lazy { NativePlaybackControllerView(this) }
    override val remote by lazy { NativePlaybackRemoteController(this) }
    override val settings by lazy { NativePlaybackSettingsController(this) }
    override val subtitles by lazy { NativePlaybackTrackController(this) }
    override val subtitleStyle by lazy { NativePlaybackSubtitleStyleController(this) }
    override val externalSubtitles by lazy { NativePlaybackExternalSubtitleController(this) }
    override val subtitleFiles by lazy { NativePlaybackSubtitleFiles(activity) }
    override val runtime by lazy { NativePlaybackRuntimeController(this) }
    override val diagnostics by lazy { NativePlaybackDiagnostics(this) }
    override val systemSession by lazy { NativePlaybackSystemController(this) }
    override val target = NativePlaybackTarget {
        activity.intent.getStringExtra(EXTRA_TITLE).orEmpty()
    }
    override val memory by lazy {
        NativePlaybackMemoryStore(
            activity.getSharedPreferences(SHARED_PREFERENCES_NAME, Activity.MODE_PRIVATE)
        )
    }
    override val isPlayerViewInitialized: Boolean
        get() = ::playerView.isInitialized

    override lateinit var playerView: PlayerView

    override val playerListener: Player.Listener =
        object : Player.Listener {
            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                if (!playWhenReady) episodes.cancelAutomaticAdvance()
            }

            override fun onTimelineChanged(timeline: Timeline, reason: Int) {
                session.validateInitialIntroPosition()
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                diagnostics.playbackPerformanceTracker.onBufferingChanged(
                    buffering = session.player?.playbackState == Player.STATE_BUFFERING,
                    playWhenReady = session.player?.playWhenReady == true,
                )
                if (isPlaying) {
                    runtime.markPlaybackWatchdogActivity(session.player?.currentPosition ?: 0L)
                } else if (session.player?.playWhenReady == false) {
                    runtime.persistPlaybackProgress(force = true)
                }
                systemSession.syncPlaybackSystemSession()
                controllerView.updateControllerAutoHidePolicy()
                if (
                    isTelevisionDevice &&
                        !externalSubtitles.subtitleSearchActive &&
                        !settings.isOverlayDialogVisible()
                ) {
                    if (!isPlaying) {
                        controllerView.showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
                    } else if (!playerView.isControllerFullyVisible) {
                        playerView.requestFocus()
                    }
                }
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                diagnostics.playbackPerformanceTracker.onBufferingChanged(
                    buffering = playbackState == Player.STATE_BUFFERING,
                    playWhenReady = session.player?.playWhenReady == true,
                )
                if (
                    playbackState == Player.STATE_READY || playbackState == Player.STATE_BUFFERING
                ) {
                    runtime.markPlaybackWatchdogActivity(session.player?.currentPosition ?: 0L)
                }
                systemSession.syncPlaybackSystemSession()
                systemSession.updatePictureInPictureParams()
                controllerView.updateProgressMarkers()
                if (playbackState == Player.STATE_READY) {
                    session.validateInitialIntroPosition()
                    val tracks = session.player?.currentTracks
                    if (
                        tracks?.groups?.any { it.type == C.TRACK_TYPE_AUDIO } == true &&
                            tracks.groups.none { it.type == C.TRACK_TYPE_VIDEO }
                    ) {
                        episodes.onPlaybackReady()
                        launch.cancelPlaybackLaunchTimeout()
                        launch.reportPlaybackLaunchResult(RESULT_PLAYBACK_READY)
                    }
                    controllerView.updateControllerAutoHidePolicy()
                    runtime.maybeApplyAutoSkip()
                }
                if (
                    playbackState == Player.STATE_ENDED &&
                        session.player?.playbackState == Player.STATE_ENDED &&
                        episodes.advanceToAdjacentEpisode(forward = true, reason = "ended")
                ) {
                    return
                }
                NativePlaybackFormatting.logPlayback(
                    "native.playback.state state=${NativePlaybackFormatting.playbackStateLabel(playbackState)} " +
                        "positionMs=${session.player?.currentPosition ?: -1L}"
                )
            }

            override fun onRenderedFirstFrame() {
                episodes.onPlaybackReady()
                diagnostics.playbackFirstFrameRendered = true
                controllerView.updateControllerAutoHidePolicy()
                controllerView.hideTelevisionControllerAfterStartup()
                val firstFrameMs = diagnostics.playbackPerformanceTracker.onFirstFrame()
                if (firstFrameMs >= 0L) {
                    NativeAppLogger.info(
                        "playback.performance",
                        "Playback first frame rendered engine=exo firstFrameMs=$firstFrameMs",
                    )
                }
                diagnostics.logPlaybackRuntime(reason = "first-frame")
                launch.cancelPlaybackLaunchTimeout()
                launch.reportPlaybackLaunchResult(RESULT_PLAYBACK_READY)
            }

            override fun onPositionDiscontinuity(
                oldPosition: Player.PositionInfo,
                newPosition: Player.PositionInfo,
                reason: Int,
            ) {
                NativePlaybackFormatting.logPlayback(
                    "native.playback.discontinuity reason=$reason " +
                        "oldPositionMs=${oldPosition.positionMs} " +
                        "newPositionMs=${newPosition.positionMs}"
                )
                runtime.resetPlaybackWatchdogProgress(newPosition.positionMs)
                runtime.syncSkipFlagsWithCurrentPosition()
                if (reason == Player.DISCONTINUITY_REASON_SEEK) runtime.onUserSeek()
                systemSession.syncPlaybackSystemSession()
            }

            override fun onPlayerError(error: PlaybackException) {
                NativePlaybackFormatting.logPlayback(
                    "native.playback.error code=${error.errorCode} " +
                        "name=${error.errorCodeName} message=${error.message ?: ""} " +
                        "url=${NativePlaybackSource.summarizeUrl(activity.intent.getStringExtra(EXTRA_URL)?.trim().orEmpty())} " +
                        "container=${target.decodePlaybackTargetObject().optString("container").trim()}",
                    error,
                )
                if (recovery.retrySmartStrmAsHlsIfNeeded(error)) {
                    return
                }
                if (episodes.retryPreparedAddressIfNeeded(error)) return
                launch.handlePlayerError(error)
            }

            override fun onTracksChanged(tracks: Tracks) {
                diagnostics.logAudioTracks(tracks)
                diagnostics.logVideoTracks(tracks)
                recovery.fallbackToTranscodedVideoIfNeeded(tracks)
                subtitles.applyAutomaticSubtitleSelection(tracks)
            }
        }

    override val isTelevisionDevice: Boolean by lazy {
        val currentMode =
            activity.resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK
        currentMode == Configuration.UI_MODE_TYPE_TELEVISION ||
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEVISION)
    }

    fun onCreate(savedInstanceState: Bundle?) {
        activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        applyPlaybackIntent(activity.intent)
        NativeAppLogger.markPlaybackStarted(
            mapOf(
                "television" to isTelevisionDevice,
                "decodeMode" to activity.intent.getStringExtra(EXTRA_DECODE_MODE).orEmpty(),
                "container" to target.decodePlaybackTargetObject().optString("container").trim(),
            )
        )
        NativePlaybackFormatting.logPlayback(
            "native.activity.created television=$isTelevisionDevice"
        )

        activity.setContentView(
            if (isTelevisionDevice) {
                R.layout.native_player_view_tv
            } else {
                R.layout.native_player_view_phone
            }
        )
        playerView =
            activity.findViewById<PlayerView>(R.id.native_player_view).apply {
                useController = true
                setShutterBackgroundColor(Color.BLACK)
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                setBackgroundColor(Color.BLACK)
                keepScreenOn = true
                setShowSubtitleButton(true)
                setShowFastForwardButton(true)
                setShowRewindButton(true)
                setShowPreviousButton(false)
                setShowNextButton(false)
                setControllerAutoShow(!isTelevisionDevice)
                setControllerHideOnTouch(!isTelevisionDevice)
                setControllerShowTimeoutMs(CONTROLLER_SHOW_TIMEOUT_MS)
            }
        subtitleStyle.applySubtitleStyle()
        controllerView.bindControllerChrome()
        controllerView.configureRemoteControls()
        activity.findViewById<View>(Media3UiR.id.exo_subtitle)?.setOnClickListener {
            subtitles.openSubtitleTrackSelectionDialog()
        }
        activity.findViewById<View>(R.id.native_audio_track_button)?.setOnClickListener {
            subtitles.openAudioTrackSelectionDialog()
        }
        activity.findViewById<View>(R.id.native_external_subtitle)?.setOnClickListener {
            externalSubtitles.openExternalSubtitlePicker()
            controllerView.showControllerForRemoteFocus(ControllerFocusTarget.SETTINGS)
        }
        activity.findViewById<View>(R.id.native_subtitle_delay)?.setOnClickListener {
            externalSubtitles.openSubtitleDelayPicker()
            controllerView.showControllerForRemoteFocus(ControllerFocusTarget.SETTINGS)
        }
        activity.findViewById<View>(R.id.native_online_subtitle_search)?.setOnClickListener {
            externalSubtitles.openOnlineSubtitleSearch()
        }
        activity.findViewById<View>(R.id.native_playback_settings)?.setOnClickListener {
            settings.openPlaybackSettingsDialog()
        }
        controllerView.updateControllerAutoHidePolicy()
        systemSession.updatePictureInPictureParams()
        controllerView.enterImmersiveMode()
    }

    fun onNewIntent(newIntent: Intent) {
        launch.reportPlaybackLaunchResult(
            resultCode = RESULT_PLAYBACK_CANCELLED,
            message = "播放请求已被新的影片替换",
        )
        runtime.persistPlaybackProgress(force = true)
        diagnostics.finishPlaybackPerformanceSession("replaced")
        session.releasePlayer()
        launch.dismissFailure()
        activity.setIntent(newIntent)
        resetPlaybackStateForNewIntent()
        applyPlaybackIntent(newIntent)
        subtitleStyle.applySubtitleStyle()
        controllerView.bindControllerChrome()
        controllerView.updateProgressMarkers()
        session.initializePlayer()
    }

    fun onStart() {
        session.initializePlayer()
    }

    fun onResume() {
        controllerView.enterImmersiveMode()
        controllerView.restoreVideoSurfaceIfNeeded()
        playerView.onResume()
        systemSession.syncPlaybackSystemSession()
        if (
            isTelevisionDevice &&
                session.player?.isPlaying == true &&
                !externalSubtitles.subtitleSearchActive
        ) {
            playerView.hideController()
            playerView.requestFocus()
        }
        if (
            !externalSubtitles.subtitleSearchActive &&
                externalSubtitles.resumePlaybackAfterSubtitleSearch
        ) {
            session.setPlayWhenReady(true)
            externalSubtitles.resumePlaybackAfterSubtitleSearch = false
        }
    }

    fun onPause() {
        if (externalSubtitles.subtitleSearchActive) {
            controllerView.hideVideoSurfaceForOverlay()
        }
        runtime.persistPlaybackProgress(force = true)
        playerView.onPause()
    }

    fun onStop() {
        remote.dismissExitConfirmation()
        settings.dismissSettingsDialog()
        episodes.dismissDialog()
        settings.dismissTrackDialog()
        runtime.persistPlaybackProgress(force = true)
        if (activity.isFinishing) {
            session.releasePlayer()
        }
    }

    fun onDestroy() {
        episodes.invalidateResolution()
        launch.reportPlaybackLaunchResult(
            resultCode = RESULT_PLAYBACK_CANCELLED,
            message = "原生播放器在画面就绪前已关闭",
        )
        diagnostics.finishPlaybackPerformanceSession("destroyed")
        session.releasePlayer()
        launch.dismissFailure()
        systemSession.playbackSystemSessionManager.release()
        NativePlaybackFormatting.logPlayback(
            "native.activity.destroyed finishing=${activity.isFinishing}"
        )
        NativeAppLogger.markPlaybackEnded()
    }

    private fun applyPlaybackIntent(playbackIntent: Intent) {
        launch.applyIntent(playbackIntent)
        target.playbackTargetJson =
            playbackIntent.getStringExtra(EXTRA_PLAYBACK_TARGET_JSON)?.trim().orEmpty().ifEmpty {
                "{}"
            }
        diagnostics.beginPlaybackPerformanceSession()
        target.playbackItemKey =
            playbackIntent.getStringExtra(EXTRA_PLAYBACK_ITEM_KEY)?.trim().orEmpty()
        target.seriesKey = playbackIntent.getStringExtra(EXTRA_SERIES_KEY)?.trim().orEmpty()
        target.resolverSessionId =
            playbackIntent.getStringExtra(EXTRA_RESOLVER_SESSION_ID)?.trim().orEmpty()
        val parsedEpisodeQueue =
            NativeEpisodeQueue.fromJsonString(
                playbackIntent.getStringExtra(EXTRA_EPISODE_QUEUE_JSON)?.trim().orEmpty()
            )
        val launchMediaMimeType =
            playbackIntent.getStringExtra(EXTRA_MEDIA_MIME_TYPE)?.trim().orEmpty()
        episodes.episodeQueue = parsedEpisodeQueue?.withCurrentMediaMimeType(launchMediaMimeType)
        session.audioOutputMode =
            NativeAudioOutputMode.fromRaw(
                playbackIntent.getStringExtra(EXTRA_AUDIO_OUTPUT_MODE).orEmpty()
            )
        subtitleStyle.subtitleScale =
            playbackIntent.getDoubleExtra(
                EXTRA_SUBTITLE_SCALE,
                NativeSubtitleStylePolicy.DEFAULT_SCALE,
            )
        subtitleStyle.primarySubtitlePosition =
            playbackIntent
                .getDoubleExtra(EXTRA_PRIMARY_SUBTITLE_POSITION, 80.0)
                .coerceIn(50.0, 100.0)
        subtitleStyle.secondarySubtitlePosition =
            playbackIntent
                .getDoubleExtra(EXTRA_SECONDARY_SUBTITLE_POSITION, 90.0)
                .coerceIn(50.0, 100.0)
        subtitleStyle.secondarySubtitleScale =
            playbackIntent
                .getDoubleExtra(
                    EXTRA_SECONDARY_SUBTITLE_SCALE,
                    NativeDualSubtitleLayoutPolicy.SECONDARY_TEXT_SCALE_PERCENT,
                )
                .coerceIn(50.0, 120.0)
        subtitles.dualSubtitleController.configureLayout(
            primaryPositionPercent = subtitleStyle.primarySubtitlePosition,
            secondaryPositionPercent = subtitleStyle.secondarySubtitlePosition,
            secondaryScalePercent = subtitleStyle.secondarySubtitleScale,
        )
        externalSubtitles.restoreExternalSubtitleSourceFromTarget()
    }

    private fun resetPlaybackStateForNewIntent() {
        session.baseMediaItem = null
        recovery.resetForNewMedia()
        episodes.invalidateResolution()
        externalSubtitles.externalSubtitleSource = null
        subtitles.dualSubtitleController.disable()
        subtitles.subtitleSessionPreference = null
        externalSubtitles.subtitleDelayMs = 0L
        session.restoredResumePositionMs = 0L
        runtime.lastSavedPositionMs = -1L
        session.pendingResumePositionOverrideMs = null
        session.nextInitializePlayWhenReady = null
        runtime.introSkipApplied = false
        runtime.outroSkipApplied = false
        externalSubtitles.subtitleSearchActive = false
        externalSubtitles.resumePlaybackAfterSubtitleSearch = false
        session.internalEpisodeSwitchPlayback = false
        session.nextEpisodeIsAutomatic = false
        runtime.resetForNewMedia()
    }

    fun onWindowFocusChanged(hasFocus: Boolean) {
        if (hasFocus) {
            controllerView.enterImmersiveMode()
        }
    }

    fun onUserLeaveHint() {
        systemSession.enterPictureInPictureIfPossible()
    }

    fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        if (isInPictureInPictureMode) {
            playerView.hideController()
        } else if (!externalSubtitles.subtitleSearchActive) {
            if (isTelevisionDevice && session.player?.isPlaying == true) {
                playerView.hideController()
                playerView.requestFocus()
            } else {
                controllerView.showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_CODE_EXTERNAL_SUBTITLE) {
            if (resultCode != Activity.RESULT_OK) {
                return
            }
            val subtitleUri = data?.data ?: return
            externalSubtitles.loadExternalSubtitle(subtitleUri, data.flags)
            return
        }
        if (requestCode == REQUEST_CODE_SUBTITLE_SEARCH) {
            externalSubtitles.handleSubtitleSearchResult(resultCode, data)
        }
    }

    override fun showToast(message: String) {
        Toast.makeText(activity, message, Toast.LENGTH_SHORT).show()
    }
}
