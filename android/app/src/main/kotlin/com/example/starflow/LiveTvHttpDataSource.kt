package com.example.starflow

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSpec
import java.io.EOFException
import java.io.IOException

internal class LiveTvHttpDataSource(policy: LiveTvHttpPolicy) : BaseDataSource(true) {
    private val transport = LiveTvHttpTransport(policy)
    private var response: LiveTvHttpTransport.Response? = null
    private var remaining = C.LENGTH_UNSET.toLong()

    override fun open(dataSpec: DataSpec): Long {
        check(response == null)
        if (dataSpec.httpMethod != DataSpec.HTTP_METHOD_GET) throw IOException("Unsupported live HTTP method")
        transferInitializing(dataSpec)
        val opened = transport.open(
            dataSpec.uri.toString(), dataSpec.position, dataSpec.length, dataSpec.isFlagSet(DataSpec.FLAG_ALLOW_GZIP),
        )
        response = opened
        remaining = opened.length
        transferStarted(dataSpec)
        return remaining
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (remaining == 0L) return C.RESULT_END_OF_INPUT
        val opened = response ?: throw IOException("Live connection closed")
        val count = opened.stream.read(buffer, offset, if (remaining < 0) length else minOf(remaining, length.toLong()).toInt())
        if (count == -1) {
            if (remaining > 0) throw EOFException("Truncated live response")
            return C.RESULT_END_OF_INPUT
        }
        if (remaining >= 0) remaining -= count
        bytesTransferred(count)
        return count
    }

    override fun getUri(): Uri? = response?.connection?.url?.toString()?.let(Uri::parse)

    override fun getResponseHeaders(): Map<String, List<String>> =
        response?.connection?.headerFields?.entries?.mapNotNull { (key, value) ->
            if (key == null || value == null) null else key to value
        }?.toMap() ?: emptyMap()

    override fun close() {
        val old = response ?: return
        response = null
        try { old.stream.close() } finally {
            old.connection.disconnect()
            transferEnded()
        }
    }
}
