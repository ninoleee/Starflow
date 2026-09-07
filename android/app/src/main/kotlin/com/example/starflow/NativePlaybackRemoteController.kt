package com.example.starflow

import android.app.Activity
import android.app.AlertDialog
import android.view.KeyEvent
import androidx.media3.common.Player
import androidx.media3.ui.PlayerView

internal class NativePlaybackRemoteController(private val host: Host) {
    interface Host {
        val controllerView: NativePlaybackControllerView
        val externalSubtitles: NativePlaybackExternalSubtitleController
        val session: NativePlaybackSession
        val episodes: NativePlaybackEpisodeController
        val settings: NativePlaybackSettingsController
        val subtitles: NativePlaybackTrackController
        val isTelevisionDevice: Boolean
        val playerView: PlayerView
        val activity: Activity
    }

    private var exitConfirmationDialog: AlertDialog? = null

    fun dismissExitConfirmation() {
        exitConfirmationDialog?.dismiss()
        exitConfirmationDialog = null
    }

    private val seekPolicy = NativePlayerTvSeekPolicy()
    private val handledPlaybackKeys = mutableMapOf<Pair<Int, Int>, Long>()

    fun resetInputState() {
        handledPlaybackKeys.clear()
        resetTvSeekHold()
    }

    fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (handlePlaybackKey(event)) {
            return true
        }
        if (event.action != KeyEvent.ACTION_DOWN) {
            if (
                host.isTelevisionDevice &&
                    event.action == KeyEvent.ACTION_UP &&
                    isTvSeekKeyCode(event.keyCode)
            ) {
                resetTvSeekHold(keyCode = event.keyCode)
                return true
            }
            return false
        }

        when (event.keyCode) {
            KeyEvent.KEYCODE_BACK,
            KeyEvent.KEYCODE_ESCAPE -> {
                resetTvSeekHold()
                if (
                    !host.externalSubtitles.subtitleSearchActive &&
                        host.playerView.isControllerFullyVisible
                ) {
                    host.controllerView.hideController()
                    host.playerView.requestFocus()
                    return true
                }
                if (!host.externalSubtitles.subtitleSearchActive && host.isTelevisionDevice) {
                    showExitConfirmation()
                    return true
                }
            }

            KeyEvent.KEYCODE_DPAD_UP -> {
                if (host.isTelevisionDevice && !host.playerView.isControllerFullyVisible) {
                    host.controllerView.showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
                    return true
                }
            }

            KeyEvent.KEYCODE_DPAD_DOWN -> {
                if (host.isTelevisionDevice && !host.playerView.isControllerFullyVisible) {
                    if (!host.episodes.openEpisodeSelectionDialog()) {
                        host.settings.openPlaybackSettingsDialog()
                    }
                    return true
                }
            }

            KeyEvent.KEYCODE_DPAD_LEFT -> {
                if (handleTvDirectionalSeek(event, direction = -1)) {
                    return true
                }
            }

            KeyEvent.KEYCODE_DPAD_RIGHT -> {
                if (handleTvDirectionalSeek(event, direction = 1)) {
                    return true
                }
            }

            KeyEvent.KEYCODE_MEDIA_REWIND -> {
                if (host.session.seekBy(-10_000L)) {
                    resetTvSeekHold()
                    return true
                }
            }

            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> {
                if (host.session.seekBy(10_000L)) {
                    resetTvSeekHold()
                    return true
                }
            }

            KeyEvent.KEYCODE_MENU,
            KeyEvent.KEYCODE_INFO,
            KeyEvent.KEYCODE_SETTINGS -> {
                host.settings.openPlaybackSettingsDialog()
                return true
            }

            KeyEvent.KEYCODE_CAPTIONS -> {
                host.subtitles.openSubtitleTrackSelectionDialog()
                return true
            }

            KeyEvent.KEYCODE_SEARCH -> {
                host.externalSubtitles.openOnlineSubtitleSearch()
                return true
            }
        }
        return false
    }

    private fun handlePlaybackKey(event: KeyEvent): Boolean {
        val isConfirmKey = event.keyCode == KeyEvent.KEYCODE_DPAD_CENTER ||
            event.keyCode == KeyEvent.KEYCODE_ENTER ||
            event.keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER ||
            event.keyCode == KeyEvent.KEYCODE_BUTTON_A
        val isMediaKey = event.keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE ||
            event.keyCode == KeyEvent.KEYCODE_HEADSETHOOK ||
            event.keyCode == KeyEvent.KEYCODE_SPACE ||
            event.keyCode == KeyEvent.KEYCODE_MEDIA_PLAY ||
            event.keyCode == KeyEvent.KEYCODE_MEDIA_PAUSE
        if (!isConfirmKey && !isMediaKey) return false

        // Ownership lasts until key-up, even if the first press changes focus or opens chrome.
        val key = event.deviceId to event.keyCode
        if (handledPlaybackKeys[key] == event.downTime) {
            if (event.action == KeyEvent.ACTION_UP) {
                handledPlaybackKeys.remove(key)
            }
            return true
        }
        if (event.action != KeyEvent.ACTION_DOWN) return false
        if (
            host.externalSubtitles.subtitleSearchActive ||
                host.settings.isOverlayDialogVisible() ||
                exitConfirmationDialog?.isShowing == true
        ) {
            return false
        }
        val progressFocused = host.controllerView.progressTimeBar?.hasFocus() == true
        val progressPlaybackControl = NativePlayerTvFocusPolicy.shouldToggleFromProgress(
            host.isTelevisionDevice, progressFocused, overlayVisible = false,
        )
        if (isConfirmKey && !host.isTelevisionDevice) {
            return false
        }
        handledPlaybackKeys[key] = event.downTime
        if (event.repeatCount != 0 || event.isCanceled) return true

        val handled = when (event.keyCode) {
            KeyEvent.KEYCODE_MEDIA_PLAY -> host.session.setPlayWhenReady(true)
            KeyEvent.KEYCODE_MEDIA_PAUSE -> host.session.setPlayWhenReady(false)
            else -> host.session.togglePlayback()
        }
        if (handled) {
            if (progressPlaybackControl) {
                host.playerView.showController()
            } else {
                host.controllerView.showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
            }
        }
        return true
    }

    private fun showExitConfirmation() {
        val existingDialog = exitConfirmationDialog
        if (existingDialog?.isShowing == true) {
            return
        }

        exitConfirmationDialog =
            AlertDialog.Builder(host.activity)
                .setTitle("退出播放")
                .setMessage("确认退出当前播放吗？")
                .setNegativeButton("继续播放", null)
                .setPositiveButton("退出") { _, _ -> host.activity.finish() }
                .create()
                .apply {
                    setOnDismissListener {
                        exitConfirmationDialog = null
                        host.controllerView.restoreControllerFocusIfNeeded(ControllerFocusTarget.PLAYER)
                    }
                    show()
                }
    }

    fun handleNavigationBack() {
        if (host.isTelevisionDevice) {
            showExitConfirmation()
        } else {
            host.activity.finish()
        }
    }

    private fun isTvSeekKeyCode(keyCode: Int): Boolean {
        return keyCode == KeyEvent.KEYCODE_DPAD_LEFT || keyCode == KeyEvent.KEYCODE_DPAD_RIGHT
    }

    private fun resetTvSeekHold(keyCode: Int? = null) {
        seekPolicy.reset(keyCode)
    }

    private fun handleTvDirectionalSeek(event: KeyEvent, direction: Int): Boolean {
        if (
            !host.isTelevisionDevice ||
                host.externalSubtitles.subtitleSearchActive ||
                host.settings.isOverlayDialogVisible()
        ) {
            return false
        }
        val currentPlayer = host.session.player ?: return false
        if (
            currentPlayer.playbackState == Player.STATE_IDLE ||
                currentPlayer.playbackState == Player.STATE_ENDED
        ) {
            return false
        }
        val keyCode = event.keyCode
        if (!isTvSeekKeyCode(keyCode)) {
            return false
        }
        val stepMs = seekPolicy.stepMs(keyCode, event.repeatCount)
        host.session.seekBy(stepMs * direction.toLong())
        return true
    }
}
