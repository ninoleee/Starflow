package com.example.starflow

internal const val REQUEST_CODE_EXTERNAL_SUBTITLE = 1001
internal const val REQUEST_CODE_SUBTITLE_SEARCH = 1002
internal const val SHARED_PREFERENCES_NAME = "FlutterSharedPreferences"
internal const val PLAYBACK_MEMORY_STORAGE_KEY = "flutter.starflow.playback.memory.v1"
internal const val RECENT_ENTRY_LIMIT = 20
internal const val NATIVE_HTTP_CONNECT_TIMEOUT_MS = 15_000
internal const val NETWORK_SPEED_STALE_AFTER_MS = 2_500L
internal const val NATIVE_HTTP_READ_TIMEOUT_MS = 30_000
internal const val CONTROLLER_SHOW_TIMEOUT_MS = 4_000
internal const val PLAYBACK_LAUNCH_TIMEOUT_MS = 30_000L
internal const val PLAYBACK_WATCHDOG_INTERVAL_MS = 5_000L
internal const val PLAYBACK_RUNTIME_INITIAL_DELAY_MS = 500L
internal const val PLAYBACK_RUNTIME_INTERVAL_MS = 1_000L
internal const val PLAYBACK_PROGRESS_PERSIST_INTERVAL_MS = 10_000L
internal const val PLAYBACK_RUNTIME_LOG_INTERVAL_MS = 10_000L
internal const val OUTRO_SKIP_END_MARGIN_MS = 400L
internal val SUBTITLE_DELAY_OPTIONS_MS =
    listOf(-5_000L, -2_000L, -1_000L, -500L, 0L, 500L, 1_000L, 2_000L, 5_000L)
internal val PLAYBACK_SPEED_OPTIONS = listOf(0.75f, 1.0f, 1.25f, 1.5f, 1.75f, 2.0f)
internal val SUBTITLE_SCALE_OPTIONS =
    listOf(20.0, 24.0, 28.0, 32.0, 36.0, 42.0, 48.0, 56.0, 64.0, 78.0)
internal val SUBTITLE_POSITION_OPTIONS = NativeSubtitlePositionPolicy.options
internal val SECONDARY_SUBTITLE_SCALE_OPTIONS =
    listOf(
        50.0,
        55.0,
        60.0,
        65.0,
        70.0,
        75.0,
        80.0,
        85.0,
        90.0,
        95.0,
        100.0,
        105.0,
        110.0,
        115.0,
        120.0,
    )
