package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.TrackGroup
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.analytics.AnalyticsListener
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackVideoDiagnosticsTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()

    private val host = mock(NativePlaybackDiagnostics.Host::class.java)
    private val session = mock(NativePlaybackSession::class.java)
    private val records = mutableListOf<String>()
    private val diagnostics = NativePlaybackDiagnostics(host,
        invokeResolver = { _, _, _ -> }, logVideoDiagnostic = { records += it })

    @Test
    fun trackLogsDistinguishEveryMedia3SupportState() {
        val format = Format.Builder().setSampleMimeType(MimeTypes.VIDEO_H264)
            .setCodecs("avc1.640034").setWidth(3840).setHeight(2160).setFrameRate(30f).build()
        for ((code, label) in listOf(
            C.FORMAT_HANDLED to "handled",
            C.FORMAT_EXCEEDS_CAPABILITIES to "exceeds-capabilities",
            C.FORMAT_UNSUPPORTED_DRM to "unsupported-drm",
            C.FORMAT_UNSUPPORTED_SUBTYPE to "unsupported-subtype",
            C.FORMAT_UNSUPPORTED_TYPE to "unsupported-type",
        )) {
            diagnostics.logVideoTracks(Tracks(listOf(Tracks.Group(TrackGroup(format), false,
                intArrayOf(code), booleanArrayOf(true)))))
            val row = records.last()
            assertTrue(row.contains(":supportCode=$code:support=$label"))
            assertTrue(row.contains(":supported=${code == C.FORMAT_HANDLED}"))
            assertTrue(row.contains(":width=3840:height=2160:frameRate=30.0"))
            assertTrue(row.contains(":codecs=avc1.640034"))
            assertTrue(row.contains(":selected=true"))
        }
        assertEquals("unknown", NativePlaybackFormatting.formatTrackSupport(999))
        diagnostics.logVideoTracks(Tracks.EMPTY)
        assertEquals("native.video.tracks none", records.last())
    }

    @Test
    fun decoderLifecycleLogsActualNameWithoutHealthSampleOrExceptionMessage() {
        `when`(host.session).thenReturn(session)
        // No active player means health sampling is unavailable; events must remain visible.
        val listener = diagnostics.playbackPerformanceAnalyticsListener
        val event = mock(AnalyticsListener.EventTime::class.java)
        listener.onVideoDecoderInitialized(event, "c2.vendor.avc.decoder", 1, 37)
        assertEquals("native.video.decoder.initialized name=c2.vendor.avc.decoder durationMs=37", records.last())
        listener.onVideoCodecError(event, IllegalStateException("https://private.test/?token=secret"))
        assertEquals("native.video.decoder.error name=c2.vendor.avc.decoder type=IllegalStateException", records.last())
        listener.onVideoDecoderInitialized(event, "c2.android.avc.decoder", 2, 15)
        listener.onVideoDecoderReleased(event, "c2.vendor.avc.decoder")
        listener.onVideoCodecError(event, IllegalStateException())
        assertTrue(records.last().contains("name=c2.android.avc.decoder"))
        listener.onVideoDecoderReleased(event, "c2.android.avc.decoder")
        assertEquals("native.video.decoder.released name=c2.android.avc.decoder", records.last())
        listener.onVideoCodecError(event, IllegalStateException())
        assertTrue(records.last().contains("name=unknown"))
        assertFalse(records.joinToString().contains("secret"))
        assertFalse(records.joinToString().contains("private.test"))
    }
}
