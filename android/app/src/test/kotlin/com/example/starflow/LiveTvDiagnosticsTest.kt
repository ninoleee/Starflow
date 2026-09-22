package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.Player
import androidx.media3.common.TrackGroup
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.audio.AudioSink
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class LiveTvDiagnosticsTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()

    @Test fun buffersAndTerminalSnapshotsDistinguishSourceEndFromUiFrames() {
        var now = 0L
        var active = true
        val records = mutableListOf<Pair<String, Map<String, Any?>>>()
        val diagnostics = LiveTvDiagnostics(7, { active }, { now }) { message, fields -> records.add(message to fields) }
        val player = mock(Player::class.java)
        `when`(player.duration).thenReturn(C.TIME_UNSET)
        diagnostics.state(player, Player.STATE_BUFFERING)
        now = 1000
        diagnostics.state(player, Player.STATE_BUFFERING)
        now = 2000
        diagnostics.state(player, Player.STATE_READY)
        `when`(player.currentPosition).thenReturn(8000)
        `when`(player.duration).thenReturn(8000)
        diagnostics.state(player, Player.STATE_ENDED)
        assertEquals(8000L, records.last().second["durationMs"])
        assertEquals(false, records.last().second["isLive"])
        val event = mock(AnalyticsListener.EventTime::class.java)
        diagnostics.onDroppedVideoFrames(event, 4, 1000)
        diagnostics.onAudioUnderrun(event, 1024, 1000, 1000)
        active = false
        diagnostics.onDroppedVideoFrames(event, 100, 1000)
        diagnostics.state(player, Player.STATE_BUFFERING)
        diagnostics.close()
        diagnostics.close()
        assertEquals(4, records.size)
        val summary = records.last().second
        assertEquals(1, summary["bufferingCount"])
        assertEquals(2000L, summary["bufferingMs"])
        assertEquals(4, summary["droppedVideoFrames"])
        assertEquals(1, summary["audioUnderruns"])
        assertTrue(records.all { it.second["generation"] == 7L })
    }

    @Test fun closingDuringBufferingIncludesTheUnfinishedInterval() {
        var now = 0L
        val records = mutableListOf<Map<String, Any?>>()
        val diagnostics = LiveTvDiagnostics(1, { true }, { now }) { _, fields -> records.add(fields) }
        diagnostics.state(mock(Player::class.java), Player.STATE_BUFFERING)
        now = 3500
        diagnostics.close()
        assertEquals(3500L, records.last()["bufferingMs"])
        diagnostics.hlsFallback()
        assertEquals(2, records.size)
    }

    @Test fun audioReportsSupportSelectionAndOutputWithoutProviderStrings() {
        var active = true
        val records = mutableListOf<Pair<String, Map<String, Any?>>>()
        val diagnostics = LiveTvDiagnostics(1, { active }, { 0L }) { message, fields -> records.add(message to fields) }
        val secret = "https://private.test/password?token=secret"
        val format = Format.Builder().setSampleMimeType("audio/mpeg-L2")
            .setLabel(secret).setId(secret).setLanguage(secret).setSampleRate(48000).setChannelCount(2).build()
        val tracks = Tracks(listOf(Tracks.Group(TrackGroup(format, format), false,
            intArrayOf(C.FORMAT_HANDLED, C.FORMAT_UNSUPPORTED_SUBTYPE), booleanArrayOf(true, false))))
        diagnostics.tracks(tracks)
        diagnostics.tracks(tracks)
        assertEquals(1, records.size)
        assertEquals(2, records.single().second["audioTrackCount"])
        assertEquals(1, records.single().second["supportedAudioTrackCount"])
        assertEquals(1, records.single().second["selectedAudioTrackCount"])
        val event = mock(AnalyticsListener.EventTime::class.java)
        diagnostics.onAudioInputFormatChanged(event, format, null)
        assertEquals("mp2", records.last().second["audioCodec"])
        diagnostics.onAudioInputFormatChanged(event, format.buildUpon().setSampleMimeType(secret).build(), null)
        diagnostics.onAudioDecoderInitialized(event, secret, 0, 10)
        diagnostics.onAudioSinkError(event, IllegalStateException(secret))
        diagnostics.onAudioCodecError(event, IllegalStateException(secret))
        diagnostics.onAudioTrackInitialized(event, AudioSink.AudioTrackConfig(C.ENCODING_PCM_16BIT, 48000, 12, false, false, 4096))
        assertEquals(C.ENCODING_PCM_16BIT, records.last().second["encoding"])
        val before = records.size
        active = false
        diagnostics.tracks(Tracks.EMPTY)
        diagnostics.onAudioSinkError(event, IllegalStateException(secret))
        assertEquals(before, records.size)
        assertFalse(records.toString().contains("private"))
        assertFalse(records.toString().contains("secret"))
    }
}
