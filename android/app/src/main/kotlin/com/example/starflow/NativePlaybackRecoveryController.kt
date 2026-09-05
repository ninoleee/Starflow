package com.example.starflow

import android.app.Activity
import androidx.media3.common.C
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Tracks
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_MEDIA_MIME_TYPE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_URL

internal class NativePlaybackRecoveryController(private val host: Host) {
    interface Host {
        val diagnostics: NativePlaybackDiagnostics
        val session: NativePlaybackSession
        val runtime: NativePlaybackRuntimeController
        val systemSession: NativePlaybackSystemController
        val activity: Activity

        fun showToast(message: String)
    }

    private var transcodedVideoFallbackAttempted = false

    var smartStrmHlsFallbackAttempted = false

    fun resetForNewMedia() {
        transcodedVideoFallbackAttempted = false
        smartStrmHlsFallbackAttempted = false
    }

    fun fallbackToTranscodedVideoIfNeeded(tracks: Tracks) {
        if (transcodedVideoFallbackAttempted) {
            return
        }
        val videoGroups = tracks.groups.filter { it.type == C.TRACK_TYPE_VIDEO }
        if (
            videoGroups.isEmpty() ||
                videoGroups.any { group ->
                    (0 until group.length).any { trackIndex -> group.isTrackSupported(trackIndex) }
                }
        ) {
            return
        }

        transcodedVideoFallbackAttempted = true
        host.diagnostics.playbackPerformanceTracker.onRecovery()
        val currentPlayer = host.session.player ?: return
        val fallbackUrl =
            NativePlaybackSource.buildTranscodedVideoFallbackUrl(
                host.activity.intent.getStringExtra(EXTRA_URL)?.trim().orEmpty()
            )
        if (fallbackUrl == null) {
            NativePlaybackFormatting.logPlayback("native.video.unsupported-no-transcode-fallback")
            return
        }

        host.session.pendingResumePositionOverrideMs =
            currentPlayer.currentPosition.coerceAtLeast(0L)
        host.session.nextInitializePlayWhenReady = currentPlayer.playWhenReady
        host.activity.intent.putExtra(EXTRA_URL, fallbackUrl)
        NativePlaybackFormatting.logPlayback(
            "native.video.unsupported-fallback " +
                "resumeMs=${host.session.pendingResumePositionOverrideMs}"
        )
        host.session.rebuildPlayer()
        host.showToast("视频编码需要转码，正在重新连接")
    }

    fun retrySmartStrmAsHlsIfNeeded(error: PlaybackException): Boolean {
        val url = host.activity.intent.getStringExtra(EXTRA_URL)?.trim().orEmpty()
        if (
            !NativePlaybackHlsFallbackPolicy.shouldRetryAsHls(
                errorCode = error.errorCode,
                url = url,
                alreadyAttempted = smartStrmHlsFallbackAttempted,
            )
        ) {
            return false
        }

        smartStrmHlsFallbackAttempted = true
        host.diagnostics.playbackPerformanceTracker.onRecovery()
        host.session.pendingResumePositionOverrideMs =
            host.session.player?.currentPosition?.coerceAtLeast(0L) ?: 0L
        host.session.nextInitializePlayWhenReady = host.session.player?.playWhenReady ?: true
        host.activity.intent.putExtra(EXTRA_MEDIA_MIME_TYPE, MimeTypes.APPLICATION_M3U8)
        NativePlaybackFormatting.logPlayback(
            "native.playback.smartstrm-hls-fallback " +
                "resumeMs=${host.session.pendingResumePositionOverrideMs} " +
                "url=${NativePlaybackSource.summarizeUrl(url)}"
        )
        host.session.rebuildPlayer()
        return true
    }

    fun recoverPlaybackStall(positionMs: Long): Boolean {
        val currentPlayer = host.session.player ?: return true
        val nowMs = System.currentTimeMillis()
        val recovery =
            host.runtime.playbackWatchdogPolicy.recovery(
                host.diagnostics::isCurrentBandwidthInsufficient
            )
        if (recovery == NativePlaybackWatchdogPolicy.Recovery.NONE) {
            return true
        }
        if (recovery == NativePlaybackWatchdogPolicy.Recovery.WAIT_FOR_BANDWIDTH) {
            if (!host.diagnostics.bandwidthWarningShown) {
                host.diagnostics.bandwidthWarningShown = true
                host.showToast("当前网速低于片源码率，继续等待缓冲")
            }
            return true
        }
        host.diagnostics.playbackPerformanceTracker.onRecovery()

        if (recovery == NativePlaybackWatchdogPolicy.Recovery.SOFT) {
            host.systemSession.playbackSystemSessionManager.prepareForPlayback()
            currentPlayer.seekTo(positionMs.coerceAtLeast(0L))
            currentPlayer.prepare()
            currentPlayer.playWhenReady = true
            host.runtime.playbackWatchdogPolicy.onSoftRecoveryCompleted(nowMs)
            return true
        }

        restartPlayerAfterPlaybackStall(positionMs)
        return false
    }

    private fun restartPlayerAfterPlaybackStall(positionMs: Long) {
        host.session.pendingResumePositionOverrideMs = positionMs.coerceAtLeast(0L)
        host.session.nextInitializePlayWhenReady = true
        host.session.rebuildPlayer()
        host.systemSession.syncPlaybackSystemSession()
    }
}
