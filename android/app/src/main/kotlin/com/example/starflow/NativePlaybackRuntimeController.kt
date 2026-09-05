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
        val episodes: NativePlaybackEpisodeController

        fun showToast(message: String)

        val activity: Activity
    }

    var lastSavedPositionMs: Long = -1L

    private val playbackWatchdogHandler by lazy { Handler(Looper.getMainLooper()) }

    private val playbackRuntimeHandler by lazy { Handler(Looper.getMainLooper()) }

    private var playbackRuntimeActive = false
    private var runtimeGeneration = 0L
    private var completedByAutoSkip = false

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
                val generation = runtimeGeneration
                host.episodes.tick()
                maybeApplyAutoSkip()
                persistPlaybackProgress()
                host.diagnostics.logPlaybackRuntimeIfNeeded()
                host.diagnostics.updateNetworkSpeedLabelIfVisible()
                if (playbackRuntimeActive && generation == runtimeGeneration) {
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
        runtimeGeneration += 1L
        playbackRuntimeHandler.removeCallbacks(playbackRuntimeRunnable)
        playbackRuntimeActive = true
        syncSkipFlagsWithCurrentPosition()
        playbackRuntimeHandler.postDelayed(
            playbackRuntimeRunnable,
            PLAYBACK_RUNTIME_INITIAL_DELAY_MS,
        )
    }

    fun stopPlaybackRuntimeLoop() {
        runtimeGeneration += 1L
        playbackRuntimeActive = false
        playbackRuntimeHandler.removeCallbacks(playbackRuntimeRunnable)
        host.diagnostics.playbackFirstFrameRendered = false
        host.diagnostics.playbackLastRuntimeLogAtMs = 0L
        introSkipApplied = false
        outroSkipApplied = false
    }

    fun resetForNewMedia() {
        lastSavedPositionMs = -1L
        completedByAutoSkip = false
        introSkipApplied = false
        outroSkipApplied = false
    }

    fun markAutoSkipCompleted() {
        completedByAutoSkip = true
        persistPlaybackProgress(force = true)
    }

    fun onSkipPreferenceChanged() {
        host.episodes.cancelAutomaticAdvance()
        introSkipApplied = false
        outroSkipApplied = false
        syncSkipFlagsWithCurrentPosition()
        maybeApplyAutoSkip()
    }

    fun onUserSeek() {
        completedByAutoSkip = false
        syncSkipFlagsWithCurrentPosition()
        introSkipApplied = true
        val current = host.session.player ?: return
        val preference = host.memory.loadSeriesSkipPreference(host.target.seriesKey)
        val boundary =
            NativePlaybackSkipPolicy.endBoundaryMs(
                current.duration,
                preference?.optBoolean("enabled", false) == true,
                preference?.optLong("outroDurationMs", 0L) ?: 0L,
            )
        if (boundary > 0L && current.currentPosition >= boundary) outroSkipApplied = true
        host.episodes.onUserSeek()
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
                host.externalSubtitles.subtitleSearchActive ||
                host.episodes.isSwitching
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
            if (
                positionMs >= introDurationMs || (durationMs > 0L && introDurationMs >= durationMs)
            ) {
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

        if (host.episodes.advanceToAdjacentEpisode(forward = true, reason = "outro")) return
        outroSkipApplied = true
        markAutoSkipCompleted()
        host.session.setPlayWhenReady(false)
        host.showToast("本集已播放完毕")
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
        val outroDurationMs = skipPreference.optLong("outroDurationMs", 0L)
        if (
            durationMs <= 0L || outroDurationMs <= 0L || positionMs < durationMs - outroDurationMs
        ) {
            outroSkipApplied = false
            completedByAutoSkip = false
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
            completedByAutoSkip = completedByAutoSkip,
        )
    }
}
