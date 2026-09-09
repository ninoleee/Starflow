package com.example.starflow

internal enum class PlaybackPhase {
    preparing, playing, paused, buffering, recovering, ended, failed;

    val showsLoading: Boolean
        get() = this == preparing || this == buffering || this == recovering
}

internal object PlaybackReliabilityPolicy {
    fun phase(
        ready: Boolean,
        playing: Boolean,
        buffering: Boolean,
        recovering: Boolean = false,
        ended: Boolean = false,
        failed: Boolean = false,
    ): PlaybackPhase = when {
        failed -> PlaybackPhase.failed
        ended -> PlaybackPhase.ended
        recovering -> PlaybackPhase.recovering
        !ready -> PlaybackPhase.preparing
        buffering -> PlaybackPhase.buffering
        playing -> PlaybackPhase.playing
        else -> PlaybackPhase.paused
    }

    fun classifyHttpStatus(status: Int?): NativeLoadFailureKind = when {
        status in PlaybackPolicyValues.transientHttpStatuses ||
            (status != null && status in 500..599) -> NativeLoadFailureKind.TRANSIENT
        status in PlaybackPolicyValues.permanentHttpStatuses -> NativeLoadFailureKind.PERMANENT
        else -> NativeLoadFailureKind.UNKNOWN
    }

    fun isAddressRefreshable(status: Int?): Boolean =
        status in PlaybackPolicyValues.refreshableHttpStatuses

    fun failureLabel(kind: NativeLoadFailureKind): String = when (kind) {
        NativeLoadFailureKind.TRANSIENT -> "transientNetwork"
        NativeLoadFailureKind.PERMANENT -> "permanent"
        NativeLoadFailureKind.UNKNOWN -> "unknown"
    }
}

internal class PlaybackBufferProgress {
    private var bufferMs = 0L
    private var percentage = 0

    fun reset() {
        bufferMs = 0L
        percentage = 0
    }

    fun observe(bufferedPositionMs: Long, bufferedPercentage: Int): Boolean {
        var advanced = false
        if (bufferedPositionMs - bufferMs >= PlaybackPolicyValues.bufferAdvanceMs) {
            bufferMs = bufferedPositionMs
            advanced = true
        }
        val normalized = bufferedPercentage.coerceIn(0, 100)
        if (normalized - percentage >= PlaybackPolicyValues.bufferAdvancePercent) {
            percentage = normalized
            advanced = true
        }
        return advanced
    }
}

internal class PlaybackRecoveryBudget {
    var attempts = 0
        private set

    fun take(): Boolean {
        if (attempts >= PlaybackPolicyValues.maxRuntimeRecoveries) return false
        attempts++
        return true
    }

    fun reset() { attempts = 0 }
}
