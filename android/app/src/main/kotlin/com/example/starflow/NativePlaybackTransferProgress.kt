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
    var networkBytesPerSecond: Long? = null
        private set

    @Synchronized
    fun sampleNetworkSpeed() {
        val sampledAt = now()
        val elapsed = sampledAt - sampledAtMs
        if (elapsed < 1_000L) return
        networkBytesPerSecond = speedWindow.add((bytes.toDouble() * 1_000 / elapsed).toLong())
        bytes = 0L
        sampledAtMs = sampledAt
    }

    @Volatile
    var lastProgressAtMs = -1L
        private set

    override fun onTransferInitializing(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) = Unit

    override fun onTransferStart(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) = Unit

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

    override fun onTransferEnd(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) = Unit
}
