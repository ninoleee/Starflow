package com.example.starflow

import android.app.Activity
import android.app.AlertDialog
import android.os.SystemClock
import android.view.KeyEvent
import androidx.media3.common.Player
import androidx.media3.ui.PlayerView

internal class NativePlaybackRemoteController(
    private val host: Host,
    private val now: () -> Long = SystemClock::uptimeMillis,
) {
    private companion object {
        const val SEEK_REPEAT_INTERVAL_MS = 250L
    }

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

    private data class SeekPress(
        val deviceId: Int,
        val keyCode: Int,
        val downTime: Long,
        val player: Player,
    ) {
        fun matches(event: KeyEvent): Boolean =
            deviceId == event.deviceId && keyCode == event.keyCode && downTime == event.downTime
    }

    private val seekPolicy = NativePlayerTvSeekPolicy(now)
    private var seekPress: SeekPress? = null
    private var pendingSeekPositionMs: Long? = null
    private var lastSeekAtMs = 0L
    private var pendingSeekRunnable: Runnable? = null
    private val handledPlaybackKeys = mutableMapOf<Pair<Int, Int>, Long>()

    fun resetInputState() {
        handledPlaybackKeys.clear()
        resetTvSeekHold()
    }

    fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (host.isTelevisionDevice && isTvSeekKeyCode(event.keyCode)) {
            return handleTvDirectionalSeek(event)
        }
        if (handlePlaybackKey(event)) {
            resetTvSeekHold()
            return true
        }
        if (event.action != KeyEvent.ACTION_DOWN) {
            return false
        }
        resetTvSeekHold()

        when (event.keyCode) {
            KeyEvent.KEYCODE_BACK,
            KeyEvent.KEYCODE_ESCAPE -> {
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

            KeyEvent.KEYCODE_MEDIA_REWIND -> {
                if (host.session.seekBy(-10_000L)) {
                    return true
                }
            }

            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> {
                if (host.session.seekBy(10_000L)) {
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

    private fun cancelPendingSeekCallback() {
        pendingSeekRunnable?.let { host.playerView.removeCallbacks(it) }
        pendingSeekRunnable = null
    }

    private fun resetTvSeekHold() {
        cancelPendingSeekCallback()
        seekPress = null
        pendingSeekPositionMs = null
        seekPolicy.reset()
    }

    private fun canSeek(player: Player): Boolean =
        host.session.player === player &&
            !host.activity.isFinishing && !host.activity.isDestroyed &&
            host.activity.hasWindowFocus() && host.playerView.isAttachedToWindow &&
            !host.externalSubtitles.subtitleSearchActive &&
            !host.settings.isOverlayDialogVisible() &&
            exitConfirmationDialog?.isShowing != true &&
            player.playbackState != Player.STATE_IDLE && player.playbackState != Player.STATE_ENDED

    private fun flushPendingSeek() {
        cancelPendingSeekCallback()
        val press = seekPress ?: return
        if (!canSeek(press.player)) {
            resetTvSeekHold()
            return
        }
        val positionMs = pendingSeekPositionMs ?: return
        pendingSeekPositionMs = null
        lastSeekAtMs = now()
        if (!host.session.seekTo(positionMs)) {
            host.controllerView.showControllerForRemoteFocus(ControllerFocusTarget.PLAYER)
        }
    }

    private fun handleTvDirectionalSeek(event: KeyEvent): Boolean {
        val owned = seekPress?.matches(event) == true
        if (event.action == KeyEvent.ACTION_UP) {
            if (!owned) return false
            if (!event.isCanceled) flushPendingSeek()
            resetTvSeekHold()
            return true
        }
        if (event.action != KeyEvent.ACTION_DOWN) return false
        val player = host.session.player
        if (player == null || !canSeek(player)) {
            resetTvSeekHold()
            return owned
        }
        if (event.isCanceled) {
            resetTvSeekHold()
            return true
        }
        // A repeat arriving after focus loss or a session change cannot start a new hold.
        val samePress = owned && seekPress?.player === player
        if (!samePress && event.repeatCount > 0) return true
        val previousTarget = pendingSeekPositionMs.takeIf { seekPress?.player === player }
        if (!samePress) {
            resetTvSeekHold()
            seekPress = SeekPress(event.deviceId, event.keyCode, event.downTime, player)
        }
        val direction = if (event.keyCode == KeyEvent.KEYCODE_DPAD_LEFT) -1L else 1L
        val stepMs = seekPolicy.stepMs(event.keyCode, event.repeatCount) * direction
        val baseMs = previousTarget ?: player.currentPosition.coerceAtLeast(0L)
        val durationMs = player.duration.takeIf { it > 0L } ?: Long.MAX_VALUE
        pendingSeekPositionMs = (baseMs + stepMs).coerceIn(0L, durationMs)
        val delayMs = SEEK_REPEAT_INTERVAL_MS - (now() - lastSeekAtMs)
        if (!samePress || delayMs <= 0L) {
            flushPendingSeek()
        } else if (pendingSeekRunnable == null) {
            val callback = object : Runnable {
                override fun run() {
                    if (pendingSeekRunnable !== this) return
                    flushPendingSeek()
                }
            }
            pendingSeekRunnable = callback
            host.playerView.postDelayed(callback, delayMs)
        }
        return true
    }
}
