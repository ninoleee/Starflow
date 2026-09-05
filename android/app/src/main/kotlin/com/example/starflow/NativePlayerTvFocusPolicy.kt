package com.example.starflow

import androidx.media3.ui.R as Media3UiR

internal enum class ControllerFocusTarget {
    NONE,
    PLAYER,
    PRIMARY,
    SETTINGS,
    AUDIO,
    SUBTITLE,
}

internal object NativePlayerTvFocusPolicy {
    val focusableControlIds: IntArray = intArrayOf(Media3UiR.id.exo_play_pause)
    val primaryFocusOrder: IntArray = intArrayOf(Media3UiR.id.exo_play_pause)
    val removedBottomRightControlIds: IntArray =
        intArrayOf(
            Media3UiR.id.exo_subtitle,
            R.id.native_audio_track_button,
            R.id.native_playback_settings,
        )
}
