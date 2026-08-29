package com.example.starflow

import android.app.PictureInPictureParams
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.Context
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ResultReceiver
import android.provider.Settings
import android.util.Rational
import android.content.pm.PackageManager
import android.media.AudioManager
import kotlin.math.roundToInt
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {
    private var platformChannel: MethodChannel? = null
    private var playbackSessionChannel: MethodChannel? = null
    private var playbackPictureInPictureEnabled = false
    private var playbackPictureInPictureAspectRatio = Rational(16, 9)
    private val nativePlaybackLaunchHandler = Handler(Looper.getMainLooper())
    private var pendingNativePlaybackLaunchResult: MethodChannel.Result? = null
    private var pendingNativePlaybackLaunchRequestId = ""
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
                    } catch (error: ActivityNotFoundException) {
                        NativeAppLogger.warning(
                            "native.external-player",
                            "No external video player is available",
                            error,
                        )
                        result.success(false)
                    } catch (error: Throwable) {
                        NativeAppLogger.error(
                            "native.external-player",
                            "Could not launch external video player",
                            error,
                        )
                        result.success(false)
                    }
                }
                "launchNativePlaybackContainer" -> {
                    val rawUrl = call.argument<String>("url")?.trim().orEmpty()
                    val title = call.argument<String>("title")?.trim().orEmpty()
                    val headersJson = call.argument<String>("headersJson")?.trim().orEmpty()
                    val decodeMode = call.argument<String>("decodeMode")?.trim().orEmpty()
                    val audioOutputMode =
                        call.argument<String>("audioOutputMode")?.trim().orEmpty()
                    val subtitleScale = call.argument<Double>("subtitleScale")
                        ?: NativeSubtitleStylePolicy.DEFAULT_SCALE
                    val subtitlePreference =
                        call.argument<String>("subtitlePreference")?.trim().orEmpty()
                    val subtitlePreferredLanguages =
                        call.argument<List<String>>("subtitlePreferredLanguages")
                            ?.map(String::trim)
                            ?.filter(String::isNotEmpty)
                            ?.toTypedArray()
                            ?: emptyArray()
                    val playbackTargetJson = call.argument<String>("playbackTargetJson")?.trim().orEmpty()
                    val playbackItemKey = call.argument<String>("playbackItemKey")?.trim().orEmpty()
                    val seriesKey = call.argument<String>("seriesKey")?.trim().orEmpty()
                    val episodeQueueJson = call.argument<String>("episodeQueueJson")?.trim().orEmpty()
                    if (rawUrl.isEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    completeNativePlaybackLaunch(false)
                    val requestId = UUID.randomUUID().toString()
                    pendingNativePlaybackLaunchResult = result
                    pendingNativePlaybackLaunchRequestId = requestId
                    val launchResultReceiver = object : ResultReceiver(
                        nativePlaybackLaunchHandler,
                    ) {
                        override fun onReceiveResult(resultCode: Int, resultData: Bundle?) {
                            if (resultData?.getString(
                                    NativePlaybackActivity.RESULT_DATA_REQUEST_ID,
                                ) != requestId
                            ) {
                                return
                            }
                            completeNativePlaybackLaunch(
                                resultCode != NativePlaybackActivity.RESULT_PLAYBACK_FAILED,
                            )
                        }
                    }

                    try {
                        val intent = Intent(this, NativePlaybackActivity::class.java).apply {
                            putExtra(NativePlaybackActivity.EXTRA_URL, rawUrl)
                            putExtra(NativePlaybackActivity.EXTRA_TITLE, title)
                            putExtra(NativePlaybackActivity.EXTRA_HEADERS_JSON, headersJson)
                            putExtra(NativePlaybackActivity.EXTRA_DECODE_MODE, decodeMode)
                            putExtra(
                                NativePlaybackActivity.EXTRA_AUDIO_OUTPUT_MODE,
                                audioOutputMode,
                            )
                            putExtra(NativePlaybackActivity.EXTRA_SUBTITLE_SCALE, subtitleScale)
                            putExtra(
                                NativePlaybackActivity.EXTRA_SUBTITLE_PREFERENCE,
                                subtitlePreference,
                            )
                            putExtra(
                                NativePlaybackActivity.EXTRA_SUBTITLE_PREFERRED_LANGUAGES,
                                subtitlePreferredLanguages,
                            )
                            putExtra(NativePlaybackActivity.EXTRA_PLAYBACK_TARGET_JSON, playbackTargetJson)
                            putExtra(NativePlaybackActivity.EXTRA_PLAYBACK_ITEM_KEY, playbackItemKey)
                            putExtra(NativePlaybackActivity.EXTRA_SERIES_KEY, seriesKey)
                            putExtra(NativePlaybackActivity.EXTRA_EPISODE_QUEUE_JSON, episodeQueueJson)
                            putExtra(NativePlaybackActivity.EXTRA_LAUNCH_REQUEST_ID, requestId)
                            putExtra(
                                NativePlaybackActivity.EXTRA_LAUNCH_RESULT_RECEIVER,
                                launchResultReceiver,
                            )
                        }
                        startActivity(intent)
                    } catch (error: ActivityNotFoundException) {
                        NativeAppLogger.warning(
                            "native.playback-launch",
                            "Native playback Activity is unavailable",
                            error,
                        )
                        completeNativePlaybackLaunch(false)
                    } catch (error: Throwable) {
                        NativeAppLogger.error(
                            "native.playback-launch",
                            "Could not launch native playback Activity",
                            error,
                        )
                        completeNativePlaybackLaunch(false)
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
        completeNativePlaybackLaunch(false)
        playbackSessionChannel?.setMethodCallHandler(null)
        playbackSystemSessionManager.release()
        super.onDestroy()
    }

    private fun completeNativePlaybackLaunch(launched: Boolean) {
        val result = pendingNativePlaybackLaunchResult
        pendingNativePlaybackLaunchResult = null
        pendingNativePlaybackLaunchRequestId = ""
        result?.success(launched)
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
        val resolvedWidth = width ?: 0
        val resolvedHeight = height ?: 0
        if (resolvedWidth <= 0 || resolvedHeight <= 0) {
            playbackPictureInPictureAspectRatio = Rational(16, 9)
            return
        }
        val ratio = resolvedWidth.toDouble() / resolvedHeight.toDouble()
        playbackPictureInPictureAspectRatio = when {
            ratio < 0.42 -> Rational(42, 100)
            ratio > 2.39 -> Rational(239, 100)
            else -> Rational(resolvedWidth, resolvedHeight)
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
        try {
            setPictureInPictureParams(buildPictureInPictureParams())
        } catch (error: IllegalArgumentException) {
            NativeAppLogger.warning(
                "native.pip",
                "PIP parameters rejected by platform",
                error,
            )
        }
    }

    private fun enterPlaybackPictureInPicture(): Boolean {
        if (!playbackPictureInPictureEnabled || !isPictureInPictureSupported()) {
            return false
        }
        if (isInPictureInPictureMode) {
            return true
        }
        return try {
            enterPictureInPictureMode(buildPictureInPictureParams())
        } catch (error: IllegalArgumentException) {
            NativeAppLogger.warning(
                "native.pip",
                "PIP enter rejected by platform",
                error,
            )
            false
        }
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
