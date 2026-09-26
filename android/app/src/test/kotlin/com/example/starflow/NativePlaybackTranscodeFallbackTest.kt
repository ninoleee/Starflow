package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.TrackGroup
import androidx.media3.common.Tracks
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackTranscodeFallbackTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()

    @Test
    fun unsupported4kTrackDoesNotRewriteOrRebuildRelayPlayback() {
        val host = mock(NativePlaybackRecoveryController.Host::class.java, RETURNS_DEEP_STUBS)
        val url = "http://127.0.0.1:12345/playback-relay/session/media"
        `when`(host.activity.intent.getStringExtra(NativePlaybackActivity.EXTRA_URL)).thenReturn(url)
        `when`(host.activity.intent.getStringExtra(NativePlaybackActivity.EXTRA_PLAYBACK_TARGET_JSON))
            .thenReturn("""{"sourceKind":"nas"}""")
        val format = Format.Builder().setSampleMimeType(MimeTypes.VIDEO_H264)
            .setCodecs("avc1.640034").setWidth(3840).setHeight(2160).build()
        val tracks = Tracks(listOf(Tracks.Group(TrackGroup(format), false,
            intArrayOf(C.FORMAT_EXCEEDS_CAPABILITIES), booleanArrayOf(true))))
        mockStatic(NativePlaybackFormatting::class.java).use {
            val recovery = NativePlaybackRecoveryController(host)
            recovery.fallbackToTranscodedVideoIfNeeded(tracks)
            recovery.fallbackToTranscodedVideoIfNeeded(tracks)
        }
        verify(host.session, never()).rebuildPlayer()
        verify(host.activity.intent, never()).putExtra(eq(NativePlaybackActivity.EXTRA_URL), anyString())
        verify(host.diagnostics.playbackPerformanceTracker, never()).onRecovery()
        verify(host, never()).showToast(anyString())
    }

    @Test
    fun relayCannotBeRewrittenEvenForMediaServerSources() {
        for (source in listOf("nas", "quark", "emby", "fntv", "")) {
            val url = "http://127.0.0.1:12345/playback-relay/session/media"
            assertFalse(NativePlaybackSource.supportsVideoTranscodeFallback(url, source))
            assertNull(NativePlaybackSource.buildTranscodedVideoFallbackUrl(url, source))
        }
    }

    @Test
    fun ordinaryAndSignedMediaUrlsAreNotTranscodeEndpoints() {
        for (url in listOf("https://cdn.example/movie.mp4?signature=example",
            "https://nas.example/smartstrm/123", "https://nas.example/movie.m3u8",
            "file:///movie.mp4", "invalid url", "ftp://nas.example/Videos/123/stream.mp4")) {
            assertFalse(NativePlaybackSource.supportsVideoTranscodeFallback(url, "emby"))
            assertNull(NativePlaybackSource.buildTranscodedVideoFallbackUrl(url, "emby"))
        }
        assertFalse(NativePlaybackSource.supportsVideoTranscodeFallback(
            "https://nas.example/Videos/123/stream.mp4", "nas"))
    }

    @Test
    fun directEmbyEndpointsRetainFallbackEligibility() {
        for (url in listOf("https://server.example/emby/Videos/123/stream.mp4?static=true",
            "http://192.168.1.2:8096/Videos/123/stream.mkv?api_key=example",
            "https://server.example/videos/123/stream")) {
            assertTrue(NativePlaybackSource.supportsVideoTranscodeFallback(url, "emby"))
        }
    }
}
