package com.example.starflow

import android.content.Context
import android.content.Intent

internal object ApplicationExitPolicy {
    const val POST_INPUT_RELEASE_DELAY_MS = 120L
    const val INPUT_RELEASE_TIMEOUT_MS = 2_000L
    const val RELAUNCH_SUPPRESSION_WINDOW_MS = 5_000L

    fun isLauncherIntent(action: String?, categories: Set<String>?): Boolean {
        if (action != Intent.ACTION_MAIN) {
            return false
        }
        return categories?.contains(Intent.CATEGORY_LAUNCHER) == true ||
            categories?.contains(Intent.CATEGORY_LEANBACK_LAUNCHER) == true
    }

    fun shouldSuppressLauncherRelaunch(
        lastExitRequestedAtMs: Long,
        nowMs: Long,
    ): Boolean {
        if (lastExitRequestedAtMs <= 0L || nowMs < lastExitRequestedAtMs) {
            return false
        }
        return nowMs - lastExitRequestedAtMs <= RELAUNCH_SUPPRESSION_WINDOW_MS
    }
}

internal object ApplicationExitGate {
    private const val preferencesName = "starflow_application_exit"
    private const val lastExitRequestedAtKey = "last_exit_requested_at_ms"

    fun markExitRequested(context: Context, nowMs: Long = System.currentTimeMillis()) {
        context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .edit()
            .putLong(lastExitRequestedAtKey, nowMs)
            .commit()
    }

    fun shouldSuppressLauncherRelaunch(
        context: Context,
        intent: Intent?,
        nowMs: Long = System.currentTimeMillis(),
    ): Boolean {
        if (!ApplicationExitPolicy.isLauncherIntent(intent?.action, intent?.categories)) {
            return false
        }
        val preferences = context.getSharedPreferences(
            preferencesName,
            Context.MODE_PRIVATE,
        )
        val lastExitRequestedAtMs = preferences.getLong(lastExitRequestedAtKey, 0L)
        val shouldSuppress = ApplicationExitPolicy.shouldSuppressLauncherRelaunch(
            lastExitRequestedAtMs = lastExitRequestedAtMs,
            nowMs = nowMs,
        )
        if (!shouldSuppress && lastExitRequestedAtMs > 0L) {
            preferences.edit().remove(lastExitRequestedAtKey).apply()
        }
        return shouldSuppress
    }

}
