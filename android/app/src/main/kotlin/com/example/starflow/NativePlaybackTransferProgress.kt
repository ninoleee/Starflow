package com.example.starflow

import android.os.SystemClock
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener

internal class NativePlaybackTransferProgress(
    private val now: () -> Long = SystemClock::elapsedRealtime,
) : TransferListener {
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
            lastProgressAtMs = maxOf(lastProgressAtMs, now())
        }
    }

    override fun onTransferEnd(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) = Unit
}
