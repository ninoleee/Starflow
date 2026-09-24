package com.example.starflow

import androidx.media3.common.C
import androidx.media3.datasource.DataSpec
import androidx.media3.exoplayer.source.LoadEventInfo
import androidx.media3.exoplayer.source.MediaLoadData
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import java.io.IOException
import org.mockito.Mockito.mock
import org.junit.Assert.assertEquals
import org.junit.Test

class NativePlaybackLoadErrorPolicyTest {
    @Test
    fun `policy rejection is not retried even when wrapped as an IO error`() {
        val rejection = LiveTvHttpTransport.PolicyException(
            MediaHttpPolicyException(MediaHttpRejection.HTTPS_DOWNGRADE))
        for (error in listOf(rejection, IOException("Source error", rejection))) {
            val info = LoadErrorHandlingPolicy.LoadErrorInfo(
                LoadEventInfo(1L, mock(DataSpec::class.java), 0L),
                MediaLoadData(C.DATA_TYPE_MEDIA), error, 1)
            assertEquals(C.TIME_UNSET, NativePlaybackLoadErrorPolicy().getRetryDelayMsFor(info))
        }
    }

    @Test
    fun `classifies permanent and transient HTTP statuses`() {
        assertEquals(
            NativeLoadFailureKind.PERMANENT,
            NativePlaybackLoadErrorClassifier.classifyHttpStatus(404),
        )
        assertEquals(
            NativeLoadFailureKind.TRANSIENT,
            NativePlaybackLoadErrorClassifier.classifyHttpStatus(429),
        )
        assertEquals(
            NativeLoadFailureKind.TRANSIENT,
            NativePlaybackLoadErrorClassifier.classifyHttpStatus(503),
        )
        assertEquals(
            NativeLoadFailureKind.UNKNOWN,
            NativePlaybackLoadErrorClassifier.classifyHttpStatus(418),
        )
    }

    @Test
    fun `backs off transient failures and stops after bounded retries`() {
        assertEquals(500L, NativePlaybackLoadErrorClassifier.retryDelayMs(1))
        assertEquals(1_000L, NativePlaybackLoadErrorClassifier.retryDelayMs(2))
        assertEquals(8_000L, NativePlaybackLoadErrorClassifier.retryDelayMs(6))
        assertEquals(C.TIME_UNSET, NativePlaybackLoadErrorClassifier.retryDelayMs(7))
    }
}
