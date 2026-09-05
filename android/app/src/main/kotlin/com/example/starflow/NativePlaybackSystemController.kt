package com.example.starflow

import android.app.Activity
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.content.Intent
import android.os.Build
import android.util.Rational
import androidx.media3.common.Player

internal class NativePlaybackSystemController(private val host: Host) {
    interface Host {
        val session: NativePlaybackSession
        val target: NativePlaybackTarget
        val episodes: NativePlaybackEpisodeController
        val runtime: NativePlaybackRuntimeController
        val activity: Activity
        val isTelevisionDevice: Boolean
    }

    val playbackSystemSessionManager by lazy {
        PlaybackSystemSessionManager(
            context = host.activity.applicationContext,
            sessionTag = "starflow_native_playback",
            contentIntentFactory = { buildPlaybackContentIntent() },
        ) { command, positionMs ->
            handlePlaybackSystemCommand(command, positionMs)
        }
    }

    fun syncPlaybackSystemSession() {
        val currentPlayer = host.session.player ?: return
        val state =
            PlaybackSystemSessionState(
                title = host.target.buildSystemSessionTitle(),
                subtitle = host.target.buildSystemSessionSubtitle(),
                positionMs = currentPlayer.currentPosition.coerceAtLeast(0L),
                durationMs = currentPlayer.duration.takeIf { it > 0L } ?: 0L,
                playing = currentPlayer.isPlaying,
                buffering = currentPlayer.playbackState == Player.STATE_BUFFERING,
                speed = currentPlayer.playbackParameters.speed,
                canSeek = true,
                hasEpisodeQueue = (host.episodes.episodeQueue?.entries?.size ?: 0) > 1,
                hasPrevious = host.episodes.episodeQueue?.hasPrevious() == true,
                hasNext = host.episodes.episodeQueue?.hasNext() == true,
            )
        playbackSystemSessionManager.update(state)
    }

    private fun handlePlaybackSystemCommand(command: String, positionMs: Long?) {
        when (command) {
            "play" -> host.session.setPlayWhenReady(true)
            "pause",
            "stop",
            "becomingNoisy",
            "interruptionPause" -> {
                host.session.setPlayWhenReady(false)
                host.runtime.persistPlaybackProgress(force = true)
            }
            "toggle" -> host.session.togglePlayback()
            "seekForward" -> host.session.seekBy(10_000L)
            "next" -> {
                host.episodes.advanceToAdjacentEpisode(forward = true, reason = "remote-next")
            }
            "seekBackward" -> host.session.seekBy(-10_000L)
            "previous" -> {
                host.episodes.advanceToAdjacentEpisode(forward = false, reason = "remote-previous")
            }
            "seekTo" -> {
                val currentPlayer = host.session.player ?: return
                currentPlayer.seekTo((positionMs ?: 0L).coerceAtLeast(0L))
                host.runtime.syncSkipFlagsWithCurrentPosition()
                syncPlaybackSystemSession()
            }
            "interruptionResume" -> host.session.setPlayWhenReady(true)
        }
    }

    private fun buildPlaybackContentIntent(): PendingIntent? {
        val activityIntent =
            Intent(host.activity, NativePlaybackActivity::class.java).apply {
                replaceExtras(host.activity.intent)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
        val flags =
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }
        return PendingIntent.getActivity(host.activity, 0, activityIntent, flags)
    }

    fun updatePictureInPictureParams() {
        // TV playback stays full-screen and does not use mobile PIP. Avoid
        // sending PIP parameters to TV firmware, which may reject video
        // dimensions reported by hardware decoders.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || host.isTelevisionDevice) {
            return
        }
        try {
            host.activity.setPictureInPictureParams(
                PictureInPictureParams.Builder()
                    .setAspectRatio(buildPictureInPictureAspectRatio())
                    .build()
            )
        } catch (error: IllegalArgumentException) {
            // Some TV firmware rejects an otherwise valid video ratio. PIP is
            // optional, so never let this system call terminate playback.
            NativePlaybackFormatting.logPlayback("native.pip.params-rejected", error)
        }
    }

    fun enterPictureInPictureIfPossible() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || host.isTelevisionDevice) {
            return
        }
        val currentPlayer = host.session.player ?: return
        if (!currentPlayer.isPlaying || host.activity.isInPictureInPictureMode) {
            return
        }
        updatePictureInPictureParams()
        try {
            host.activity.enterPictureInPictureMode(
                PictureInPictureParams.Builder()
                    .setAspectRatio(buildPictureInPictureAspectRatio())
                    .build()
            )
        } catch (error: IllegalArgumentException) {
            NativePlaybackFormatting.logPlayback("native.pip.enter-rejected", error)
        }
    }

    private fun buildPictureInPictureAspectRatio(): Rational {
        val currentPlayer = host.session.player
        val videoSize = currentPlayer?.videoSize
        val width = videoSize?.width ?: 0
        val height = videoSize?.height ?: 0
        if (width <= 0 || height <= 0) {
            return Rational(16, 9)
        }

        // Android's framework only accepts ratios in [0.418410, 2.390000].
        // Clamp unusual/corrupt stream dimensions before handing them to the
        // system (for example a 1x8192 image reported by some TV decoders).
        val ratio = width.toDouble() / height.toDouble()
        return when {
            ratio < 0.42 -> Rational(42, 100)
            ratio > 2.39 -> Rational(239, 100)
            else -> Rational(width, height)
        }
    }
}
