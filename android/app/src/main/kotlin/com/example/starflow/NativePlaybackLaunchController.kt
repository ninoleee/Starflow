package com.example.starflow

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ResultReceiver
import androidx.media3.common.PlaybackException
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_LAUNCH_RESULT_RECEIVER
import com.example.starflow.NativePlaybackActivity.Companion.RESULT_DATA_MESSAGE
import com.example.starflow.NativePlaybackActivity.Companion.RESULT_DATA_REQUEST_ID
import com.example.starflow.NativePlaybackActivity.Companion.RESULT_PLAYBACK_CANCELLED

internal class NativePlaybackLaunchController(
    private val host: Host,
    private val playbackLaunchTimeoutHandler: Handler = Handler(Looper.getMainLooper()),
) {
    interface Host {
        val session: NativePlaybackSession
        val diagnostics: NativePlaybackDiagnostics
        val episodes: NativePlaybackEpisodeController
        val activity: Activity
    }

    private var launchResultReceiver: ResultReceiver? = null

    private var launchRequestId = ""

    var launchResultDelivered = false
        private set

    private var startupPending = false

    private val playbackLaunchTimeoutRunnable = Runnable {
        if (startupPending && !host.activity.isFinishing && !host.activity.isDestroyed) {
            handlePlaybackFailure("30 秒内未显示视频画面，请检查网络或重试播放。")
        }
    }

    private var playbackErrorDialog: AlertDialog? = null

    fun applyIntent(intent: Intent) {
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
            AlertDialog.Builder(host.activity)
                .setTitle("播放失败")
                .setMessage(message)
                .setCancelable(false)
                .setPositiveButton("重试") { _, _ ->
                    playbackErrorDialog = null
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
        playbackLaunchTimeoutHandler.removeCallbacks(playbackLaunchTimeoutRunnable)
        startupPending = true
        playbackLaunchTimeoutHandler.postDelayed(
            playbackLaunchTimeoutRunnable,
            PLAYBACK_LAUNCH_TIMEOUT_MS,
        )
    }

    fun cancelPlaybackLaunchTimeout() {
        startupPending = false
        playbackLaunchTimeoutHandler.removeCallbacks(playbackLaunchTimeoutRunnable)
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
