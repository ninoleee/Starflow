package com.example.starflow

import android.graphics.Bitmap
import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.TrackOutput
import androidx.media3.extractor.ts.TsPayloadReader
import androidx.media3.extractor.text.CuesWithTiming
import androidx.media3.extractor.text.SubtitleParser
import androidx.media3.extractor.text.pgs.PgsParser
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mockito.Mockito.anyInt
import org.mockito.Mockito.eq
import org.mockito.Mockito.mock
import org.mockito.Mockito.mockStatic
import org.mockito.Mockito.any
import org.mockito.Mockito.`when`

class PgsReaderTest {
    @Test
    fun registersTextTrackAndCombinesPesSegmentsIntoOneDisplaySet() {
        val output = mock(ExtractorOutput::class.java)
        val track = RecordingTrackOutput()
        `when`(output.track(anyInt(), eq(C.TRACK_TYPE_TEXT))).thenReturn(track)

        val reader = PgsReader(language = null, roleFlags = 0)
        reader.createTracks(output, TsPayloadReader.TrackIdGenerator(0, 1))
        reader.packetStarted(12_345L, 0)
        reader.consume(ParsableByteArray(segment(type = 0x14, payload = byteArrayOf(0x01))))
        reader.packetFinished(false)
        reader.packetStarted(12_999L, 0)
        reader.consume(
            ParsableByteArray(
                segment(type = 0x15, payload = byteArrayOf(0x02, 0x03)) +
                    segment(type = 0x80),
            ),
        )
        reader.packetFinished(false)

        assertEquals(MimeTypes.APPLICATION_PGS, track.formats.single().sampleMimeType)
        assertEquals("S_HDMV/PGS", track.formats.single().codecs)
        assertEquals(
            C.ROLE_FLAG_SUBTITLE,
            track.formats.single().roleFlags and C.ROLE_FLAG_SUBTITLE,
        )
        assertArrayEquals(
            segment(type = 0x14, payload = byteArrayOf(0x01)) +
                segment(type = 0x15, payload = byteArrayOf(0x02, 0x03)) +
                segment(type = 0x80),
            track.bytes.toByteArray(),
        )
        assertEquals(listOf(12_345L), track.timestamps)
    }

    @Test
    fun emitsMultipleDisplaySetsAndHandlesSegmentSplits() {
        val output = mock(ExtractorOutput::class.java)
        val track = RecordingTrackOutput()
        `when`(output.track(anyInt(), eq(C.TRACK_TYPE_TEXT))).thenReturn(track)

        val reader = PgsReader(language = null, roleFlags = 0)
        reader.createTracks(output, TsPayloadReader.TrackIdGenerator(0, 1))
        reader.packetStarted(100L, 0)
        val first = segment(type = 0x15, payload = byteArrayOf(0x01, 0x02)) +
            segment(type = 0x80)
        reader.consume(ParsableByteArray(first.copyOfRange(0, 2)))
        reader.consume(ParsableByteArray(first.copyOfRange(2, first.size)))
        reader.packetStarted(200L, 0)
        val second = segment(type = 0x15, payload = byteArrayOf(0x03)) +
            segment(type = 0x80)
        reader.consume(ParsableByteArray(second))
        reader.packetFinished(false)

        assertArrayEquals(first + second, track.bytes.toByteArray())
        assertEquals(listOf(100L, 200L), track.timestamps)
    }

    @Test
    fun seekDiscardsPartialDisplaySet() {
        val output = mock(ExtractorOutput::class.java)
        val track = RecordingTrackOutput()
        `when`(output.track(anyInt(), eq(C.TRACK_TYPE_TEXT))).thenReturn(track)

        val reader = PgsReader(language = null, roleFlags = 0)
        reader.createTracks(output, TsPayloadReader.TrackIdGenerator(0, 1))
        reader.packetStarted(100L, 0)
        val partial = segment(type = 0x15, payload = byteArrayOf(0x01, 0x02))
        reader.consume(ParsableByteArray(partial.copyOfRange(0, 3)))
        reader.seek()
        reader.packetStarted(200L, 0)
        val complete = segment(type = 0x80)
        reader.consume(ParsableByteArray(complete))

        assertArrayEquals(complete, track.bytes.toByteArray())
        assertEquals(listOf(200L), track.timestamps)
    }

    @Test
    fun compositionPtsIsNotReplacedByEarlierObjectOrEndPts() {
        val output = mock(ExtractorOutput::class.java)
        val track = RecordingTrackOutput()
        `when`(output.track(anyInt(), eq(C.TRACK_TYPE_TEXT))).thenReturn(track)
        val reader = PgsReader(language = null, roleFlags = 0)
        reader.createTracks(output, TsPayloadReader.TrackIdGenerator(0, 1))
        val composition = segment(0x16, ByteArray(19))
        reader.packetStarted(992_558_833L, 0)
        reader.consume(ParsableByteArray(composition.copyOfRange(0, 2)))
        reader.packetStarted(992_492_100L, 0)
        reader.consume(ParsableByteArray(composition.copyOfRange(2, composition.size)))
        reader.consume(ParsableByteArray(segment(0x14, ByteArray(7))))
        reader.packetStarted(992_495_967L, 0)
        reader.consume(ParsableByteArray(segment(0x15, ByteArray(12))))
        reader.packetStarted(992_556_000L, 0)
        reader.consume(ParsableByteArray(segment(0x80)))
        assertEquals(listOf(992_558_833L), track.timestamps)
    }

    @Test
    fun newCompositionDropsDisplaySetWhoseEndWasLost() {
        val output = mock(ExtractorOutput::class.java)
        val track = RecordingTrackOutput()
        `when`(output.track(anyInt(), eq(C.TRACK_TYPE_TEXT))).thenReturn(track)
        val reader = PgsReader(language = null, roleFlags = 0)
        reader.createTracks(output, TsPayloadReader.TrackIdGenerator(0, 1))
        reader.packetStarted(100L, 0)
        reader.consume(ParsableByteArray(segment(0x16) + segment(0x15, ByteArray(12))))
        reader.packetStarted(200L, 0)
        val clear = segment(0x16, ByteArray(11)) + segment(0x80)
        reader.consume(ParsableByteArray(clear))
        assertArrayEquals(clear, track.bytes.toByteArray())
        assertEquals(listOf(200L), track.timestamps)
    }

    @Test
    fun missingEndCannotGrowBufferWithoutBoundAndNextCompositionRecovers() {
        val output = mock(ExtractorOutput::class.java)
        val track = RecordingTrackOutput()
        `when`(output.track(anyInt(), eq(C.TRACK_TYPE_TEXT))).thenReturn(track)
        val reader = PgsReader(language = null, roleFlags = 0)
        reader.createTracks(output, TsPayloadReader.TrackIdGenerator(0, 1))
        reader.packetStarted(100L, 0)
        repeat(70) { reader.consume(ParsableByteArray(segment(0x15, ByteArray(65535)))) }
        reader.consume(ParsableByteArray(segment(0x80)))
        assertEquals(0, track.bytes.size())
        reader.packetStarted(200L, 0)
        val clear = segment(0x16, ByteArray(11)) + segment(0x80)
        reader.consume(ParsableByteArray(clear))
        assertArrayEquals(clear, track.bytes.toByteArray())
        assertEquals(listOf(200L), track.timestamps)
    }

    @Test
    fun completeDisplaySetProducesBitmapCueAndClearSetRemovesIt() {
        val output = mock(ExtractorOutput::class.java)
        val track = RecordingTrackOutput()
        `when`(output.track(anyInt(), eq(C.TRACK_TYPE_TEXT))).thenReturn(track)
        val reader = PgsReader(language = null, roleFlags = 0)
        reader.createTracks(output, TsPayloadReader.TrackIdGenerator(0, 1))
        // A 1x1 opaque white object on a 1920x1080 plane, at (100, 200).
        val composition = byteArrayOf(
            7, 0x80.toByte(), 4, 0x38, 0x10, 0, 1, 0x80.toByte(), 0, 0, 1,
            0, 0, 0, 0, 0, 100, 0, 200.toByte(),
        )
        val palette = byteArrayOf(0, 0, 1, 235.toByte(), 128.toByte(), 128.toByte(), 255.toByte())
        val bitmapObject = byteArrayOf(0, 0, 0, 0xc0.toByte(), 0, 0, 5, 0, 1, 0, 1, 1)
        for ((time, bytes) in listOf(
            1_000_000L to segment(0x16, composition),
            950_000L to segment(0x14, palette),
            960_000L to segment(0x15, bitmapObject),
            999_000L to segment(0x80),
        )) {
            reader.packetStarted(time, 0)
            reader.consume(ParsableByteArray(bytes))
            reader.packetFinished(false)
        }
        val bitmap = mock(Bitmap::class.java)
        mockStatic(Bitmap::class.java).use { staticBitmap ->
            staticBitmap.`when`<Bitmap> {
                Bitmap.createBitmap(any(IntArray::class.java), eq(1), eq(1), any())
            }.thenReturn(bitmap)
            val parser = PgsParser()
            val cues = mutableListOf<CuesWithTiming>()
            val sample = track.bytes.toByteArray()
            parser.parse(sample, 0, sample.size, SubtitleParser.OutputOptions.allCues()) { cues.add(it) }
            assertEquals(bitmap, cues.single().cues.single().bitmap)
            assertEquals(listOf(1_000_000L), track.timestamps)
            val clear = segment(0x16, composition.copyOf(11).also { it[10] = 0 }) + segment(0x80)
            cues.clear()
            parser.parse(clear, 0, clear.size, SubtitleParser.OutputOptions.allCues()) { cues.add(it) }
            assertEquals(0, cues.single().cues.size)
        }
    }

    private class RecordingTrackOutput : TrackOutput {
        val bytes = ByteArrayOutputStream()
        val timestamps = mutableListOf<Long>()
        val formats = mutableListOf<Format>()
        private var committedBytes = 0

        override fun format(format: Format) {
            formats.add(format)
        }

        override fun sampleData(data: ParsableByteArray, length: Int, sampleDataPart: Int) {
            assertEquals(TrackOutput.SAMPLE_DATA_PART_MAIN, sampleDataPart)
            val chunk = ByteArray(length)
            data.readBytes(chunk, 0, length)
            bytes.write(chunk)
        }

        override fun sampleData(
            input: DataReader,
            length: Int,
            allowEndOfInput: Boolean,
            sampleDataPart: Int,
        ): Int = error("Unexpected streaming input")

        override fun sampleMetadata(
            timeUs: Long,
            flags: Int,
            size: Int,
            offset: Int,
            cryptoData: TrackOutput.CryptoData?,
        ) {
            assertEquals(C.BUFFER_FLAG_KEY_FRAME, flags)
            assertEquals(0, offset)
            committedBytes += size
            assertEquals(committedBytes, bytes.size())
            timestamps.add(timeUs)
        }
    }

    private fun segment(type: Int, payload: ByteArray = byteArrayOf()): ByteArray =
        byteArrayOf(
            type.toByte(),
            (payload.size shr 8).toByte(),
            payload.size.toByte(),
        ) + payload
}
