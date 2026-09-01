package com.example.starflow

import androidx.media3.common.C
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import java.io.IOException
import java.io.InterruptedIOException
import java.net.SocketException
import kotlin.math.min

enum class NativeLoadFailureKind {
    TRANSIENT,
    PERMANENT,
    UNKNOWN,
}

object NativePlaybackLoadErrorClassifier {
    fun classifyHttpStatus(statusCode: Int): NativeLoadFailureKind = when {
        statusCode == 408 || statusCode == 425 || statusCode == 429 ->
            NativeLoadFailureKind.TRANSIENT
        statusCode in 500..599 -> NativeLoadFailureKind.TRANSIENT
        statusCode in setOf(400, 401, 403, 404, 405, 410, 416) ->
            NativeLoadFailureKind.PERMANENT
        else -> NativeLoadFailureKind.UNKNOWN
    }

    fun retryDelayMs(errorCount: Int): Long {
        if (errorCount > MAX_TRANSIENT_RETRIES) {
            return C.TIME_UNSET
        }
        val shift = (errorCount - 1).coerceIn(0, 4)
        return min(8_000L, 500L * (1L shl shift))
    }

    const val MAX_TRANSIENT_RETRIES = 6
}

class NativePlaybackLoadErrorPolicy : DefaultLoadErrorHandlingPolicy() {
    override fun getRetryDelayMsFor(
        loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo,
    ): Long {
        val error = loadErrorInfo.exception
        val responseCode = findInvalidResponseCode(error)
        if (responseCode != null) {
            return when (
                NativePlaybackLoadErrorClassifier.classifyHttpStatus(responseCode)
            ) {
                NativeLoadFailureKind.PERMANENT -> C.TIME_UNSET
                NativeLoadFailureKind.TRANSIENT ->
                    NativePlaybackLoadErrorClassifier.retryDelayMs(loadErrorInfo.errorCount)
                NativeLoadFailureKind.UNKNOWN -> super.getRetryDelayMsFor(loadErrorInfo)
            }
        }
        if (hasTransientNetworkCause(error)) {
            return NativePlaybackLoadErrorClassifier.retryDelayMs(loadErrorInfo.errorCount)
        }
        return super.getRetryDelayMsFor(loadErrorInfo)
    }

    override fun getMinimumLoadableRetryCount(dataType: Int): Int =
        NativePlaybackLoadErrorClassifier.MAX_TRANSIENT_RETRIES

    private fun findInvalidResponseCode(error: Throwable?): Int? {
        var current = error
        while (current != null) {
            if (current is HttpDataSource.InvalidResponseCodeException) {
                return current.responseCode
            }
            current = current.cause
        }
        return null
    }

    private fun hasTransientNetworkCause(error: IOException): Boolean {
        var current: Throwable? = error
        while (current != null) {
            if (current is HttpDataSource.InvalidContentTypeException ||
                current is HttpDataSource.CleartextNotPermittedException
            ) {
                return false
            }
            current = current.cause
        }
        current = error
        while (current != null) {
            if (current is InterruptedIOException ||
                current is SocketException ||
                current is HttpDataSource.HttpDataSourceException
            ) {
                return true
            }
            current = current.cause
        }
        return false
    }
}
