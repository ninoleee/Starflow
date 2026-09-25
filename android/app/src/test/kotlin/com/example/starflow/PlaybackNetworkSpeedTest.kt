package com.example.starflow

import java.io.File
import java.util.Locale
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import androidx.media3.common.Format

class PlaybackNetworkSpeedTest {
    @Test fun activeMediaFormatAndDuration() {
        val video = Format.Builder().setWidth(1920).setHeight(1080)
            .setContainerMimeType("video/mp2t").setSampleMimeType("video/hevc").build()
        val audio = Format.Builder().setSampleMimeType("audio/mp4a-latm").build()
        assertEquals("1920x1080 · HEVC · AAC", NativePlaybackFormatting.formatVideoFormat(video, audio))
        assertEquals(null, NativePlaybackFormatting.formatVideoFormat(null, null))
        assertEquals("2.0 KB/s · 32.0 MB · 18s", NativePlaybackFormatting.formatPlaybackMetrics(2048, 33554432, 18000))
        assertEquals("1m 0s", NativePlaybackFormatting.formatBufferDuration(59999))
        assertEquals("1h 0m", NativePlaybackFormatting.formatBufferDuration(3600000))
        assertEquals("--", NativePlaybackFormatting.formatBufferDuration(-1))
    }
    private val fixture = JSONObject(File("../../test/fixtures/playback_network_speed.json").readText())

    @Test fun formattingMatchesDartRegardlessOfDeviceLocale() {
        val original = Locale.getDefault()
        try {
            Locale.setDefault(Locale.GERMANY)
            val cases = fixture.getJSONArray("formats")
            for (index in 0 until cases.length()) {
                val row = cases.getJSONObject(index)
                val speed = if (row.isNull("bytes")) null else row.getLong("bytes")
                assertEquals(row.getString("label"), NativePlaybackFormatting.formatNetworkSpeed(speed))
                assertEquals(row.getString("label").removeSuffix("/s"), NativePlaybackFormatting.formatCacheBytes(speed))
            }
        } finally {
            Locale.setDefault(original)
        }
    }

    @Test fun smoothingMatchesDartAndResetsOnIdleOrUnknown() {
        val window = PlaybackNetworkSpeedWindow()
        val samples = fixture.getJSONArray("samples")
        val expected = fixture.getJSONArray("smoothed")
        for (index in 0 until samples.length()) {
            val sample = if (samples.isNull(index)) null else samples.getLong(index)
            val result = if (expected.isNull(index)) null else expected.getLong(index)
            assertEquals(result, window.add(sample))
        }
    }
}
