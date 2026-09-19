package com.example.starflow

import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.TrackGroup
import androidx.media3.common.TrackSelectionOverride
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class NativePlaybackAudioTracksTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()
    private fun track(id: String, language: String, supported: Boolean = true): NativeAudioTrack {
        val format = Format.Builder().setId(id).setLanguage(language)
            .setSampleMimeType(MimeTypes.AUDIO_AAC).setChannelCount(2).build()
        return NativeAudioTrack(format, TrackSelectionOverride(TrackGroup(format), 0), false, supported)
    }

    @Test fun restoresByIdentityAndLanguageAliasWithoutOldTrackGroup() {
        val old = track("2", "eng")
        val fresh = track("2", "en")
        assertSame(fresh, NativePlaybackAudioTracks.match(listOf(track("1", "zh"), fresh), old.format))
        assertNotSame(old.override.mediaTrackGroup, fresh.override.mediaTrackGroup)
    }

    @Test fun ambiguousOrUnsupportedTrackIsNotRestored() {
        val previous = track("old", "en")
        assertNull(NativePlaybackAudioTracks.match(listOf(track("1", "en"), track("2", "en")), previous.format))
        assertNull(NativePlaybackAudioTracks.match(listOf(track("old", "en", false)), previous.format))
    }

    @Test fun serverOrdinalIncludesUnsupportedTracksAndRequiresSameCount() {
        val target = JSONObject("""{"preferredAudioStreamId":"b","audioStreams":[{"id":"a","index":0},{"id":"b","index":1}]}""")
        val second = track("2", "en")
        assertSame(second, NativePlaybackAudioTracks.serverDefault(listOf(track("1", "zh", false), second), target))
        assertNull(NativePlaybackAudioTracks.serverDefault(listOf(second), target))
        target.put("preferredAudioStreamId", "a")
        assertNull(NativePlaybackAudioTracks.serverDefault(listOf(track("1", "zh", false), second), target))
    }

    @Test fun serverLanguageMatchesEvenWhenOrderDiffers() {
        val target = JSONObject("""{"preferredAudioStreamId":"b","audioStreams":[{"id":"a","index":0},{"id":"b","index":1,"language":"eng","channels":2}]}""")
        val english = track("1", "en")
        assertSame(english, NativePlaybackAudioTracks.serverDefault(listOf(english, track("2", "zh")), target))
        target.put("preferredAudioStreamId", "")
        assertNull(NativePlaybackAudioTracks.serverDefault(listOf(english), target))
    }
}
