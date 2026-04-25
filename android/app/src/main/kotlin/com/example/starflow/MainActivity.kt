package com.example.starflow

import android.app.PictureInPictureParams
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.Context
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Rational
import android.content.pm.PackageManager
import android.media.AudioManager
import kotlin.math.roundToInt
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var platformChannel: MethodChannel? = null
    private var playbackSessionChannel: MethodChannel? = null
    private var playbackPictureInPictureEnabled = false
    private var playbackPictureInPictureAspectRatio = Rational(16, 9)
    private val audioManager by lazy {
        getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }
    private val playbackSystemSessionManager by lazy {
        PlaybackSystemSessionManager(
            context = applicationContext,
            sessionTag = "starflow_flutter_playback",
            contentIntentFactory = { buildPlaybackContentIntent() },
        ) { command, positionMs ->
            val payload = mutableMapOf<String, Any>("command" to command)
            if (positionMs != null) {
                payload["positionMs"] = positionMs
            }
            playbackSessionChannel?.invokeMethod("onPlaybackRemoteCommand", payload)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        platformChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "starflow/platform"
        )
        platformChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSystemBrightnessLevel" -> {
                    result.success(getSystemBrightnessLevel())
                }
                "setSystemBrightnessLevel" -> {
                    val value = call.argument<Double>("value") ?: 0.5
                    setSystemBrightnessLevel(value)
                    result.success(true)
                }
                "getSystemVolumeLevel" -> {
                    result.success(getSystemVolumeLevel())
                }
                "setSystemVolumeLevel" -> {
                    val value = call.argument<Double>("value") ?: 0.5
                    setSystemVolumeLevel(value)
                    result.success(true)
                }
                "isTelevision" -> {
                    val currentMode = resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK
                    result.success(currentMode == Configuration.UI_MODE_TYPE_TELEVISION)
                }
                "isPictureInPictureSupported" -> {
                    result.success(isPictureInPictureSupported())
                }
                "setPlaybackPictureInPictureEnabled" -> {
                    playbackPictureInPictureEnabled = call.argument<Boolean>("enabled") == true
                    updatePictureInPictureAspectRatio(
                        call.argument<Int>("aspectRatioWidth"),
                        call.argument<Int>("aspectRatioHeight"),
                    )
                    applyPictureInPictureParams()
                    result.success(isPictureInPictureSupported())
                }
                "enterPlaybackPictureInPicture" -> {
                    updatePictureInPictureAspectRatio(
                        call.argument<Int>("aspectRatioWidth"),
                        call.argument<Int>("aspectRatioHeight"),
                    )
                    result.success(enterPlaybackPictureInPicture())
                }
                "launchSystemVideoPlayer" -> {
                    val rawUrl = call.argument<String>("url")?.trim().orEmpty()
                    val title = call.argument<String>("title")?.trim().orEmpty()
                    if (rawUrl.isEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    try {
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(Uri.parse(rawUrl), "video/*")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        val chooser = Intent.createChooser(
                            intent,
                            if (title.isEmpty()) "选择播放器" else "播放：$title"
                        ).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(chooser)
                        result.success(true)
                    } catch (_: ActivityNotFoundException) {
                        result.success(false)
                    } catch (_: Throwable) {
                        result.success(false)
                    }
                }
                "launchNativePlaybackContainer" -> {
                    val rawUrl = call.argument<String>("url")?.trim().orEmpty()
                    val title = call.argument<String>("title")?.trim().orEmpty()
                    val headersJson = call.argument<String>("headersJson")?.trim().orEmpty()
                    val decodeMode = call.argument<String>("decodeMode")?.trim().orEmpty()
                    val playbackTargetJson = call.argument<String>("playbackTargetJson")?.trim().orEmpty()
                    val playbackItemKey = call.argument<String>("playbackItemKey")?.trim().orEmpty()
                    val seriesKey = call.argument<String>("seriesKey")?.trim().orEmpty()
                    val episodeQueueJson = call.argument<String>("episodeQueueJson")?.trim().orEmpty()
                    if (rawUrl.isEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    try {
                        val intent = Intent(this, NativePlaybackActivity::class.java).apply {
                            putExtra(NativePlaybackActivity.EXTRA_URL, rawUrl)
                            putExtra(NativePlaybackActivity.EXTRA_TITLE, title)
                            putExtra(NativePlaybackActivity.EXTRA_HEADERS_JSON, headersJson)
                            putExtra(NativePlaybackActivity.EXTRA_DECODE_MODE, decodeMode)
                            putExtra(NativePlaybackActivity.EXTRA_PLAYBACK_TARGET_JSON, playbackTargetJson)
                            putExtra(NativePlaybackActivity.EXTRA_PLAYBACK_ITEM_KEY, playbackItemKey)
                            putExtra(NativePlaybackActivity.EXTRA_SERIES_KEY, seriesKey)
                            putExtra(NativePlaybackActivity.EXTRA_EPISODE_QUEUE_JSON, episodeQueueJson)
                            addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (_: ActivityNotFoundException) {
                        result.success(false)
                    } catch (_: Throwable) {
                        result.success(false)
                    }
                }

                else -> result.notImplemented()
            }
        }
        playbackSessionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "starflow/playback_session"
        )
        playbackSessionChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setActive" -> {
                    playbackSystemSessionManager.setActive(
                        call.argument<Boolean>("active") == true,
                    )
                    result.success(true)
                }
                "update" -> {
                    val arguments = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                    playbackSystemSessionManager.update(
                        PlaybackSystemSessionState.fromMap(arguments),
                    )
                    result.success(true)
                }
                "showAirPlayPicker" -> {
                    result.success(false)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        playbackSessionChannel?.setMethodCallHandler(null)
        playbackSystemSessionManager.release()
        super.onDestroy()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (playbackPictureInPictureEnabled) {
            enterPlaybackPictureInPicture()
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        platformChannel?.invokeMethod(
            "onPictureInPictureModeChanged",
            mapOf("enabled" to isInPictureInPictureMode),
        )
    }

    private fun isPictureInPictureSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }
        return packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun updatePictureInPictureAspectRatio(width: Int?, height: Int?) {
        if ((width ?: 0) > 0 && (height ?: 0) > 0) {
            playbackPictureInPictureAspectRatio = Rational(width!!, height!!)
        } else {
            playbackPictureInPictureAspectRatio = Rational(16, 9)
        }
    }

    private fun buildPictureInPictureParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(playbackPictureInPictureAspectRatio)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(playbackPictureInPictureEnabled)
            builder.setSeamlessResizeEnabled(true)
        }

        return builder.build()
    }

    private fun applyPictureInPictureParams() {
        if (!isPictureInPictureSupported()) {
            return
        }
        setPictureInPictureParams(buildPictureInPictureParams())
    }

    private fun enterPlaybackPictureInPicture(): Boolean {
        if (!playbackPictureInPictureEnabled || !isPictureInPictureSupported()) {
            return false
        }
        if (isInPictureInPictureMode) {
            return true
        }
        return enterPictureInPictureMode(buildPictureInPictureParams())
    }

    private fun buildPlaybackContentIntent(): PendingIntent? {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
        return PendingIntent.getActivity(this, 0, launchIntent, flags)
    }

    private fun getSystemBrightnessLevel(): Double {
        val windowBrightness = window.attributes.screenBrightness
        if (windowBrightness in 0f..1f) {
            return windowBrightness.toDouble()
        }
        return try {
            Settings.System.getInt(
                contentResolver,
                Settings.System.SCREEN_BRIGHTNESS
            ).toDouble().div(255.0).coerceIn(0.0, 1.0)
        } catch (_: Throwable) {
            0.5
        }
    }

    private fun setSystemBrightnessLevel(value: Double) {
        val clamped = value.coerceIn(0.0, 1.0)
        val attributes = window.attributes
        attributes.screenBrightness = clamped.toFloat()
        window.attributes = attributes

        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.System.canWrite(this)) {
                Settings.System.putInt(
                    contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS,
                    (clamped * 255.0).roundToInt().coerceIn(0, 255)
                )
            }
        } catch (_: Throwable) {
        }
    }

    private fun getSystemVolumeLevel(): Double {
        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) {
            return 1.0
        }
        val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        return current.toDouble().div(max.toDouble()).coerceIn(0.0, 1.0)
    }

    private fun setSystemVolumeLevel(value: Double) {
        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) {
            return
        }
        val target = (value.coerceIn(0.0, 1.0) * max.toDouble()).roundToInt()
        audioManager.setStreamVolume(
            AudioManager.STREAM_MUSIC,
            target.coerceIn(0, max),
            0
        )
    }
}
