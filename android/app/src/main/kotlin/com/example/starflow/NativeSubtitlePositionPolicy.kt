package com.example.starflow

import androidx.media3.common.text.Cue
import androidx.media3.common.text.CueGroup

internal object NativeSubtitlePositionPolicy {
    fun positionFraction(percent: Double, defaultPercent: Double): Float =
        ((if (percent.isFinite()) percent else defaultPercent).coerceIn(50.0, 100.0) / 100.0)
            .toFloat()

    fun bottomPaddingFraction(percent: Double): Float =
        1f - positionFraction(percent, defaultPercent = 80.0)

    fun applyPrimaryPosition(cueGroup: CueGroup): CueGroup = CueGroup(
        cueGroup.cues.map { cue ->
            // Media3 ignores bottomPaddingFraction when a text cue specifies its own line.
            if (cue.bitmap != null) cue else cue.buildUpon()
                .setLine(Cue.DIMEN_UNSET, Cue.TYPE_UNSET)
                .setLineAnchor(Cue.TYPE_UNSET)
                .build()
        },
        cueGroup.presentationTimeUs,
    )
}
