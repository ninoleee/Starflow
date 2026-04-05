package com.example.starflow

import android.content.res.Configuration
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "starflow/platform"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isTelevision" -> {
                    val currentMode = resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK
                    result.success(currentMode == Configuration.UI_MODE_TYPE_TELEVISION)
                }

                else -> result.notImplemented()
            }
        }
    }
}
