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

    fun dispatchKeyEvent(event: KeyEvent): Boolean {
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
                    host.controllerView.pendingControllerFocusTarget = ControllerFocusTarget.PLAYER
                    host.playerView.hideController()
                    host.playerView.requestFocus()
                    return true
                }
                if (!host.externalSubtitles.subtitleSearchActive && host.isTelevisionDevice) {
                    showExitConfirmation()
                    return true
                }
            }

            KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_ENTER,
            KeyEvent.KEYCODE_NUMPAD_ENTER,
            KeyEvent.KEYCODE_BUTTON_A -> {
                if (host.isTelevisionDevice && !host.playerView.isControllerFullyVisible) {
                    if (host.session.togglePlayback()) {
                        host.controllerView.showControllerForRemoteFocus(
                            ControllerFocusTarget.PLAYER
                        )
                        return true
                    }
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

            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_HEADSETHOOK,
            KeyEvent.KEYCODE_SPACE -> {
                if (host.session.togglePlayback()) {
                    host.controllerView.showControllerForRemoteFocus(
                        if (host.isTelevisionDevice) {
                            ControllerFocusTarget.PLAYER
                        } else {
                            ControllerFocusTarget.PRIMARY
                        }
                    )
                    return true
                }
            }

            KeyEvent.KEYCODE_MEDIA_PLAY -> {
                if (host.session.setPlayWhenReady(true)) {
                    host.controllerView.showControllerForRemoteFocus(
                        if (host.isTelevisionDevice) {
                            ControllerFocusTarget.PLAYER
                        } else {
                            ControllerFocusTarget.PRIMARY
                        }
                    )
                    return true
                }
            }

            KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                if (host.session.setPlayWhenReady(false)) {
                    host.controllerView.showControllerForRemoteFocus(
                        if (host.isTelevisionDevice) {
                            ControllerFocusTarget.PLAYER
                        } else {
                            ControllerFocusTarget.PRIMARY
                        }
                    )
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
                        if (!host.activity.isFinishing) {
                            host.playerView.post {
                                host.controllerView.enterImmersiveMode()
                                host.playerView.requestFocus()
                            }
                        }
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
