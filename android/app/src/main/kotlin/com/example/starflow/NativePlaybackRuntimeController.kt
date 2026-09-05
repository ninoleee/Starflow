package com.example.starflow

import android.app.Activity
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.media3.common.Player

internal class NativePlaybackRuntimeController(private val host: Host) {
    interface Host {
        val diagnostics: NativePlaybackDiagnostics
        val session: NativePlaybackSession
        val externalSubtitles: NativePlaybackExternalSubtitleController
        val memory: NativePlaybackMemoryStore
        val recovery: NativePlaybackRecoveryController
        val target: NativePlaybackTarget

        fun showToast(message: String)

        val activity: Activity
    }

    var lastSavedPositionMs: Long = -1L

    private val playbackWatchdogHandler = Handler(Looper.getMainLooper())

    private val playbackRuntimeHandler = Handler(Looper.getMainLooper())

    private var playbackRuntimeActive = false

    private var playbackWatchdogActive = false

    val playbackWatchdogPolicy = NativePlaybackWatchdogPolicy()

    private val playbackWatchdogRunnable =
        object : Runnable {
            override fun run() {
                if (!playbackWatchdogActive) {
                    return
                }
                val shouldContinue = evaluatePlaybackWatchdog()
                if (playbackWatchdogActive && shouldContinue) {
                    playbackWatchdogHandler.postDelayed(this, PLAYBACK_WATCHDOG_INTERVAL_MS)
                }
            }
        }

    private val playbackRuntimeRunnable =
        object : Runnable {
            override fun run() {
                if (!playbackRuntimeActive) {
                    return
                }
                maybeApplyAutoSkip()
                persistPlaybackProgress()
                host.diagnostics.logPlaybackRuntimeIfNeeded()
                host.diagnostics.updateNetworkSpeedLabelIfVisible()
                if (playbackRuntimeActive) {
                    playbackRuntimeHandler.postDelayed(this, PLAYBACK_RUNTIME_INTERVAL_MS)
                }
            }
        }

    var introSkipApplied = false

    var outroSkipApplied = false

    fun startPlaybackWatchdog() {
        playbackWatchdogHandler.removeCallbacks(playbackWatchdogRunnable)
        playbackWatchdogActive = true
        resetPlaybackWatchdogProgress(host.session.player?.currentPosition ?: 0L)
        playbackWatchdogHandler.postDelayed(playbackWatchdogRunnable, PLAYBACK_WATCHDOG_INTERVAL_MS)
    }

    fun stopPlaybackWatchdog() {
        playbackWatchdogActive = false
        playbackWatchdogHandler.removeCallbacks(playbackWatchdogRunnable)
        playbackWatchdogPolicy.clearRecoveries()
    }

    fun startPlaybackRuntimeLoop() {
        playbackRuntimeHandler.removeCallbacks(playbackRuntimeRunnable)
        playbackRuntimeActive = true
        syncSkipFlagsWithCurrentPosition()
        playbackRuntimeHandler.postDelayed(
            playbackRuntimeRunnable,
            PLAYBACK_RUNTIME_INITIAL_DELAY_MS,
        )
    }

    fun stopPlaybackRuntimeLoop() {
        playbackRuntimeActive = false
        playbackRuntimeHandler.removeCallbacks(playbackRuntimeRunnable)
        host.diagnostics.playbackFirstFrameRendered = false
        host.diagnostics.playbackLastRuntimeLogAtMs = 0L
        introSkipApplied = false
        outroSkipApplied = false
    }

    fun resetPlaybackWatchdogProgress(positionMs: Long) {
        markPlaybackWatchdogActivity(positionMs)
        playbackWatchdogPolicy.clearRecoveries()
    }

    fun markPlaybackWatchdogActivity(positionMs: Long) {
        val currentPlayer = host.session.player
        playbackWatchdogPolicy.markActivity(
            positionMs,
            currentPlayer?.let { it.bufferedPosition.coerceAtLeast(it.currentPosition) },
            currentPlayer?.bufferedPercentage,
        )
    }

    fun maybeApplyAutoSkip() {
        val currentPlayer = host.session.player ?: return
        if (
            !currentPlayer.playWhenReady ||
                currentPlayer.playbackState != Player.STATE_READY ||
                host.externalSubtitles.subtitleSearchActive
        ) {
            return
        }
        val skipPreference = host.memory.loadSeriesSkipPreference(host.target.seriesKey)
        if (skipPreference?.optBoolean("enabled", false) != true) {
            introSkipApplied = true
            outroSkipApplied = true
            return
        }

        val positionMs = currentPlayer.currentPosition.coerceAtLeast(0L)
        val durationMs = currentPlayer.duration.takeIf { it > 0L } ?: 0L
        val introDurationMs = skipPreference.optLong("introDurationMs", 0L).coerceAtLeast(0L)
        if (!introSkipApplied && introDurationMs > 0L) {
            if (positionMs >= introDurationMs) {
                introSkipApplied = true
            } else {
                introSkipApplied = true
                currentPlayer.seekTo(introDurationMs)
                resetPlaybackWatchdogProgress(introDurationMs)
                host.showToast("已自动跳过片头")
                return
            }
        }

        val outroDurationMs = skipPreference.optLong("outroDurationMs", 0L).coerceAtLeast(0L)
        if (outroSkipApplied || outroDurationMs <= 0L || durationMs <= 0L) {
            return
        }
        val triggerPositionMs = durationMs - outroDurationMs
        if (triggerPositionMs <= 0L || positionMs < triggerPositionMs) {
            return
        }

        outroSkipApplied = true
        val seekTargetMs = (durationMs - OUTRO_SKIP_END_MARGIN_MS).coerceAtLeast(0L)
        currentPlayer.seekTo(seekTargetMs)
        resetPlaybackWatchdogProgress(seekTargetMs)
        host.showToast("已自动跳过片尾")
    }

    fun syncSkipFlagsWithCurrentPosition() {
        val currentPlayer = host.session.player ?: return
        val skipPreference = host.memory.loadSeriesSkipPreference(host.target.seriesKey)
        if (skipPreference?.optBoolean("enabled", false) != true) {
            introSkipApplied = true
            outroSkipApplied = true
            return
        }

        val positionMs = currentPlayer.currentPosition.coerceAtLeast(0L)
        val durationMs = currentPlayer.duration.takeIf { it > 0L } ?: 0L
        val introDurationMs = skipPreference.optLong("introDurationMs", 0L)
        introSkipApplied = introDurationMs <= 0L || positionMs >= introDurationMs

        val outroDurationMs = skipPreference.optLong("outroDurationMs", 0L)
        outroSkipApplied =
            if (durationMs <= 0L || outroDurationMs <= 0L) {
                false
            } else {
                durationMs - positionMs <= outroDurationMs
            }
    }

    private fun evaluatePlaybackWatchdog(): Boolean {
        val currentPlayer = host.session.player ?: return true
        val inPictureInPicture =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && host.activity.isInPictureInPictureMode
        if (
            host.externalSubtitles.subtitleSearchActive ||
                (!host.activity.hasWindowFocus() && !inPictureInPicture) ||
                !currentPlayer.playWhenReady ||
                currentPlayer.playbackState == Player.STATE_IDLE ||
                currentPlayer.playbackState == Player.STATE_ENDED
        ) {
            resetPlaybackWatchdogProgress(currentPlayer.currentPosition)
            return true
        }

        val positionMs = currentPlayer.currentPosition.coerceAtLeast(0L)
        if (
            !playbackWatchdogPolicy.isStalled(
                positionMs = positionMs,
                bufferedPositionMs = currentPlayer.bufferedPosition,
                bufferedPercentage = currentPlayer.bufferedPercentage,
                buffering = currentPlayer.playbackState == Player.STATE_BUFFERING,
                playing = currentPlayer.isPlaying,
            )
        ) {
            return true
        }

        return host.recovery.recoverPlaybackStall(positionMs)
    }

    fun persistPlaybackProgress(force: Boolean = false) {
        val currentPlayer = host.session.player ?: return
        val resolvedDuration = currentPlayer.duration.takeIf { it > 0L } ?: 0L
        val resolvedPosition = currentPlayer.currentPosition.coerceAtLeast(0L)
        if (
            !force &&
                kotlin.math.abs(resolvedPosition - lastSavedPositionMs) <
                    PLAYBACK_PROGRESS_PERSIST_INTERVAL_MS
        ) {
            return
        }
        lastSavedPositionMs = resolvedPosition
        host.memory.savePlaybackEntry(
            targetJson = host.target.playbackTargetJson,
            itemKey = host.target.playbackItemKey,
            seriesKey = host.target.seriesKey,
            positionMs = resolvedPosition,
            durationMs = resolvedDuration,
            synchronous = force,
        )
    }
}
