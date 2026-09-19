package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.TrackOutput
import androidx.media3.extractor.ts.TsPayloadReader
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import androidx.media3.common.util.TimestampAdjuster
import org.junit.Test
import org.mockito.ArgumentCaptor
import org.mockito.Mockito.anyInt
import org.mockito.Mockito.eq
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`

class NativePlaybackExtractorsFactoryTest {
    @Test
    fun pgsContinuityResetUsesOnlyItsRegisteredFormatId() {
        val resets = mutableListOf<Set<String?>>()
        val output = mock(ExtractorOutput::class.java)
        `when`(output.track(anyInt(), anyInt())).thenReturn(mock(TrackOutput::class.java))
        val info = TsPayloadReader.EsInfo(0x90, null, 0, null, byteArrayOf())
        val reader = NativeTsPayloadReaderFactory(resetSubtitleParsers = { resets += it.toSet() })
            .createPayloadReader(0x90, info)!!
        reader.init(TimestampAdjuster(0), output, TsPayloadReader.TrackIdGenerator(7, 1))
        reader.seek()
        org.junit.Assert.assertEquals(listOf(setOf("7")), resets)
    }

    @Test
    fun ambiguousStreamRequiresExactCodecOrHdmvRegistration() {
        for (codec in listOf("", "pcm", "lpcm", "h264", "pcm_s16be", "pcm_bluray_extra")) {
            assertFalse(NativeTsPayloadReaderFactory(codec).shouldUseBluRayPcm(0x80, byteArrayOf()))
        }
        for (codec in listOf("pcm_bluray", " PCM_BLURAY ")) {
            assertTrue(NativeTsPayloadReaderFactory(codec).shouldUseBluRayPcm(0x80, byteArrayOf()))
            assertFalse(NativeTsPayloadReaderFactory(codec).shouldUseBluRayPcm(0x1B, byteArrayOf()))
        }
        val descriptors = byteArrayOf(0x0A, 1, 0, 5, 6, 0x48, 0x44, 0x4D, 0x56, 0, 0)
        assertTrue(NativeTsPayloadReaderFactory().shouldUseBluRayPcm(0x80, descriptors))
        assertFalse(NativeTsPayloadReaderFactory().shouldUseBluRayPcm(0x02, descriptors))
    }

    @Test
    fun malformedOrConflictingDescriptorsDoNotOverrideDefaultReader() {
        val invalidDescriptors = listOf(
            byteArrayOf(5),
            byteArrayOf(5, 4, 0x48, 0x44, 0x4D),
            byteArrayOf(5, 3, 0x48, 0x44, 0x4D),
            byteArrayOf(5, 4, 0x41, 0x43, 0x2D, 0x33),
            byteArrayOf(5, 4, 0x48, 0x44, 0x4D, 0x56, 0x0A),
            byteArrayOf(5, 4, 0x48, 0x44, 0x4D, 0x56, 5, 4, 0, 0, 0, 0),
        )
        for (codec in listOf("", "pcm_bluray")) {
            for (descriptors in invalidDescriptors) {
                assertFalse(NativeTsPayloadReaderFactory(codec).shouldUseBluRayPcm(0x80, descriptors))
            }
        }
        assertFalse(NativeTsPayloadReaderFactory().shouldUseBluRayPcm(
            0x80, byteArrayOf(0x0A, 4, 0x48, 0x44, 0x4D, 0x56),
        ))
    }

    @Test
    fun factoryRegistersAudioOnlyWithEvidenceOtherwiseKeepsVideoReader() {
        for ((codec, descriptors, trackType) in listOf(
            Triple("", byteArrayOf(), C.TRACK_TYPE_VIDEO),
            Triple("pcm_bluray", byteArrayOf(), C.TRACK_TYPE_AUDIO),
            Triple("", byteArrayOf(5, 4, 0x48, 0x44, 0x4D, 0x56), C.TRACK_TYPE_AUDIO),
        )) {
            val output = mock(ExtractorOutput::class.java)
            `when`(output.track(anyInt(), anyInt())).thenReturn(mock(TrackOutput::class.java))
            val info = TsPayloadReader.EsInfo(0x80, null, 0, null, descriptors)
            val reader = NativeTsPayloadReaderFactory(codec).createPayloadReader(0x80, info)!!
            reader.init(TimestampAdjuster(0), output, TsPayloadReader.TrackIdGenerator(0, 1))
            verify(output).track(anyInt(), eq(trackType))
        }
    }

    @Test
    fun factoryRegistersBluRayPgsAsTextTrack() {
        val output = mock(ExtractorOutput::class.java)
        `when`(output.track(anyInt(), anyInt())).thenReturn(mock(TrackOutput::class.java))
        val info = TsPayloadReader.EsInfo(0x90, null, 0, null, byteArrayOf())
        val reader = NativeTsPayloadReaderFactory().createPayloadReader(0x90, info)!!
        reader.init(TimestampAdjuster(0), output, TsPayloadReader.TrackIdGenerator(0, 1))
        verify(output).track(anyInt(), eq(C.TRACK_TYPE_TEXT))
    }

    @Test
    fun convertsStereoBluRayPcmToLittleEndianPcm16() {
        val output = mock(ExtractorOutput::class.java)
        val track = mock(TrackOutput::class.java)
        `when`(output.track(anyInt(), eq(C.TRACK_TYPE_AUDIO))).thenReturn(track)
        val reader = PcmBluRayReader(language = null, roleFlags = 0)
        reader.createTracks(output, TsPayloadReader.TrackIdGenerator(0, 0))
        reader.packetStarted(123_456L, 0)
        reader.consume(
            ParsableByteArray(
                byteArrayOf(
                    0,
                    4,
                    0x31,
                    0x40,
                    0x12,
                    0x34,
                    0xAB.toByte(),
                    0xCD.toByte(),
                ),
            ),
        )

        val captor = ArgumentCaptor.forClass(ParsableByteArray::class.java)
        verify(track).sampleData(captor.capture(), eq(4), eq(TrackOutput.SAMPLE_DATA_PART_MAIN))
        val converted = ByteArray(4)
        captor.value.readBytes(converted, 0, converted.size)
        assertArrayEquals(
            byteArrayOf(0x34, 0x12, 0xCD.toByte(), 0xAB.toByte()),
            converted,
        )
    }
}
