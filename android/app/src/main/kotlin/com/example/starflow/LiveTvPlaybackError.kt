package com.example.starflow

import androidx.media3.common.PlaybackException
import androidx.media3.datasource.HttpDataSource
import java.io.IOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.net.ssl.SSLException

/** Only stable categories and numeric codes cross the bridge, never exception text or URLs. */
internal object LiveTvPlaybackError {
    fun details(error: Throwable): Map<String, Any> {
        val causes = generateSequence(error) { it.cause }.take(10).toList()
        val code = (error as? PlaybackException)?.errorCode
        val status = causes.firstNotNullOfOrNull {
            when (it) {
                is LiveTvHttpTransport.HttpStatusException -> it.status
                is HttpDataSource.InvalidResponseCodeException -> it.responseCode
                else -> null
            }
        }?.takeIf { it in 100..599 }
        val category = when {
            status != null -> "http"
            causes.any { it is UnknownHostException } -> "dns"
            causes.any { it is SocketTimeoutException } ||
                code == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT -> "timeout"
            causes.any { it is SSLException } -> "tls"
            causes.any { it is ConnectException || it is NoRouteToHostException || it is SocketException } ||
                code == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED -> "connection"
            code == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW -> "behindLiveWindow"
            code == PlaybackException.ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED -> "cleartext"
            code != null && code in 3000..3999 -> "container"
            code != null && code in 4000..4999 -> "decoder"
            code != null && code in 5000..5999 -> "audio"
            code != null && code in 6000..6999 -> "drm"
            causes.any { it is IOException } -> "io"
            else -> "unknown"
        }
        return buildMap {
            put("errorCategory", category)
            if (code != null) put("nativeErrorCode", code)
            if (status != null) put("httpStatus", status)
        }
    }
}
