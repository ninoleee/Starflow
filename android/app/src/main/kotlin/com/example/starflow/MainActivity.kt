package com.example.starflow

import android.app.PictureInPictureParams
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.util.Rational
import android.content.pm.PackageManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var platformChannel: MethodChannel? = null
    private var playbackPictureInPictureEnabled = false
    private var playbackPictureInPictureAspectRatio = Rational(16, 9)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        platformChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "starflow/platform"
        )
        platformChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
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
}
