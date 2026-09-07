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
    fun `default remote focus targets play pause`() {
        assertTrue(
            NativePlayerTvFocusPolicy.primaryFocusOrder.contentEquals(
                intArrayOf(Media3UiR.id.exo_play_pause),
            ),
        )
    }

    @Test
    fun `keeps only play pause focusable on television`() {
        assertTrue(
            NativePlayerTvFocusPolicy.focusableControlIds.contentEquals(
                intArrayOf(Media3UiR.id.exo_play_pause),
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
    fun `excludes the three right bottom controls`() {
        assertTrue(
            NativePlayerTvFocusPolicy.removedBottomRightControlIds.contains(
                Media3UiR.id.exo_subtitle,
            ),
        )
        assertTrue(
            NativePlayerTvFocusPolicy.removedBottomRightControlIds.contains(
                R.id.native_audio_track_button,
            ),
        )
        assertTrue(
            NativePlayerTvFocusPolicy.removedBottomRightControlIds.contains(
                R.id.native_playback_settings,
            ),
        )
    }
}
