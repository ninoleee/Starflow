package com.example.starflow

import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import org.json.JSONObject

class NativePlaybackActivity : AppCompatActivity() {
    private var player: ExoPlayer? = null
    private lateinit var playerView: PlayerView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        playerView = PlayerView(this).apply {
            useController = false
            setShutterBackgroundColor(Color.BLACK)
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            setBackgroundColor(Color.BLACK)
            keepScreenOn = true
        }
        setContentView(
            FrameLayout(this).apply {
                setBackgroundColor(Color.BLACK)
                addView(
                    playerView,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT,
                    ),
                )
            },
        )
        enterImmersiveMode()
    }

    override fun onStart() {
        super.onStart()
        initializePlayer()
    }

    override fun onResume() {
        super.onResume()
        enterImmersiveMode()
        player?.playWhenReady = true
    }

    override fun onStop() {
        releasePlayer()
        super.onStop()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            enterImmersiveMode()
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN) {
            return super.dispatchKeyEvent(event)
        }

        val currentPlayer = player ?: return super.dispatchKeyEvent(event)
        when (event.keyCode) {
            KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_ENTER,
            KeyEvent.KEYCODE_NUMPAD_ENTER,
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_SPACE -> {
                if (currentPlayer.isPlaying) {
                    currentPlayer.pause()
                } else {
                    currentPlayer.play()
                }
                return true
            }

            KeyEvent.KEYCODE_MEDIA_PLAY -> {
                currentPlayer.play()
                return true
            }

            KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                currentPlayer.pause()
                return true
            }

            KeyEvent.KEYCODE_DPAD_LEFT,
            KeyEvent.KEYCODE_MEDIA_REWIND -> {
                currentPlayer.seekTo((currentPlayer.currentPosition - 10_000L).coerceAtLeast(0L))
                return true
            }

            KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> {
                val duration = currentPlayer.duration.takeIf { it > 0 } ?: Long.MAX_VALUE
                currentPlayer.seekTo((currentPlayer.currentPosition + 10_000L).coerceAtMost(duration))
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun initializePlayer() {
        if (player != null) {
            return
        }

        val url = intent.getStringExtra(EXTRA_URL)?.trim().orEmpty()
        if (url.isEmpty()) {
            finish()
            return
        }
        val title = intent.getStringExtra(EXTRA_TITLE)?.trim().orEmpty()
        val headersJson = intent.getStringExtra(EXTRA_HEADERS_JSON)?.trim().orEmpty()
        val decodeMode = PlaybackDecodeMode.fromRaw(
            intent.getStringExtra(EXTRA_DECODE_MODE)?.trim().orEmpty(),
        )

        val dataSourceFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setUserAgent("Starflow")

        if (headersJson.isNotEmpty()) {
            try {
                val json = JSONObject(headersJson)
                val headers = mutableMapOf<String, String>()
                val keys = json.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    headers[key] = json.optString(key)
                }
                dataSourceFactory.setDefaultRequestProperties(headers)
            } catch (_: Throwable) {
            }
        }

        val renderersFactory = DefaultRenderersFactory(this).apply {
            setEnableDecoderFallback(true)
            when (decodeMode) {
                PlaybackDecodeMode.AUTO -> Unit
                PlaybackDecodeMode.HARDWARE_PREFERRED -> {
                    setMediaCodecSelector(buildMediaCodecSelector(preferSoftware = false))
                }

                PlaybackDecodeMode.SOFTWARE_PREFERRED -> {
                    setMediaCodecSelector(buildMediaCodecSelector(preferSoftware = true))
                }
            }
        }

        val exoPlayer = ExoPlayer.Builder(this)
            .setRenderersFactory(renderersFactory)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory))
            .build().apply {
                playWhenReady = true
                repeatMode = Player.REPEAT_MODE_OFF
                setMediaItem(
                    MediaItem.Builder()
                        .setUri(url)
                        .setMediaMetadata(
                            MediaMetadata.Builder()
                                .setTitle(title.ifEmpty { null })
                                .build(),
                        )
                        .build(),
                )
                prepare()
            }

        player = exoPlayer
        playerView.player = exoPlayer
    }

    private fun buildMediaCodecSelector(preferSoftware: Boolean): MediaCodecSelector {
        return MediaCodecSelector { mimeType, requiresSecureDecoder, requiresTunnelingDecoder ->
            val allInfos = MediaCodecUtil.getDecoderInfos(
                mimeType,
                requiresSecureDecoder,
                requiresTunnelingDecoder,
            )
            val preferredInfos = allInfos.filter { info -> info.softwareOnly == preferSoftware }
            if (preferredInfos.isNotEmpty()) {
                preferredInfos
            } else {
                allInfos
            }
        }
    }

    private fun releasePlayer() {
        playerView.player = null
        player?.release()
        player = null
    }

    private fun enterImmersiveMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.hide(
                android.view.WindowInsets.Type.statusBars() or
                    android.view.WindowInsets.Type.navigationBars(),
            )
            window.insetsController?.systemBarsBehavior =
                android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            return
        }

        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
    }

    companion object {
        const val EXTRA_URL = "url"
        const val EXTRA_TITLE = "title"
        const val EXTRA_HEADERS_JSON = "headersJson"
        const val EXTRA_DECODE_MODE = "decodeMode"
    }
}

private enum class PlaybackDecodeMode {
    AUTO,
    HARDWARE_PREFERRED,
    SOFTWARE_PREFERRED;

    companion object {
        fun fromRaw(raw: String): PlaybackDecodeMode {
            return when (raw) {
                "hardwarePreferred" -> HARDWARE_PREFERRED
                "softwarePreferred" -> SOFTWARE_PREFERRED
                else -> AUTO
            }
        }
    }
}
