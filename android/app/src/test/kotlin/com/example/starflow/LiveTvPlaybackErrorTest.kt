package com.example.starflow

import androidx.media3.common.PlaybackException
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.net.ssl.SSLHandshakeException
import org.junit.Assert.*
import org.junit.Test

class LiveTvPlaybackErrorTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()
    private val secret = "https://private.test/account/password/live?token=secret"

    @Test fun httpStatusSurvivesNestedTransportErrorsWithoutHeadersOrMessages() {
        for (status in listOf(401, 403, 404, 410, 429, 500, 503)) {
            val error = PlaybackException(secret, IOException(secret,
                LiveTvHttpTransport.HttpStatusException(status, mapOf("Set-Cookie" to listOf(secret)))),
                PlaybackException.ERROR_CODE_IO_UNSPECIFIED)
            assertEquals(mapOf("errorCategory" to "http", "nativeErrorCode" to 2000, "httpStatus" to status),
                LiveTvPlaybackError.details(error))
        }
    }

    @Test fun networkCategoriesAreBasedOnTypesNotSensitiveMessages() {
        for ((cause, category) in listOf(
            UnknownHostException(secret) to "dns",
            SocketTimeoutException(secret) to "timeout",
            SSLHandshakeException(secret) to "tls",
            ConnectException(secret) to "connection",
            IOException(secret) to "io",
            IllegalStateException(secret) to "unknown",
        )) {
            val summary = LiveTvPlaybackError.details(PlaybackException(secret, cause, 2000))
            assertEquals(category, summary["errorCategory"])
            assertFalse(summary.toString().contains("private.test"))
            assertFalse(summary.containsKey("httpStatus"))
        }
    }

    @Test fun nativeCodesDistinguishFormatDecodingAudioAndLiveWindowFailures() {
        for ((code, category) in listOf(
            PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED to "container",
            PlaybackException.ERROR_CODE_DECODER_INIT_FAILED to "decoder",
            PlaybackException.ERROR_CODE_AUDIO_TRACK_INIT_FAILED to "audio",
            PlaybackException.ERROR_CODE_DRM_SCHEME_UNSUPPORTED to "drm",
            PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW to "behindLiveWindow",
            PlaybackException.ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED to "cleartext",
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED to "connection",
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT to "timeout",
        )) {
            val summary = LiveTvPlaybackError.details(PlaybackException(secret, null, code))
            assertEquals(category, summary["errorCategory"])
            assertEquals(code, summary["nativeErrorCode"])
        }
    }

    @Test fun unknownAndCyclicCausesRemainBoundedAndDoNotExposeText() {
        val first = IOException(secret)
        val second = IOException(secret, first)
        first.initCause(second)
        assertEquals(mapOf("errorCategory" to "io"), LiveTvPlaybackError.details(first))
        assertEquals(mapOf("errorCategory" to "unknown"), LiveTvPlaybackError.details(IllegalArgumentException(secret)))
    }
}
