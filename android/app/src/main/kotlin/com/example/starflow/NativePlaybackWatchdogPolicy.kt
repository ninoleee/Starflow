package com.example.starflow

internal class NativePlaybackWatchdogPolicy(
    private val now: () -> Long = System::currentTimeMillis
) {
    enum class Recovery {
        NONE,
        WAIT_FOR_BANDWIDTH,
        SOFT,
        RESTART,
    }

    private var lastPositionMs = 0L
    private var lastProgressAtMs = 0L
    private var lastBufferedPositionMs = 0L
    private var lastBufferedPercentage = 0
    private var lastBufferActivityAtMs = 0L
    private var recoveries = 0
    private var lastRecoveryAtMs = 0L

    fun clearRecoveries() {
        recoveries = 0
        lastRecoveryAtMs = 0L
    }

    fun markActivity(positionMs: Long, bufferedPositionMs: Long?, bufferedPercentage: Int?) {
        lastPositionMs = positionMs.coerceAtLeast(0L)
        lastProgressAtMs = now()
        if (bufferedPositionMs != null && bufferedPercentage != null) {
            lastBufferedPositionMs = bufferedPositionMs
            lastBufferedPercentage = bufferedPercentage.coerceIn(0, 100)
            lastBufferActivityAtMs = now()
        }
    }

    fun reset(positionMs: Long, bufferedPositionMs: Long?, bufferedPercentage: Int?) {
        markActivity(positionMs, bufferedPositionMs, bufferedPercentage)
        clearRecoveries()
    }

    fun isStalled(
        positionMs: Long,
        bufferedPositionMs: Long,
        bufferedPercentage: Int,
        buffering: Boolean,
        playing: Boolean,
    ): Boolean {
        val timeMs = now()
        val position = positionMs.coerceAtLeast(0L)
        val bufferedPosition = bufferedPositionMs.coerceAtLeast(position)
        val percentage = bufferedPercentage.coerceIn(0, 100)
        if (
            bufferedPosition > lastBufferedPositionMs + BUFFER_ADVANCE_THRESHOLD_MS ||
                percentage > lastBufferedPercentage
        ) {
            lastBufferedPositionMs = bufferedPosition
            lastBufferedPercentage = percentage
            lastBufferActivityAtMs = timeMs
        }
        if (position > lastPositionMs + 500L || position < lastPositionMs - 1_000L) {
            reset(position, bufferedPosition, percentage)
            return false
        }
        return (buffering && timeMs - lastBufferActivityAtMs >= BUFFERING_TIMEOUT_MS) ||
            (playing && timeMs - lastProgressAtMs >= PROGRESS_TIMEOUT_MS)
    }

    fun recovery(bandwidthInsufficient: () -> Boolean): Recovery {
        val timeMs = now()
        if (timeMs - lastRecoveryAtMs < RECOVERY_COOLDOWN_MS) return Recovery.NONE
        lastRecoveryAtMs = timeMs
        if (bandwidthInsufficient()) {
            lastProgressAtMs = timeMs
            lastBufferActivityAtMs = timeMs
            return Recovery.WAIT_FOR_BANDWIDTH
        }
        recoveries += 1
        return if (recoveries <= SOFT_RECOVERY_LIMIT) Recovery.SOFT else Recovery.RESTART
    }

    // Player callbacks may reset recovery state synchronously during seek/prepare.
    // The activity acknowledges the attempt only after those calls return.
    fun onSoftRecoveryCompleted(startedAtMs: Long) {
        lastProgressAtMs = startedAtMs
    }

    private companion object {
        const val PROGRESS_TIMEOUT_MS = 15_000L
        const val BUFFERING_TIMEOUT_MS = 45_000L
        const val BUFFER_ADVANCE_THRESHOLD_MS = 1_000L
        const val RECOVERY_COOLDOWN_MS = 10_000L
        const val SOFT_RECOVERY_LIMIT = 2
    }
}
