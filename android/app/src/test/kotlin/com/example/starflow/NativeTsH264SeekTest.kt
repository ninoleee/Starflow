package com.example.starflow

import android.util.SparseArray
import androidx.media3.common.C
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.common.util.TimestampAdjuster
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.TrackOutput
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import androidx.media3.extractor.ts.TsPayloadReader
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.*

class NativeTsH264SeekTest {
    @Test
    fun nonIdrISliceWithoutRandomAccessFlagIsSeekableOnlyWithCompatibilityReader() {
        assertFalse(readSampleFlags(DefaultTsPayloadReaderFactory(0), 0x88)
            .any { it and C.BUFFER_FLAG_KEY_FRAME != 0 })
        assertTrue(readSampleFlags(NativeTsPayloadReaderFactory(), 0x88)
            .any { it and C.BUFFER_FLAG_KEY_FRAME != 0 })
    }

    @Test
    fun ordinaryPredictiveSlicesAreNotPromotedToKeyframes() {
        assertFalse(readSampleFlags(NativeTsPayloadReaderFactory(), 0x98)
            .any { it and C.BUFFER_FLAG_KEY_FRAME != 0 })
    }

    private fun readSampleFlags(factory: TsPayloadReader.Factory, sliceHeader: Int): List<Int> {
        // Access-unit detection is off, so SparseArray storage is not read by H264Reader.
        mockConstruction(SparseArray::class.java).use {
            val output = mock(ExtractorOutput::class.java)
            val track = mock(TrackOutput::class.java)
            `when`(output.track(anyInt(), anyInt())).thenReturn(track)
            doAnswer { invocation ->
                invocation.getArgument<ParsableByteArray>(0)
                    .skipBytes(invocation.getArgument<Int>(1))
                null
            }.`when`(track).sampleData(any(ParsableByteArray::class.java), anyInt())
            val flags = mutableListOf<Int>()
            doAnswer { invocation ->
                flags += invocation.getArgument<Int>(1)
                null
            }.`when`(track).sampleMetadata(anyLong(), anyInt(), anyInt(), anyInt(), isNull())
            val reader = factory.createPayloadReader(
                0x1B, TsPayloadReader.EsInfo(0x1B, null, 0, null, byteArrayOf()),
            )!!
            reader.init(TimestampAdjuster(0), output, TsPayloadReader.TrackIdGenerator(0, 1))
            val aud = hex("00000109f0")
            val slice = hex("00000141") + byteArrayOf(sliceHeader.toByte(), 0x80.toByte())
            val parameters = hex(
                "00000167640029ac1b1a501e0113f7808800001f4800075307130000243d5000039387" +
                    "4625c6260000487aa00007270e8c4b87c70c2960" +
                    "00000168fa8dce50948d18b25a55284a468c592d2a50c91a3164b4aa8548d275d525" +
                    "1d2349d27a2374937a49be95daadd53d7a6b54229a4e93d6ea9fa4eeaafd6ebff5f7",
            )
            fun consume(payload: ByteArray) {
                val size = payload.size + 8
                val pes = hex("000001e0") +
                    byteArrayOf((size shr 8).toByte(), size.toByte()) +
                    hex("8080052100010001") + payload
                reader.consume(ParsableByteArray(pes), TsPayloadReader.FLAG_PAYLOAD_UNIT_START_INDICATOR)
            }
            consume(parameters + aud + slice + aud + slice + aud + slice)
            assertTrue("Reader must emit samples, not just register a track", flags.isNotEmpty())
            reader.seek()
            flags.clear()
            consume(aud + slice + aud + slice + aud + slice)
            assertTrue("Reader must emit samples after a seek", flags.isNotEmpty())
            return flags
        }
    }

    private fun hex(value: String): ByteArray =
        value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
}
