package com.example.starflow

import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import java.util.concurrent.atomic.AtomicLong

/** Per-open media reads only; loader threads never touch the platform channel. */
internal class LiveTvNetworkSpeed(private val nowMs: () -> Long) : TransferListener {
    private val bytes = AtomicLong()
    private var sampledAt = nowMs()
    var bytesPerSecond: Long? = null
        private set

    fun sample() {
        val now = nowMs()
        val elapsed = now - sampledAt
        if (elapsed <= 0) return
        bytesPerSecond = (bytes.getAndSet(0).toDouble() * 1000 / elapsed).toLong()
        sampledAt = now
    }

    override fun onTransferInitializing(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) = Unit
    override fun onTransferStart(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) = Unit
    override fun onTransferEnd(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) = Unit
    override fun onBytesTransferred(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean, bytesTransferred: Int) {
        if (isNetwork && bytesTransferred > 0) bytes.addAndGet(bytesTransferred.toLong())
    }
}
