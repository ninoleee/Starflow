package com.example.starflow

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.SystemClock

data class PlaybackSystemSessionState(
    val title: String = "",
    val subtitle: String = "",
    val positionMs: Long = 0L,
    val durationMs: Long = 0L,
    val playing: Boolean = false,
    val buffering: Boolean = false,
    val speed: Float = 1f,
    val canSeek: Boolean = true,
    val hasPrevious: Boolean = false,
    val hasNext: Boolean = false,
) {
    companion object {
        fun fromMap(arguments: Map<*, *>): PlaybackSystemSessionState {
            return PlaybackSystemSessionState(
                title = "${arguments["title"] ?: ""}".trim(),
                subtitle = "${arguments["subtitle"] ?: ""}".trim(),
                positionMs = (arguments["positionMs"] as? Number)?.toLong() ?: 0L,
                durationMs = (arguments["durationMs"] as? Number)?.toLong() ?: 0L,
                playing = arguments["playing"] as? Boolean ?: false,
                buffering = arguments["buffering"] as? Boolean ?: false,
                speed = (arguments["speed"] as? Number)?.toFloat() ?: 1f,
                canSeek = arguments["canSeek"] as? Boolean ?: true,
                hasPrevious = arguments["hasPrevious"] as? Boolean ?: false,
                hasNext = arguments["hasNext"] as? Boolean ?: false,
            )
        }
    }
}

class PlaybackSystemSessionManager(
    private val context: Context,
    private val sessionTag: String,
    private val contentIntentFactory: () -> PendingIntent?,
    private val remoteCommandDispatcher: (String, Long?) -> Unit,
) {
    companion object {
        const val ACTION_REMOTE_COMMAND =
            "com.example.starflow.action.PLAYBACK_REMOTE_COMMAND"
        const val EXTRA_COMMAND = "command"
        const val EXTRA_POSITION_MS = "positionMs"

        private const val notificationChannelId = "starflow_playback"
        private const val notificationChannelName = "播放控制"
        private const val notificationId = 41041

        @Volatile
        private var activeOwnerTag: String? = null

        @Volatile
        private var activeDispatcher: ((String, Long?) -> Unit)? = null

        fun dispatchNotificationCommand(command: String, positionMs: Long? = null) {
            activeDispatcher?.invoke(command, positionMs)
        }
    }

    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val mediaSession = MediaSession(context, sessionTag)
    private val audioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
        .build()
    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                remoteCommandDispatcher("becomingNoisy", null)
            }
        }
    }
    private val audioFocusChangeListener =
        AudioManager.OnAudioFocusChangeListener { focusChange ->
            when (focusChange) {
                AudioManager.AUDIOFOCUS_GAIN -> {
                    hasAudioFocus = true
                    if (resumeOnFocusGain) {
                        resumeOnFocusGain = false
                        remoteCommandDispatcher("interruptionResume", null)
                    }
                }

                AudioManager.AUDIOFOCUS_LOSS -> {
                    if (!hasAudioFocus) {
                        return@OnAudioFocusChangeListener
                    }
                    hasAudioFocus = false
                    resumeOnFocusGain = false
                    remoteCommandDispatcher("interruptionPause", null)
                }

                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                    if (!hasAudioFocus) {
                        return@OnAudioFocusChangeListener
                    }
                    hasAudioFocus = false
                    resumeOnFocusGain = currentState.playing
                    remoteCommandDispatcher("interruptionPause", null)
                }

                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                    // Keep video playback running for short duck events such as notifications.
                }
            }
        }

    private var audioFocusRequest: AudioFocusRequest? = null
    private var currentState = PlaybackSystemSessionState()
    private var isActive = false
    private var noisyReceiverRegistered = false
    private var hasAudioFocus = false
    private var resumeOnFocusGain = false

    init {
        mediaSession.setFlags(
            MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS,
        )
        mediaSession.setCallback(
            object : MediaSession.Callback() {
                override fun onPlay() {
                    remoteCommandDispatcher("play", null)
                }

                override fun onPause() {
                    remoteCommandDispatcher("pause", null)
                }

                override fun onStop() {
                    remoteCommandDispatcher("stop", null)
                }

                override fun onSeekTo(pos: Long) {
                    remoteCommandDispatcher("seekTo", pos)
                }

                override fun onFastForward() {
                    remoteCommandDispatcher("seekForward", null)
                }

                override fun onRewind() {
                    remoteCommandDispatcher("seekBackward", null)
                }

                override fun onSkipToNext() {
                    remoteCommandDispatcher("next", null)
                }

                override fun onSkipToPrevious() {
                    remoteCommandDispatcher("previous", null)
                }
            },
        )
    }

    fun setActive(active: Boolean) {
        if (isActive == active) {
            if (active) {
                mediaSession.setSessionActivity(contentIntentFactory())
            }
            return
        }

        isActive = active
        if (active) {
            ensureNotificationChannel()
            mediaSession.setSessionActivity(contentIntentFactory())
            mediaSession.isActive = true
            activeOwnerTag = sessionTag
            activeDispatcher = remoteCommandDispatcher
        } else {
            if (activeOwnerTag == sessionTag) {
                activeOwnerTag = null
                activeDispatcher = null
            }
            unregisterNoisyReceiver()
            abandonAudioFocus()
            mediaSession.isActive = false
            mediaSession.setMetadata(null)
            mediaSession.setPlaybackState(null)
            notificationManager.cancel(notificationId)
        }
    }

    fun update(state: PlaybackSystemSessionState) {
        currentState = state
        if (!isActive) {
            return
        }

        if (state.playing) {
            requestAudioFocus()
            registerNoisyReceiver()
        } else if (!state.buffering) {
            unregisterNoisyReceiver()
            abandonAudioFocus()
        }

        mediaSession.setPlaybackState(buildPlaybackState(state))
        mediaSession.setMetadata(buildMetadata(state))
        updateNotification(state)
    }

    fun prepareForPlayback(): Boolean {
        return requestAudioFocus()
    }

    fun release() {
        setActive(false)
        mediaSession.release()
    }

    private fun buildPlaybackState(state: PlaybackSystemSessionState): PlaybackState {
        var actions = PlaybackState.ACTION_PLAY or
            PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_STOP
        if (state.canSeek) {
            actions = actions or
                PlaybackState.ACTION_FAST_FORWARD or
                PlaybackState.ACTION_REWIND or
                PlaybackState.ACTION_SEEK_TO
        }
        if (state.hasPrevious) {
            actions = actions or PlaybackState.ACTION_SKIP_TO_PREVIOUS
        }
        if (state.hasNext) {
            actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
        }

        val status = when {
            state.buffering -> PlaybackState.STATE_BUFFERING
            state.playing -> PlaybackState.STATE_PLAYING
            else -> PlaybackState.STATE_PAUSED
        }

        return PlaybackState.Builder()
            .setActions(actions)
            .setState(
                status,
                state.positionMs.coerceAtLeast(0L),
                if (state.playing && !state.buffering) state.speed.coerceAtLeast(0.1f) else 0f,
                SystemClock.elapsedRealtime(),
            )
            .build()
    }

    private fun buildMetadata(state: PlaybackSystemSessionState): MediaMetadata {
        return MediaMetadata.Builder()
            .putString(
                MediaMetadata.METADATA_KEY_TITLE,
                state.title.ifBlank { "Starflow" },
            )
            .putString(MediaMetadata.METADATA_KEY_ARTIST, state.subtitle)
            .putString(MediaMetadata.METADATA_KEY_ALBUM, state.subtitle)
            .putLong(
                MediaMetadata.METADATA_KEY_DURATION,
                state.durationMs.coerceAtLeast(0L),
            )
            .putBitmap(
                MediaMetadata.METADATA_KEY_DISPLAY_ICON,
                BitmapFactory.decodeResource(context.resources, R.drawable.icon_preview_sharp),
            )
            .build()
    }

    private fun updateNotification(state: PlaybackSystemSessionState) {
        if (!notificationsAllowed()) {
            return
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, notificationChannelId)
        } else {
            Notification.Builder(context)
        }

        val rewindIntent = buildCommandPendingIntent("seekBackward")
        val playPauseIntent = buildCommandPendingIntent(
            if (state.playing) "pause" else "play",
        )
        val forwardIntent = buildCommandPendingIntent("seekForward")

        builder
            .setSmallIcon(R.drawable.icon_preview_sharp)
            .setContentTitle(state.title.ifBlank { "Starflow" })
            .setContentText(state.subtitle.ifBlank { null })
            .setContentIntent(contentIntentFactory())
            .setDeleteIntent(buildCommandPendingIntent("stop"))
            .setOnlyAlertOnce(true)
            .setOngoing(state.playing)
            .setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setStyle(
                Notification.MediaStyle()
                    .setMediaSession(mediaSession.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2),
            )
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(context, android.R.drawable.ic_media_rew),
                    "后退 10 秒",
                    rewindIntent,
                ).build(),
            )
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(
                        context,
                        if (state.playing) {
                            android.R.drawable.ic_media_pause
                        } else {
                            android.R.drawable.ic_media_play
                        },
                    ),
                    if (state.playing) "暂停" else "播放",
                    playPauseIntent,
                ).build(),
            )
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(context, android.R.drawable.ic_media_ff),
                    "前进 10 秒",
                    forwardIntent,
                ).build(),
            )

        notificationManager.notify(notificationId, builder.build())
    }

    private fun buildCommandPendingIntent(
        command: String,
        positionMs: Long? = null,
    ): PendingIntent {
        val intent = Intent(context, PlaybackNotificationActionReceiver::class.java).apply {
            action = ACTION_REMOTE_COMMAND
            `package` = context.packageName
            putExtra(EXTRA_COMMAND, command)
            if (positionMs != null) {
                putExtra(EXTRA_POSITION_MS, positionMs)
            }
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        return PendingIntent.getBroadcast(context, command.hashCode(), intent, flags)
    }

    private fun notificationsAllowed(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        return context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val existing = notificationManager.getNotificationChannel(notificationChannelId)
        if (existing != null) {
            return
        }
        notificationManager.createNotificationChannel(
            NotificationChannel(
                notificationChannelId,
                notificationChannelName,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "播放器锁屏与系统播放控制"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            },
        )
    }

    private fun registerNoisyReceiver() {
        if (noisyReceiverRegistered) {
            return
        }
        context.registerReceiver(
            noisyReceiver,
            IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
        )
        noisyReceiverRegistered = true
    }

    private fun unregisterNoisyReceiver() {
        if (!noisyReceiverRegistered) {
            return
        }
        try {
            context.unregisterReceiver(noisyReceiver)
        } catch (_: Throwable) {
        }
        noisyReceiverRegistered = false
    }

    private fun requestAudioFocus(): Boolean {
        if (hasAudioFocus) {
            return true
        }
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (audioFocusRequest == null) {
                audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(audioAttributes)
                    .setOnAudioFocusChangeListener(audioFocusChangeListener)
                    .setWillPauseWhenDucked(false)
                    .build()
            }
            audioManager.requestAudioFocus(audioFocusRequest!!)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                audioFocusChangeListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN,
            )
        }
        if (granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            hasAudioFocus = true
            return true
        }
        return false
    }

    private fun abandonAudioFocus() {
        if (!hasAudioFocus) {
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = audioFocusRequest
            if (request != null) {
                audioManager.abandonAudioFocusRequest(request)
            }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(audioFocusChangeListener)
        }
        hasAudioFocus = false
        resumeOnFocusGain = false
    }
}
