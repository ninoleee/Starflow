package com.example.starflow

object NativePlaybackResumePolicy {
    fun resolveResumePositionMs(
        allowResume: Boolean,
        pendingOverrideMs: Long?,
        storedResumeMs: Long,
    ): Long {
        return pendingOverrideMs ?: if (allowResume) storedResumeMs else 0L
    }
}
