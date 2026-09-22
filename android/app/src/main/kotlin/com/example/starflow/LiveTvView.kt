package com.example.starflow

import android.content.Context
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.MimeTypes
import androidx.media3.datasource.DataSource
import androidx.media3.exoplayer.source.UnrecognizedInputFormatException
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class LiveTvViewFactory(
    private val messenger: BinaryMessenger,
    private val lifecycle: Lifecycle,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView = LiveTvView(context, messenger, viewId, lifecycle)
}

/** Dedicated live session: no VOD memory, seeking, episode queue or NAS credentials. */
private class LiveTvView(context: Context, messenger: BinaryMessenger, id: Int, private val lifecycle: Lifecycle) : PlatformView {
    private val root = FrameLayout(context)
    private val texture = TextureView(context)
    private val channel = MethodChannel(messenger, "starflow/live_tv/$id")
    private var player: ExoPlayer? = null
    private val session = LiveTvSessionPolicy()
    private var ratio = LiveTvVideoPolicy.DEFAULT_RATIO
    private var disposed = false
    private var volume = 1f
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())
    private var progress: Runnable? = null
    private var networkSpeed: LiveTvNetworkSpeed? = null
    private var diagnostics: LiveTvDiagnostics? = null
    private val lifecycleObserver = LifecycleEventObserver { _, event ->
        when (event) {
            Lifecycle.Event.ON_STOP -> releasePlayer()
            Lifecycle.Event.ON_DESTROY -> dispose()
            else -> Unit
        }
    }

    init {
        root.setBackgroundColor(android.graphics.Color.BLACK)
        root.isFocusable = false
        root.addView(texture, FrameLayout.LayoutParams(-1, -1))
        texture.isFocusable = false
        texture.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> fit() }
        root.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) {
                if (!disposed) player?.setVideoTextureView(texture)
                root.keepScreenOn = !disposed && player?.isPlaying == true
                fit()
            }
            override fun onViewDetachedFromWindow(view: View) {
                player?.clearVideoTextureView(texture)
                root.keepScreenOn = false
            }
        })
        lifecycle.addObserver(lifecycleObserver)
        channel.setMethodCallHandler { call, result ->
            if (disposed) { result.error("closed", "Live session closed", null); return@setMethodCallHandler }
            val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            when (call.method) {
                "open" -> {
                    // A replacement request always invalidates the previous decoder, even if invalid.
                    releasePlayer()
                    val url = args["url"] as? String
                    val generation = args["generation"]
                    val headers = args["headers"]
                    if (url == null || (generation !is Int && generation !is Long) ||
                        (headers != null && headers !is Map<*, *>) || runCatching { LiveTvHttpPolicy.parse(url) }.isFailure) {
                        result.error("invalid", "Invalid live request", null)
                    } else if (!lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
                        result.error("inactive", "Live activity is not visible", null)
                    } else {
                        try {
                            volume = (args["volume"] as? Number)?.toFloat()?.takeIf { it.isFinite() }?.coerceIn(0f, 1f) ?: volume
                            open(context, url, headers as? Map<*, *> ?: emptyMap<Any, Any>(), (generation as Number).toLong())
                            result.success(null)
                        } catch (error: Exception) {
                            releasePlayer()
                            result.error("open", "Live playback failed", LiveTvPlaybackError.details(error))
                        }
                    }
                }
                "stop" -> { releasePlayer(); result.success(null) }
                "cancelOpen" -> {
                    if ((args["generation"] as? Number)?.toLong() == session.generation) releasePlayer()
                    result.success(null)
                }
                "pause" -> { player?.pause(); session.resetProgress(); result.success(null) }
                "play" -> {
                    if (lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
                        session.resetProgress()
                        player?.seekToDefaultPosition()
                        player?.play()
                    }
                    result.success(null)
                }
                "volume" -> {
                    val value = (args["value"] as? Number)?.toDouble()
                    if (value == null || !value.isFinite()) result.error("invalid", "Invalid live volume", null)
                    else {
                        volume = value.coerceIn(0.0, 1.0).toFloat()
                        player?.volume = volume
                        result.success(null)
                    }
                }
                "networkSpeed" -> {
                    result.success(if ((args["generation"] as? Number)?.toLong() == session.generation && player != null) {
                        networkSpeed?.bytesPerSecond
                    } else null)
                }
                "audioTracks" -> {
                    if ((args["generation"] as? Number)?.toLong() != session.generation) {
                        result.success(emptyList<Any>()); return@setMethodCallHandler
                    }
                    val tracks = player?.currentTracks?.groups.orEmpty()
                    val items = mutableListOf<Map<String, Any>>()
                    tracks.forEachIndexed { groupIndex, group ->
                        if (group.type == C.TRACK_TYPE_AUDIO) for (i in 0 until group.length) {
                            val format = group.getTrackFormat(i)
                            items.add(mapOf("id" to "${session.token}:$groupIndex:$i", "title" to (format.label ?: format.language ?: "Audio ${items.size + 1}"), "selected" to group.isTrackSelected(i)))
                        }
                    }
                    result.success(items)
                }
                "audio" -> {
                    val parts = (args["id"] as? String).orEmpty().split(":")
                    val group = parts.getOrNull(1)?.toIntOrNull()?.let { player?.currentTracks?.groups?.getOrNull(it) }
                    val track = parts.getOrNull(2)?.toIntOrNull()
                    if (session.acceptsAudio((args["generation"] as? Number)?.toLong(), parts.getOrNull(0)?.toLongOrNull()) &&
                        parts.size == 3 && group != null && track != null && track in 0 until group.length &&
                        group.type == C.TRACK_TYPE_AUDIO && group.isTrackSupported(track)) {
                        player?.let { p -> p.trackSelectionParameters = p.trackSelectionParameters.buildUpon()
                            .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
                            .addOverride(androidx.media3.common.TrackSelectionOverride(group.mediaTrackGroup, track)).build() }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun open(context: Context, url: String, headers: Map<*, *>, nextGeneration: Long) {
        val token = session.open(nextGeneration)
        val policy = LiveTvHttpPolicy(url, headers)
        val fallback = LiveTvHlsFallbackPolicy()
        val speed = LiveTvNetworkSpeed { android.os.SystemClock.elapsedRealtime() }
        networkSpeed = speed
        val http = DataSource.Factory { LiveTvHttpDataSource(policy).apply { addTransferListener(speed) } }
        val control = DefaultLoadControl.Builder().setBufferDurationsMs(3000, 12000, 1000, 2000)
            .setTargetBufferBytes(32 * 1024 * 1024).setPrioritizeTimeOverSizeThresholds(false).build()
        val renderers = DefaultRenderersFactory(context)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
            .setEnableDecoderFallback(true)
        val current = ExoPlayer.Builder(context, renderers).setLoadControl(control)
            .setMediaSourceFactory(DefaultMediaSourceFactory(http)).build()
        player = current
        val telemetry = LiveTvDiagnostics(nextGeneration,
            isActive = { !disposed && player === current && session.accepts(token) })
        diagnostics = telemetry
        current.addAnalyticsListener(telemetry)
        current.volume = volume
        current.setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true)
        current.setHandleAudioBecomingNoisy(true)
        current.addListener(object : Player.Listener {
            private fun emit(state: String, error: Throwable? = null) {
                if (!disposed && player === current && session.event(token, state)) {
                    channel.invokeMethod("state", buildMap<String, Any> {
                        put("generation", nextGeneration)
                        put("state", state)
                        if (error != null) put("error", LiveTvPlaybackError.details(error))
                    })
                }
            }
            override fun onPlaybackStateChanged(state: Int) {
                if (disposed || player !== current || !session.accepts(token)) return
                telemetry.state(current, state)
                when (state) {
                    Player.STATE_READY -> emit("ready")
                    Player.STATE_BUFFERING -> emit("buffering")
                    Player.STATE_ENDED -> { emit("ended"); finish() }
                }
            }
            override fun onRenderedFirstFrame() = emit("frame")
            override fun onTracksChanged(tracks: Tracks) = telemetry.tracks(tracks)
            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                emit(LiveTvPausePolicy.state(playWhenReady, current.playbackSuppressionReason, reason))
            }
            override fun onPlaybackSuppressionReasonChanged(playbackSuppressionReason: Int) {
                emit(LiveTvPausePolicy.state(current.playWhenReady, playbackSuppressionReason, 0))
            }
            override fun onPlayerError(error: PlaybackException) {
                if (disposed || player !== current || !session.accepts(token)) return
                val unrecognized = error.errorCode == PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED &&
                    generateSequence<Throwable>(error) { it.cause }.take(10).any { it is UnrecognizedInputFormatException }
                if (fallback.tryFallback(unrecognized)) {
                    telemetry.hlsFallback()
                    session.resetProgress()
                    emit("buffering")
                    try {
                        current.setMediaItem(mediaItem(url, hls = true))
                        current.prepare()
                    } catch (fallbackError: Exception) { emit("error", fallbackError); finish() }
                } else { emit("error", error); finish() }
            }
            private fun finish() {
                // Release outside listener dispatch; a newer open must not be stopped by this task.
                handler.post { if (player === current) releasePlayer() }
            }
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (player === current) {
                    session.resetProgress()
                    root.keepScreenOn = isPlaying && root.isAttachedToWindow
                }
            }
            override fun onPositionDiscontinuity(oldPosition: Player.PositionInfo, newPosition: Player.PositionInfo, reason: Int) {
                if (player === current) session.resetProgress()
            }
            override fun onVideoSizeChanged(size: VideoSize) {
                if (player === current && session.accepts(token)) {
                    ratio = LiveTvVideoPolicy.ratio(size.width, size.height, size.pixelWidthHeightRatio)
                        ?: LiveTvVideoPolicy.DEFAULT_RATIO
                    fit()
                }
            }
        })
        // Media3 owns Surface creation/destruction, including already-available textures and reattach.
        current.setVideoTextureView(texture)
        current.setMediaItem(mediaItem(url))
        current.prepare()
        current.playWhenReady = true
        val poll = object : Runnable {
            override fun run() {
                if (disposed || player !== current || !session.accepts(token)) return
                speed.sample()
                if (session.progress(token, current.currentPosition, current.isPlaying)) {
                    channel.invokeMethod("state", mapOf("generation" to nextGeneration, "state" to "progress"))
                }
                handler.postDelayed(this, 1000)
            }
        }
        progress = poll
        handler.postDelayed(poll, 1000)
    }

    private fun mediaItem(url: String, hls: Boolean = false): MediaItem = MediaItem.Builder().setUri(url)
        .setMimeType(if (hls) MimeTypes.APPLICATION_M3U8 else null)
        .build()

    private fun fit() {
        val (x, y) = LiveTvVideoPolicy.scale(texture.width, texture.height, ratio)
        val matrix = android.graphics.Matrix()
        matrix.setScale(x, y, texture.width / 2f, texture.height / 2f)
        texture.setTransform(matrix)
    }
    private fun releasePlayer() {
        diagnostics?.close()
        diagnostics = null
        session.invalidate()
        progress?.let(handler::removeCallbacks)
        progress = null
        networkSpeed = null
        val old = player
        player = null
        root.keepScreenOn = false
        ratio = LiveTvVideoPolicy.DEFAULT_RATIO
        try { old?.release() } finally { fit() }
    }
    override fun getView(): View = root
    override fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        lifecycle.removeObserver(lifecycleObserver)
        handler.removeCallbacksAndMessages(null)
        releasePlayer()
    }
}
