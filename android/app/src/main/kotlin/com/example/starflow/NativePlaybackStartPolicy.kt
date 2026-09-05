package com.example.starflow

internal data class NativePlaybackStartPosition(
    val positionMs: Long,
    val isResume: Boolean = false,
    val introPositionMs: Long = 0L,
)

internal object NativePlaybackStartPolicy {
    fun resolve(
        allowResume: Boolean,
        runtimeOverrideMs: Long?,
        storedResumeMs: Long,
        automaticNext: Boolean,
        skipEnabled: Boolean,
        introDurationMs: Long,
    ): NativePlaybackStartPosition {
        val resumeMs =
            NativePlaybackResumePolicy.resolveResumePositionMs(
                allowResume,
                runtimeOverrideMs,
                storedResumeMs,
            )
        if (runtimeOverrideMs != null) {
            return NativePlaybackStartPosition(resumeMs.coerceAtLeast(0L))
        }
        if (!automaticNext) {
            if (!allowResume) return NativePlaybackStartPosition(0L)
            if (resumeMs > 0L) return NativePlaybackStartPosition(resumeMs, isResume = true)
        }
        val introMs = if (skipEnabled) introDurationMs.coerceAtLeast(0L) else 0L
        return NativePlaybackStartPosition(introMs, introPositionMs = introMs)
    }
}

internal object NativePlaybackSkipPolicy {
    fun endBoundaryMs(durationMs: Long, enabled: Boolean, outroMs: Long): Long {
        return if (enabled && outroMs in 1 until durationMs) durationMs - outroMs else durationMs
    }

    fun shouldPrepareNext(positionMs: Long, boundaryMs: Long): Boolean =
        boundaryMs > 0L &&
            positionMs >= (boundaryMs - 30_000L).coerceAtLeast(0L) &&
            positionMs < boundaryMs
}
