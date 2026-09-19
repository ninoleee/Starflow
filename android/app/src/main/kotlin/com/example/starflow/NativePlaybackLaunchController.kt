package com.example.starflow

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.ResultReceiver
import androidx.media3.common.PlaybackException
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_LAUNCH_RESULT_RECEIVER
import com.example.starflow.NativePlaybackActivity.Companion.RESULT_DATA_MESSAGE
import com.example.starflow.NativePlaybackActivity.Companion.RESULT_DATA_REQUEST_ID
import com.example.starflow.NativePlaybackActivity.Companion.RESULT_PLAYBACK_CANCELLED

internal class NativePlaybackLaunchController(
    private val host: Host,
    private val playbackLaunchTimeoutHandler: Handler = Handler(Looper.getMainLooper()),
    private val now: () -> Long = SystemClock::elapsedRealtime,
) {
    interface Host {
        val fntv: NativeFntvController
        val session: NativePlaybackSession
        val diagnostics: NativePlaybackDiagnostics
        val episodes: NativePlaybackEpisodeController
        val activity: Activity
        val recovery: NativePlaybackRecoveryController
    }

    private var launchResultReceiver: ResultReceiver? = null

    private var launchRequestId = ""

    var launchResultDelivered = false
        private set

    private var startupPending = false

    val isStartupPending: Boolean
        get() = startupPending

    private var startupBufferedPositionMs = 0L

    private var startupBufferedPercentage = 0
    private val startupProgress = PlaybackBufferProgress()
    private var startupDeadlineMs = 0L
    private var startupLastProgressAtMs = 0L
    private var startupAttempts = 0

    private val playbackLaunchTimeoutRunnable = Runnable {
        if (startupPending && !host.activity.isFinishing && !host.activity.isDestroyed) {
            val timeMs = now()
            consumeStartupProgress(timeMs)
            if (startupTimedOut(timeMs)) {
                handleStartupTimeout(timeMs)
            } else {
                armPlaybackLaunchTimeout()
            }
        }
    }

    private var playbackErrorDialog: AlertDialog? = null

    private fun startupTimedOut(timeMs: Long): Boolean =
        timeMs >= startupDeadlineMs ||
            timeMs - startupLastProgressAtMs >= PlaybackPolicyValues.exoStartupNoProgressTimeoutMs

    private fun handleStartupTimeout(timeMs: Long) {
        val player = host.session.player
        NativeAppLogger.warning(
            "playback.reliability",
            "Playback startup timeout engine=exo phase=preparing " +
                "reason=${if (timeMs >= startupDeadlineMs) "hard-deadline" else "no-progress"} " +
                "idleMs=${(timeMs - startupLastProgressAtMs).coerceAtLeast(0L)} " +
                "attempt=$startupAttempts state=${player?.playbackState} " +
                "loading=${player?.isLoading} positionMs=${player?.currentPosition ?: 0L} " +
                "bufferedPositionMs=$startupBufferedPositionMs " +
                "bufferedPercentage=$startupBufferedPercentage",
        )
        handlePlaybackFailure("视频画面迟迟没有出现，请检查网络或重试播放。")
    }

    private fun consumeStartupProgress(timeMs: Long) {
        val player = host.session.player ?: return
        val bufferedPositionMs = player.bufferedPosition.coerceAtLeast(0L)
        val bufferedPercentage = player.bufferedPercentage.coerceIn(0, 100)
        // Absolute buffer positions include the intro/resume offset, not just downloaded media.
        if (startupProgress.observe(player.totalBufferedDuration.coerceAtLeast(0L), 0)) {
            startupLastProgressAtMs = maxOf(startupLastProgressAtMs, timeMs)
        }
        val receivedAtMs = host.session.playbackTransferProgress?.lastProgressAtMs ?: -1L
        startupLastProgressAtMs = maxOf(startupLastProgressAtMs, receivedAtMs)
        startupBufferedPositionMs = bufferedPositionMs
        startupBufferedPercentage = bufferedPercentage
    }

    fun applyIntent(intent: Intent) {
        resetStartupDeadline()
        launchRequestId =
            intent.getStringExtra(NativePlaybackActivity.EXTRA_LAUNCH_REQUEST_ID)?.trim().orEmpty()
        launchResultReceiver = readLaunchResultReceiver(intent)
        launchResultDelivered = false
    }

    fun dismissFailure() {
        playbackErrorDialog?.dismiss()
        playbackErrorDialog = null
    }

    @Suppress("DEPRECATION")
    private fun readLaunchResultReceiver(playbackIntent: Intent): ResultReceiver? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            playbackIntent.getParcelableExtra(
                EXTRA_LAUNCH_RESULT_RECEIVER,
                ResultReceiver::class.java,
            )
        } else {
            playbackIntent.getParcelableExtra(EXTRA_LAUNCH_RESULT_RECEIVER)
        }
    }

    fun reportPlaybackLaunchResult(resultCode: Int, message: String = "") {
        if (resultCode == NativePlaybackActivity.RESULT_PLAYBACK_READY) resetStartupDeadline()
        if (launchResultDelivered) {
            return
        }
        launchResultDelivered = true
        val receiver = launchResultReceiver
        launchResultReceiver = null
        receiver?.send(
            resultCode,
            Bundle().apply {
                putString(RESULT_DATA_REQUEST_ID, launchRequestId)
                putString(RESULT_DATA_MESSAGE, message)
            },
        )
    }

    fun handlePlayerError(error: PlaybackException) {
        handlePlaybackFailure(buildPlaybackErrorMessage(error))
    }

    fun handlePlaybackFailure(message: String) {
        if (host.fntv.recoverQualityFailure()) return
        host.episodes.onPlaybackFailed()
        val launchPending = !launchResultDelivered
        cancelPlaybackLaunchTimeout()
        if (
            host.activity.isFinishing ||
                host.activity.isDestroyed ||
                playbackErrorDialog?.isShowing == true
        ) {
            return
        }
        if (host.session.pendingResumePositionOverrideMs == null) {
            host.session.pendingResumePositionOverrideMs =
                host.session.player?.currentPosition?.coerceAtLeast(0L) ?: 0L
        }
        host.session.releasePlayer()
        showPlaybackFailureDialog(message, launchPending)
    }

    private fun showPlaybackFailureDialog(message: String, launchPending: Boolean) {
        if (
            host.activity.isFinishing ||
                host.activity.isDestroyed ||
                playbackErrorDialog?.isShowing == true
        ) {
            return
        }
        playbackErrorDialog =
            AlertDialog.Builder(host.activity, R.style.NativePlaybackSettingsDialogTheme)
                .setTitle("播放失败")
                .setMessage(message)
                .setCancelable(false)
                .setPositiveButton("重试") { _, _ ->
                    playbackErrorDialog = null
                    host.recovery.resetForNewMedia()
                    resetStartupDeadline()
                    host.diagnostics.playbackPerformanceTracker.onRecovery()
                    host.session.nextInitializePlayWhenReady = true
                    host.session.initializePlayer()
                }
                .setNegativeButton("退出") { _, _ ->
                    playbackErrorDialog = null
                    if (launchPending) {
                        reportPlaybackLaunchResult(
                            resultCode = RESULT_PLAYBACK_CANCELLED,
                            message = "用户退出原生播放器",
                        )
                    }
                    host.activity.finish()
                }
                .create()
                .also { dialog ->
                    dialog.setOnDismissListener {
                        if (playbackErrorDialog === dialog) {
                            playbackErrorDialog = null
                        }
                    }
                    dialog.show()
                }
    }

    fun schedulePlaybackLaunchTimeout() {
        startupAttempts++
        if (startupAttempts > PlaybackPolicyValues.maxPlayerAttempts) {
            handlePlaybackFailure("超过最大播放尝试次数，请检查网络后重试。")
            return
        }
        startupProgress.reset()
        val timeMs = now()
        if (startupDeadlineMs == 0L) {
            startupLastProgressAtMs = timeMs
            startupDeadlineMs = startupLastProgressAtMs + PlaybackPolicyValues.exoStartupHardLimitMs
        }
        startupBufferedPositionMs = 0L
        startupBufferedPercentage = 0
        if (startupTimedOut(timeMs)) {
            handleStartupTimeout(timeMs)
            return
        }
        armPlaybackLaunchTimeout()
    }

    private fun armPlaybackLaunchTimeout() {
        playbackLaunchTimeoutHandler.removeCallbacks(playbackLaunchTimeoutRunnable)
        startupPending = true
        val timeMs = now()
        val idleRemainingMs =
            startupLastProgressAtMs + PlaybackPolicyValues.exoStartupNoProgressTimeoutMs - timeMs
        playbackLaunchTimeoutHandler.postDelayed(
            playbackLaunchTimeoutRunnable,
            minOf(
                PLAYBACK_LAUNCH_CHECK_INTERVAL_MS,
                (startupDeadlineMs - timeMs).coerceAtLeast(0L),
                idleRemainingMs.coerceAtLeast(0L),
            ),
        )
    }

    fun cancelPlaybackLaunchTimeout() {
        if (startupPending) consumeStartupProgress(now())
        startupPending = false
        playbackLaunchTimeoutHandler.removeCallbacks(playbackLaunchTimeoutRunnable)
    }

    fun resetStartupDeadline() {
        startupDeadlineMs = 0L
        startupLastProgressAtMs = 0L
        startupAttempts = 0
    }

    private fun buildPlaybackErrorMessage(error: PlaybackException): String {
        val detail = error.message?.trim().orEmpty()
        return if (detail.isEmpty()) {
            "设备无法解码该视频或音频格式（${error.errorCodeName}）。"
        } else {
            "设备无法继续播放（${error.errorCodeName}）：$detail"
        }
    }
}
