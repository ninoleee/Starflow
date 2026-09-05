package com.example.starflow

import android.app.Activity
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.media3.common.Player
import androidx.media3.ui.DefaultTimeBar
import androidx.media3.ui.PlayerView
import androidx.media3.ui.R as Media3UiR

internal class NativePlaybackControllerView(private val host: Host) {
    interface Host {
        val remote: NativePlaybackRemoteController
        val session: NativePlaybackSession
        val settings: NativePlaybackSettingsController
        val externalSubtitles: NativePlaybackExternalSubtitleController
        val target: NativePlaybackTarget
        val memory: NativePlaybackMemoryStore
        val diagnostics: NativePlaybackDiagnostics
        val activity: Activity
        val playerView: PlayerView
        val isTelevisionDevice: Boolean
    }

    var pendingControllerFocusTarget = ControllerFocusTarget.NONE

    var progressTimeBar: DefaultTimeBar? = null

    fun bindControllerChrome() {
        progressTimeBar = host.activity.findViewById(Media3UiR.id.exo_progress)
        host.activity.findViewById<View>(R.id.native_back)?.apply {
            if (host.isTelevisionDevice) {
                visibility = View.GONE
                isFocusable = false
                isFocusableInTouchMode = false
            } else {
                setOnClickListener { host.remote.handleNavigationBack() }
            }
        }
        val primaryTitle = host.target.buildPlaybackPagePrimaryTitle()
        val secondaryTitle = host.target.buildPlaybackPageSecondaryTitle()
        host.activity.findViewById<TextView?>(R.id.native_title)?.text = primaryTitle
        host.activity.findViewById<TextView?>(R.id.native_title_secondary)?.apply {
            if (secondaryTitle.isBlank()) {
                text = ""
                visibility = View.GONE
            } else {
                text = secondaryTitle
                visibility = View.VISIBLE
            }
        }
        updateProgressMarkers()
    }

    fun updateControllerAutoHidePolicy() {
        // Until playback settles the surface is still black, so the chrome is the
        // only thing naming what is loading and how fast it is arriving. Hold it
        // open until then instead of letting it time out over a black screen.
        val shouldAutoHide =
            isPlaybackStartupSettled() &&
                (!host.isTelevisionDevice || host.session.player?.isPlaying == true)
        host.playerView.setControllerShowTimeoutMs(
            if (shouldAutoHide) CONTROLLER_SHOW_TIMEOUT_MS else 0
        )
    }

    // STATE_READY covers sources that never render a frame (audio-only), so the
    // chrome is not left pinned on screen forever waiting for onRenderedFirstFrame.
    private fun isPlaybackStartupSettled(): Boolean {
        return host.diagnostics.playbackFirstFrameRendered ||
            host.session.player?.playbackState == Player.STATE_READY
    }

    fun hideTelevisionControllerAfterStartup() {
        if (!host.isTelevisionDevice || host.session.player?.playWhenReady != true) {
            return
        }
        if (host.externalSubtitles.subtitleSearchActive || host.settings.isOverlayDialogVisible()) {
            return
        }
        host.playerView.hideController()
        host.playerView.requestFocus()
    }

    fun configureRemoteControls() {
        host.playerView.isFocusable = true
        host.playerView.isFocusableInTouchMode = true
        host.playerView.descendantFocusability = ViewGroup.FOCUS_AFTER_DESCENDANTS
        host.playerView.setOnClickListener {
            showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
        }
        host.playerView.setControllerVisibilityListener(
            PlayerView.ControllerVisibilityListener { visibility ->
                host.diagnostics.networkSpeedVisible =
                    visibility == View.VISIBLE && host.playerView.isControllerFullyVisible
                if (host.diagnostics.networkSpeedVisible) {
                    host.diagnostics.updateNetworkSpeedLabelIfVisible()
                } else {
                    host.activity.findViewById<TextView?>(R.id.native_network_speed)?.visibility =
                        View.GONE
                }
                if (visibility == View.VISIBLE) {
                    applyPendingControllerFocus()
                    updateProgressMarkers()
                } else if (host.isTelevisionDevice && !host.settings.isOverlayDialogVisible()) {
                    host.playerView.requestFocus()
                }
            }
        )
        val focusableControlIds =
            if (host.isTelevisionDevice) {
                NativePlayerTvFocusPolicy.focusableControlIds
            } else {
                intArrayOf(
                    R.id.native_back,
                    Media3UiR.id.exo_rew,
                    Media3UiR.id.exo_play_pause,
                    Media3UiR.id.exo_ffwd,
                    Media3UiR.id.exo_subtitle,
                    R.id.native_audio_track_button,
                    R.id.native_subtitle_delay,
                    R.id.native_external_subtitle,
                    R.id.native_online_subtitle_search,
                    R.id.native_playback_settings,
                )
            }
        configureFocusability(focusableControlIds)

        if (!host.isTelevisionDevice) {
            configureHorizontalFocusChain(
                intArrayOf(Media3UiR.id.exo_rew, Media3UiR.id.exo_play_pause, Media3UiR.id.exo_ffwd)
            )
        }
        if (!host.isTelevisionDevice) {
            val settingsControlIds =
                intArrayOf(
                    Media3UiR.id.exo_subtitle,
                    R.id.native_online_subtitle_search,
                    R.id.native_external_subtitle,
                    R.id.native_subtitle_delay,
                    R.id.native_playback_settings,
                )
            configureHorizontalFocusChain(settingsControlIds)
        }
        if (!host.isTelevisionDevice) {
            configureHorizontalFocusChain(intArrayOf(R.id.native_back))
        }
        if (host.isTelevisionDevice) {
            configureDisabledFocusability(NativePlayerTvFocusPolicy.removedBottomRightControlIds)
            host.playerView.requestFocus()
        }
    }

    fun configureFocusability(ids: IntArray) {
        ids.forEach { id ->
            host.activity.findViewById<View?>(id)?.apply {
                isFocusable = true
                isFocusableInTouchMode = true
            }
        }
    }

    fun configureDisabledFocusability(ids: IntArray) {
        ids.forEach { id ->
            host.activity.findViewById<View?>(id)?.apply {
                isFocusable = false
                isFocusableInTouchMode = false
                nextFocusLeftId = View.NO_ID
                nextFocusRightId = View.NO_ID
                nextFocusUpId = View.NO_ID
                nextFocusDownId = View.NO_ID
            }
        }
    }

    fun configureHorizontalFocusChain(ids: IntArray) {
        val views =
            ids.map { id -> host.activity.findViewById<View?>(id) }
                .filterNotNull()
                .filter { view -> view.id != View.NO_ID }
        views.forEachIndexed { index, view ->
            view.nextFocusLeftId =
                views.getOrNull(index - 1)?.id ?: views.lastOrNull()?.id ?: view.id
            view.nextFocusRightId =
                views.getOrNull(index + 1)?.id ?: views.firstOrNull()?.id ?: view.id
        }
    }

    fun configureVerticalFocusLink(viewId: Int, upId: Int? = null, downId: Int? = null) {
        val view = host.activity.findViewById<View?>(viewId) ?: return
        if (upId != null && host.activity.findViewById<View?>(upId) != null) {
            view.nextFocusUpId = upId
        }
        if (downId != null && host.activity.findViewById<View?>(downId) != null) {
            view.nextFocusDownId = downId
        }
    }

    fun updateProgressMarkers() {
        val timeBar =
            progressTimeBar
                ?: host.activity.findViewById<DefaultTimeBar?>(Media3UiR.id.exo_progress)?.also {
                    progressTimeBar = it
                }
                ?: return
        val durationMs = host.session.player?.duration?.takeIf { it > 0L } ?: 0L
        if (durationMs <= 0L) {
            timeBar.setAdGroupTimesMs(longArrayOf(), booleanArrayOf(), 0)
            return
        }
        val markers =
            NativePlaybackMarkers.buildPlaybackMarkerPositionsMs(
                durationMs,
                host.target.decodePlaybackTargetObject(),
                host.memory.loadSeriesSkipPreference(host.target.seriesKey),
            )
        timeBar.setAdGroupTimesMs(markers, BooleanArray(markers.size), markers.size)
    }

    fun showControllerForRemoteFocus(target: ControllerFocusTarget) {
        pendingControllerFocusTarget = target
        host.playerView.showController()
        if (host.isTelevisionDevice) {
            host.playerView.post { applyPendingControllerFocus() }
        }
    }

    fun applyPendingControllerFocus() {
        if (!host.isTelevisionDevice) {
            pendingControllerFocusTarget = ControllerFocusTarget.NONE
            return
        }
        if (pendingControllerFocusTarget == ControllerFocusTarget.NONE) {
            return
        }
        if (
            !host.playerView.isControllerFullyVisible &&
                pendingControllerFocusTarget != ControllerFocusTarget.PLAYER
        ) {
            host.playerView.post { applyPendingControllerFocus() }
            return
        }

        val handled =
            when (pendingControllerFocusTarget) {
                ControllerFocusTarget.NONE -> false
                ControllerFocusTarget.PLAYER -> host.playerView.requestFocus()
                ControllerFocusTarget.PRIMARY ->
                    requestFocusForAny(
                        if (host.isTelevisionDevice) {
                            NativePlayerTvFocusPolicy.primaryFocusOrder
                        } else {
                            intArrayOf(
                                Media3UiR.id.exo_play_pause,
                                Media3UiR.id.exo_ffwd,
                                Media3UiR.id.exo_rew,
                                R.id.native_playback_settings,
                            )
                        }
                    )

                ControllerFocusTarget.SETTINGS ->
                    requestFocusForAny(
                        if (host.isTelevisionDevice) {
                            NativePlayerTvFocusPolicy.primaryFocusOrder
                        } else {
                            intArrayOf(
                                R.id.native_playback_settings,
                                R.id.native_online_subtitle_search,
                                R.id.native_external_subtitle,
                                Media3UiR.id.exo_subtitle,
                                Media3UiR.id.exo_play_pause,
                            )
                        }
                    )

                ControllerFocusTarget.AUDIO ->
                    requestFocusForAny(
                        if (host.isTelevisionDevice) {
                            NativePlayerTvFocusPolicy.primaryFocusOrder
                        } else {
                            intArrayOf(
                                R.id.native_playback_settings,
                                Media3UiR.id.exo_subtitle,
                                Media3UiR.id.exo_play_pause,
                            )
                        }
                    )

                ControllerFocusTarget.SUBTITLE ->
                    requestFocusForAny(
                        if (host.isTelevisionDevice) {
                            NativePlayerTvFocusPolicy.primaryFocusOrder
                        } else {
                            intArrayOf(
                                Media3UiR.id.exo_subtitle,
                                R.id.native_online_subtitle_search,
                                R.id.native_external_subtitle,
                                R.id.native_subtitle_delay,
                                R.id.native_playback_settings,
                            )
                        }
                    )
            }
        if (!handled) {
            host.playerView.requestFocus()
        }
        pendingControllerFocusTarget = ControllerFocusTarget.NONE
    }

    fun requestFocusForAny(ids: IntArray): Boolean {
        ids.forEach { id ->
            val view = host.activity.findViewById<View?>(id) ?: return@forEach
            if (!view.isShown || !view.isEnabled || !view.isFocusable) {
                return@forEach
            }
            if (view.requestFocus()) {
                return true
            }
        }
        return false
    }

    fun restoreControllerFocusIfNeeded(target: ControllerFocusTarget) {
        if (host.activity.isFinishing || host.externalSubtitles.subtitleSearchActive) {
            return
        }
        host.playerView.post {
            enterImmersiveMode()
            showControllerForRemoteFocus(target)
        }
    }

    fun enterImmersiveMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            host.activity.window.insetsController?.hide(
                android.view.WindowInsets.Type.statusBars() or
                    android.view.WindowInsets.Type.navigationBars()
            )
            host.activity.window.insetsController?.systemBarsBehavior =
                android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            return
        }

        @Suppress("DEPRECATION")
        host.activity.window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
    }

    fun hideVideoSurfaceForOverlay() {
        host.playerView.hideController()
        host.playerView.visibility = View.INVISIBLE
        host.playerView.videoSurfaceView?.visibility = View.INVISIBLE
    }

    fun restoreVideoSurfaceIfNeeded() {
        host.playerView.visibility = View.VISIBLE
        host.playerView.videoSurfaceView?.visibility = View.VISIBLE
        if (host.isTelevisionDevice && host.session.player?.playWhenReady == true) {
            host.playerView.hideController()
            host.playerView.requestFocus()
        } else {
            showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
        }
    }
}
