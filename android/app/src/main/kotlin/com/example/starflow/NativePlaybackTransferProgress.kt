package com.example.starflow

import android.os.SystemClock
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener

internal class NativePlaybackTransferProgress(
    private val now: () -> Long = SystemClock::elapsedRealtime,
) : TransferListener {
    private var bytes = 0L
    private var sampledAtMs = now()
    private val speedWindow = PlaybackNetworkSpeedWindow()
    @Volatile var rawBytesPerSecond: Long? = null
        private set
    private var activeTransfers = 0
    private var activeSinceMs = sampledAtMs
    private var activeDurationMs = 0L
    @Volatile var isNetworkTransferActive = false
        private set
    @Volatile var networkBytesPerSecond: Long? = null
        private set

    @Synchronized
    fun sampleNetworkSpeed() {
        val sampledAt = now()
        val elapsed = sampledAt - sampledAtMs
        if (elapsed < 1_000L) return
        val activeMs = activeDurationMs +
            if (activeTransfers > 0) (sampledAt - activeSinceMs).coerceAtLeast(0) else 0L
        rawBytesPerSecond = if (activeMs > 0) (bytes.toDouble() * 1_000 / activeMs).toLong() else null
        networkBytesPerSecond = speedWindow.add((bytes.toDouble() * 1_000 / elapsed).toLong())
        bytes = 0L
        sampledAtMs = sampledAt
        activeDurationMs = 0L
        activeSinceMs = sampledAt
    }

    internal data class ReadAheadSnapshot(val active: Boolean, val bytesPerSecond: Long?)

    @Synchronized
    fun readAheadSnapshot(): ReadAheadSnapshot {
        sampleNetworkSpeed()
        return ReadAheadSnapshot(isNetworkTransferActive,
            rawBytesPerSecond.takeIf { isNetworkTransferActive })
    }

    @Volatile
    var lastProgressAtMs = -1L
        private set

    override fun onTransferInitializing(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) = Unit

    @Synchronized
    override fun onTransferStart(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) {
        if (isNetwork) {
            if (activeTransfers == 0) {
                activeSinceMs = now()
                rawBytesPerSecond = null
            }
            activeTransfers++
        }
        isNetworkTransferActive = activeTransfers > 0
    }

    @Synchronized
    override fun onBytesTransferred(
        source: DataSource,
        dataSpec: DataSpec,
        isNetwork: Boolean,
        bytesTransferred: Int,
    ) {
        if (isNetwork && bytesTransferred > 0) {
            bytes += bytesTransferred
            lastProgressAtMs = maxOf(lastProgressAtMs, now())
        }
    }

    @Synchronized
    override fun onTransferEnd(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) {
        if (isNetwork && activeTransfers > 0) {
            activeTransfers--
            if (activeTransfers == 0) activeDurationMs += (now() - activeSinceMs).coerceAtLeast(0)
        }
        isNetworkTransferActive = activeTransfers > 0
    }
}
