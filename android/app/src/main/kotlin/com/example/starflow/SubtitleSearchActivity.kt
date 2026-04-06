package com.example.starflow

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class SubtitleSearchActivity : FlutterActivity() {
    private var subtitleSearchChannel: MethodChannel? = null

    override fun getInitialRoute(): String {
        return intent.getStringExtra(EXTRA_INITIAL_ROUTE)?.trim().orEmpty()
            .ifEmpty { "/subtitle-search?standalone=1" }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        subtitleSearchChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "finishSubtitleSearch" -> {
                        val arguments = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
                        val data = Intent().apply {
                            putExtra(
                                RESULT_CACHED_PATH,
                                (arguments["cachedPath"] as? String)?.trim().orEmpty(),
                            )
                            putExtra(
                                RESULT_SUBTITLE_FILE_PATH,
                                (arguments["subtitleFilePath"] as? String)?.trim().orEmpty(),
                            )
                            putExtra(
                                RESULT_DISPLAY_NAME,
                                (arguments["displayName"] as? String)?.trim().orEmpty(),
                            )
                        }
                        setResult(Activity.RESULT_OK, data)
                        result.success(true)
                        finish()
                    }

                    "cancelSubtitleSearch" -> {
                        setResult(Activity.RESULT_CANCELED)
                        result.success(true)
                        finish()
                    }

                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        subtitleSearchChannel?.setMethodCallHandler(null)
        subtitleSearchChannel = null
        super.onDestroy()
    }

    companion object {
        const val EXTRA_INITIAL_ROUTE = "initialRoute"
        const val RESULT_CACHED_PATH = "cachedPath"
        const val RESULT_SUBTITLE_FILE_PATH = "subtitleFilePath"
        const val RESULT_DISPLAY_NAME = "displayName"

        private const val CHANNEL_NAME = "starflow/subtitle_search"
    }
}
