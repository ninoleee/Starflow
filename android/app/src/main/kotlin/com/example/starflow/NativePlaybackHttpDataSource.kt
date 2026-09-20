package com.example.starflow

import android.content.Context
import android.net.Uri
import androidx.media3.common.C
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.datasource.TransferListener
import java.io.EOFException
import java.io.IOException

/** The launch URL owns credentials, not a redirect, variant, key or subtitle URL. */
internal class NativePlaybackHttpDataSource(
    private val sourceUrl: String,
    private val headers: Map<String, String>,
) : BaseDataSource(true) {
    private var response: LiveTvHttpTransport.Response? = null
    private var remaining = C.LENGTH_UNSET.toLong()

    override fun open(dataSpec: DataSpec): Long {
        check(response == null)
        if (dataSpec.httpMethod != DataSpec.HTTP_METHOD_GET) throw IOException("Unsupported playback HTTP method")
        transferInitializing(dataSpec)
        val url = dataSpec.uri.toString()
        // Local media may have remote subtitles, but cannot confer HTTP credentials.
        val origin = runCatching { LiveTvHttpPolicy.parse(sourceUrl).toString() }.getOrNull()
        val policy = try {
            LiveTvHttpPolicy(origin ?: url, if (origin == null) emptyMap<String, String>() else headers + dataSpec.httpRequestHeaders)
        } catch (_: IllegalArgumentException) {
            throw IOException("Invalid playback request")
        }
        val opened = try {
            LiveTvHttpTransport(policy, NATIVE_HTTP_CONNECT_TIMEOUT_MS, NATIVE_HTTP_READ_TIMEOUT_MS)
                .open(url, dataSpec.position, dataSpec.length, dataSpec.isFlagSet(DataSpec.FLAG_ALLOW_GZIP))
        } catch (error: LiveTvHttpTransport.HttpStatusException) {
            // Preserve status-based retry/address-refresh decisions without retaining response bodies.
            throw HttpDataSource.InvalidResponseCodeException(
                error.status, null, null, error.headers, dataSpec, ByteArray(0))
        }
        response = opened
        remaining = opened.length
        transferStarted(dataSpec)
        return remaining
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (remaining == 0L) return C.RESULT_END_OF_INPUT
        val opened = response ?: throw IOException("Playback connection closed")
        val count = opened.stream.read(buffer, offset,
            if (remaining < 0) length else minOf(remaining, length.toLong()).toInt())
        if (count == -1) {
            if (remaining > 0) throw EOFException("Truncated playback response")
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

    companion object {
        fun factory(context: Context, url: String, headers: Map<String, String>, listener: TransferListener): DataSource.Factory =
            DefaultDataSource.Factory(context, DataSource.Factory { NativePlaybackHttpDataSource(url, headers) })
                .setTransferListener(listener)
    }
}
