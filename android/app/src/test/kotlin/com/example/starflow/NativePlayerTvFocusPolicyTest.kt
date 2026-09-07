package com.example.starflow

import androidx.media3.ui.R as Media3UiR
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativePlayerTvFocusPolicyTest {
    @Test
    fun `progress confirmation toggles only on television without overlays`() {
        assertTrue(NativePlayerTvFocusPolicy.shouldToggleFromProgress(true, true, false))
        assertFalse(NativePlayerTvFocusPolicy.shouldToggleFromProgress(false, true, false))
        assertFalse(NativePlayerTvFocusPolicy.shouldToggleFromProgress(true, false, false))
        assertFalse(NativePlayerTvFocusPolicy.shouldToggleFromProgress(true, true, true))
    }

    @Test
    fun `default remote focus targets progress`() {
        assertTrue(
            NativePlayerTvFocusPolicy.primaryFocusOrder.contentEquals(
                intArrayOf(Media3UiR.id.exo_progress),
            ),
        )
    }

    @Test
    fun `keeps only progress focusable on television`() {
        assertTrue(
            NativePlayerTvFocusPolicy.focusableControlIds.contentEquals(
                intArrayOf(Media3UiR.id.exo_progress),
            ),
        )
        assertFalse(
            NativePlayerTvFocusPolicy.focusableControlIds.contains(
                Media3UiR.id.exo_subtitle,
            ),
        )
        assertFalse(
            NativePlayerTvFocusPolicy.focusableControlIds.contains(
                R.id.native_audio_track_button,
            ),
        )
        assertFalse(
            NativePlayerTvFocusPolicy.focusableControlIds.contains(
                R.id.native_playback_settings,
            ),
        )
    }

    @Test
    fun `excludes play pause and the three right bottom controls`() {
        assertTrue(
            NativePlayerTvFocusPolicy.nonFocusableControlIds.contains(Media3UiR.id.exo_play_pause),
        )
        assertTrue(
            NativePlayerTvFocusPolicy.nonFocusableControlIds.contains(
                Media3UiR.id.exo_subtitle,
            ),
        )
        assertTrue(
            NativePlayerTvFocusPolicy.nonFocusableControlIds.contains(
                R.id.native_audio_track_button,
            ),
        )
        assertTrue(
            NativePlayerTvFocusPolicy.nonFocusableControlIds.contains(
                R.id.native_playback_settings,
            ),
        )
    }
}
