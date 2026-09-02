package com.example.starflow

import android.content.Intent
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ApplicationExitPolicyTest {
    @Test
    fun recognizesPhoneAndTelevisionLauncherIntents() {
        assertTrue(
            ApplicationExitPolicy.isLauncherIntent(
                action = Intent.ACTION_MAIN,
                categories = setOf(Intent.CATEGORY_LAUNCHER),
            ),
        )
        assertTrue(
            ApplicationExitPolicy.isLauncherIntent(
                action = Intent.ACTION_MAIN,
                categories = setOf(Intent.CATEGORY_LEANBACK_LAUNCHER),
            ),
        )
        assertFalse(
            ApplicationExitPolicy.isLauncherIntent(
                action = Intent.ACTION_VIEW,
                categories = setOf(Intent.CATEGORY_LEANBACK_LAUNCHER),
            ),
        )
        assertFalse(
            ApplicationExitPolicy.isLauncherIntent(
                action = Intent.ACTION_MAIN,
                categories = emptySet(),
            ),
        )
    }

    @Test
    fun suppressesLauncherRelaunchInsideGuardWindow() {
        val exitRequestedAtMs = 10_000L

        assertTrue(
            ApplicationExitPolicy.shouldSuppressLauncherRelaunch(
                lastExitRequestedAtMs = exitRequestedAtMs,
                nowMs = exitRequestedAtMs + 1,
            ),
        )
        assertTrue(
            ApplicationExitPolicy.shouldSuppressLauncherRelaunch(
                lastExitRequestedAtMs = exitRequestedAtMs,
                nowMs = exitRequestedAtMs +
                    ApplicationExitPolicy.RELAUNCH_SUPPRESSION_WINDOW_MS,
            ),
        )
    }

    @Test
    fun allowsLauncherRelaunchOutsideGuardWindow() {
        val exitRequestedAtMs = 10_000L

        assertFalse(
            ApplicationExitPolicy.shouldSuppressLauncherRelaunch(
                lastExitRequestedAtMs = 0L,
                nowMs = exitRequestedAtMs,
            ),
        )
        assertFalse(
            ApplicationExitPolicy.shouldSuppressLauncherRelaunch(
                lastExitRequestedAtMs = exitRequestedAtMs,
                nowMs = exitRequestedAtMs - 1,
            ),
        )
        assertFalse(
            ApplicationExitPolicy.shouldSuppressLauncherRelaunch(
                lastExitRequestedAtMs = exitRequestedAtMs,
                nowMs = exitRequestedAtMs +
                    ApplicationExitPolicy.RELAUNCH_SUPPRESSION_WINDOW_MS + 1,
            ),
        )
    }

    @Test
    fun inputReleaseTimingFitsInsideRelaunchGuard() {
        assertTrue(
            ApplicationExitPolicy.POST_INPUT_RELEASE_DELAY_MS <
                ApplicationExitPolicy.INPUT_RELEASE_TIMEOUT_MS,
        )
        assertTrue(
            ApplicationExitPolicy.INPUT_RELEASE_TIMEOUT_MS <
                ApplicationExitPolicy.RELAUNCH_SUPPRESSION_WINDOW_MS,
        )
    }
}
