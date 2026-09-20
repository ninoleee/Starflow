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

    @Test fun reverseMappingRetainsUnsupportedPositionsAndRejectsMissingRows() {
        val target = JSONObject("""{"audioStreams":[{"id":"a","index":0},{"id":"b","index":1}]}""")
        val first = track("1", "zh", false)
        val second = track("2", "en")
        assertEquals("b", NativePlaybackAudioTracks.serverStream(listOf(first, second), second, target)?.optString("id"))
        assertNull(NativePlaybackAudioTracks.serverStream(listOf(second), second, target))
    }

    @Test fun reverseMappingNormalizesLanguageAndUsesChannels() {
        val target = JSONObject("""{"audioStreams":[{"id":"a","index":0,"language":"zh"},{"id":"b","index":1,"language":"eng","channels":2}]}""")
        val english = track("1", "en")
        assertEquals("b", NativePlaybackAudioTracks.serverStream(listOf(english), english, target)?.optString("id"))
    }

    @Test fun codecDisambiguatesSameLanguageWithoutOrdinalGuess() {
        val target = JSONObject("""{"preferredAudioStreamId":"aac","audioStreams":[{"id":"ac3","index":0,"language":"eng","codec":"ac3"},{"id":"aac","index":1,"language":"eng","codec":"aac"}]}""")
        val aac = track("1", "en")
        assertEquals("aac", NativePlaybackAudioTracks.serverStream(listOf(aac), aac, target)?.optString("id"))
        assertSame(aac, NativePlaybackAudioTracks.serverDefault(listOf(aac), target))
    }

    @Test fun missingAc3CannotMatchOnlyAacByIdenticalMetadata() {
        val target = JSONObject("""{"preferredAudioStreamId":"ac3","audioStreams":[{"id":"ac3","index":0,"language":"eng","channels":2,"codec":"ac3"},{"id":"aac","index":1,"language":"eng","channels":2,"codec":"aac"}]}""")
        val aac = track("1", "en")
        assertNull(NativePlaybackAudioTracks.serverDefault(listOf(aac), target))
        assertEquals("aac", NativePlaybackAudioTracks.serverStream(listOf(aac), aac, target)?.optString("id"))
    }

    @Test fun codecContradictionRejectsMetadataAndOrdinalInBothDirections() {
        for ((mime, codec) in listOf(MimeTypes.AUDIO_AAC to "ac3", MimeTypes.AUDIO_AC3 to "aac")) {
            val format = track("1", "en").format.buildUpon().setSampleMimeType(mime).build()
            val local = NativeAudioTrack(format, TrackSelectionOverride(TrackGroup(format), 0), true, true)
            for (metadata in listOf("", "\"language\":\"eng\",\"channels\":2,")) {
                val target = JSONObject("""{"preferredAudioStreamId":"a","audioStreams":[{${metadata}"id":"a","index":0,"codec":"$codec"}]}""")
                assertNull(NativePlaybackAudioTracks.serverDefault(listOf(local), target))
                assertNull(NativePlaybackAudioTracks.serverStream(listOf(local), local, target))
            }
        }
    }

    @Test fun unknownCodecStillAllowsMetadataOrUncompressedOrdinal() {
        val aac = track("1", "en")
        for (codec in listOf("", "unrecognized-codec")) {
            val target = JSONObject("""{"preferredAudioStreamId":"a","audioStreams":[{"id":"a","codec":"$codec"}]}""")
            assertSame(aac, NativePlaybackAudioTracks.serverDefault(listOf(aac), target))
            assertEquals("a", NativePlaybackAudioTracks.serverStream(listOf(aac), aac, target)?.optString("id"))
        }
    }

    @Test fun genericServerCodecDoesNotContradictKnownCodecExtension() {
        for ((codec, mime) in listOf("eac3" to MimeTypes.AUDIO_E_AC3_JOC, "dts" to MimeTypes.AUDIO_DTS_HD)) {
            val format = Format.Builder().setSampleMimeType(mime).build()
            val track = NativeAudioTrack(format, TrackSelectionOverride(TrackGroup(format), 0), true, true)
            val target = JSONObject("""{"preferredAudioStreamId":"a","audioStreams":[{"id":"a","codec":"$codec"}]}""")
            assertSame(track, NativePlaybackAudioTracks.serverDefault(listOf(track), target))
            assertEquals("a", NativePlaybackAudioTracks.serverStream(listOf(track), track, target)?.optString("id"))
        }
    }
}
