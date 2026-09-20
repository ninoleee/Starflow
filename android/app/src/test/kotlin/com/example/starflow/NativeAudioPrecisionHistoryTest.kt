package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeAudioPrecisionHistoryTest {
    private fun source(
        id: String? = "audio-1",
        mime: String = MimeTypes.AUDIO_AAC,
        pcmEncoding: Int = Format.NO_VALUE,
    ): Format = Format.Builder()
        .setId(id)
        .setSampleMimeType(mime)
        .setPcmEncoding(pcmEncoding)
        .build()

    @Test fun ordinaryAacAndHighPrecisionSourcesDoNotCreateHistoryImplicitly() {
        val history = NativeAudioPrecisionHistory()
        repeat(3) {
            assertFalse(history.shouldRestore(source()))
            assertFalse(history.shouldRestore(source(mime = MimeTypes.AUDIO_RAW,
                pcmEncoding = C.ENCODING_PCM_24BIT)))
            assertFalse(history.shouldRestore(source(mime = MimeTypes.AUDIO_RAW,
                pcmEncoding = C.ENCODING_PCM_FLOAT)))
        }
    }

    @Test fun compressedTrackRestoresAfterMediaCodecFloatToPcm16Rebuild() {
        val history = NativeAudioPrecisionHistory()
        val original = source()
        // The owner observed Float32 before changing speed; the source remains AAC.
        history.recordSpeedDowngrade(original)
        val reopenedSource = original.buildUpon().setAverageBitrate(192_000).build()
        assertTrue(history.shouldRestore(reopenedSource))
        // A decoded sink format, even with the same ID, is not the source identity.
        assertFalse(history.shouldRestore(source(mime = MimeTypes.AUDIO_RAW,
            pcmEncoding = C.ENCODING_PCM_16BIT)))
    }

    @Test fun explicitHistorySupportsOtherCompressedCodecsWithoutDecoderAssumptions() {
        for (mime in listOf(MimeTypes.AUDIO_FLAC, MimeTypes.AUDIO_DTS, MimeTypes.AUDIO_E_AC3)) {
            val history = NativeAudioPrecisionHistory()
            val track = source(mime = mime)
            history.recordSpeedDowngrade(track)
            assertTrue(history.shouldRestore(track.buildUpon().build()))
        }
    }

    @Test fun sourcePcm24AndFloatSurviveReconstructionOfTheSameTrack() {
        for (encoding in listOf(C.ENCODING_PCM_24BIT, C.ENCODING_PCM_FLOAT)) {
            val history = NativeAudioPrecisionHistory()
            val track = source(mime = MimeTypes.AUDIO_RAW, pcmEncoding = encoding)
            history.recordSpeedDowngrade(track)
            assertTrue(history.shouldRestore(track.buildUpon().build()))
        }
    }

    @Test fun switchingToDifferentIdDoesNotRestoreEvenWithIdenticalAudioMetadata() {
        val history = NativeAudioPrecisionHistory()
        val original = source()
        history.recordSpeedDowngrade(original)
        assertFalse(history.shouldRestore(original.buildUpon().setId("audio-2").build()))
        assertTrue(history.shouldRestore(original.buildUpon().build()))
    }

    @Test fun sameIdWithDifferentSourceMimeDoesNotMatch() {
        val history = NativeAudioPrecisionHistory()
        history.recordSpeedDowngrade(source())
        assertFalse(history.shouldRestore(source(mime = MimeTypes.AUDIO_FLAC)))
    }

    @Test fun anonymousTracksRequireTheSameSourceInstance() {
        for (id in listOf(null, "", " ")) {
            val history = NativeAudioPrecisionHistory()
            val anonymous = source(id = id)
            history.recordSpeedDowngrade(anonymous)
            assertTrue(history.shouldRestore(anonymous))
            assertFalse(history.shouldRestore(anonymous.buildUpon().build()))
            assertFalse(history.shouldRestore(source()))
        }
    }

    @Test fun missingSourceCannotCreateAnUnscopedRestoreLoop() {
        val history = NativeAudioPrecisionHistory()
        history.recordSpeedDowngrade(null)
        repeat(3) {
            assertFalse(history.shouldRestore(null))
            assertFalse(history.shouldRestore(source()))
        }
    }

    @Test fun temporarilyMissingSourceDoesNotConsumeKnownHistory() {
        val history = NativeAudioPrecisionHistory()
        history.recordSpeedDowngrade(source())
        assertFalse(history.shouldRestore(null))
        assertTrue(history.shouldRestore(source()))
    }

    @Test fun unavailableSourceOnANewDowngradeDiscardsTheOlderTrackRecord() {
        val history = NativeAudioPrecisionHistory()
        history.recordSpeedDowngrade(source())
        history.recordSpeedDowngrade(null)
        assertFalse(history.shouldRestore(source()))
    }

    @Test fun anotherObservedDowngradeReplacesThePreviousTrack() {
        val history = NativeAudioPrecisionHistory()
        history.recordSpeedDowngrade(source())
        history.recordSpeedDowngrade(source(id = "audio-2"))
        assertFalse(history.shouldRestore(source()))
        assertTrue(history.shouldRestore(source(id = "audio-2")))
    }

    @Test fun restoreAttemptConsumesHistoryEvenWhenRebuiltOutputRemainsPcm16() {
        val history = NativeAudioPrecisionHistory()
        history.recordSpeedDowngrade(source())
        assertTrue(history.shouldRestore(source()))
        history.clear()
        repeat(3) { assertFalse(history.shouldRestore(source())) }
        // A later, independently observed high-precision downgrade can be restored.
        history.recordSpeedDowngrade(source())
        assertTrue(history.shouldRestore(source()))
    }

    @Test fun successfulRestorationAndFaultFallbackBothClearHistory() {
        val history = NativeAudioPrecisionHistory()
        val track = source()
        history.recordSpeedDowngrade(track)
        history.clear()
        assertFalse(history.shouldRestore(track))
        history.recordSpeedDowngrade(track)
        history.clear()
        history.clear()
        assertFalse(history.shouldRestore(track))
    }

    @Test fun mediaResetPreventsReusedTrackIdsFromInheritingHistory() {
        val history = NativeAudioPrecisionHistory()
        history.recordSpeedDowngrade(source())
        history.clear()
        assertFalse(history.shouldRestore(source()))
        assertFalse(NativeAudioPrecisionHistory().shouldRestore(source()))
    }

    @Test fun nonAudioAndUnknownMimeAreNotEligible() {
        val history = NativeAudioPrecisionHistory()
        for (invalid in listOf(source(mime = MimeTypes.VIDEO_H264),
            Format.Builder().setId("audio-1").build())) {
            history.recordSpeedDowngrade(source())
            assertFalse(history.shouldRestore(invalid))
            history.recordSpeedDowngrade(invalid)
            assertFalse(history.shouldRestore(invalid))
            assertFalse(history.shouldRestore(source()))
        }
    }
}
