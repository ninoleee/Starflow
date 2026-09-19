package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.common.Format
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.TrackOutput
import androidx.media3.extractor.ts.TsPayloadReader
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mockito.Mockito.*

class PcmBluRayReaderTest {
    @Test
    fun consumesLogged166BytePayloadWithoutOverflowOrLosingRemainder() {
        for (offset in listOf(3052, 6602)) {
            val fixture = Fixture()
            val payload = ByteArray(168) { it.toByte() }
            fixture.reader.packetStarted(123_456L, 0)
            fixture.consume(header(payload.size))
            val transportBuffer = ByteArray(9400)
            payload.copyInto(transportBuffer, offset, 0, 166)
            val data = ParsableByteArray(transportBuffer, offset + 166)
            data.position = offset
            fixture.reader.consume(data)
            assertEquals(0, data.bytesLeft())
            assertEquals(164, fixture.track.bytes.size())
            fixture.consume(payload.copyOfRange(166, 168))
            assertArrayEquals(toPcm16(payload, 2), fixture.track.bytes.toByteArray())
            assertEquals(listOf(123_456L, 124_310L), fixture.track.timestamps)
        }
    }

    @Test
    fun everyHeaderAndSampleSplitPreserves16And24BitAudio() {
        for (bytesPerSample in listOf(2, 3)) {
            val payload = ByteArray(bytesPerSample * 2 * 47) { (it * 31).toByte() }
            val packet = header(payload.size, depthCode = if (bytesPerSample == 2) 1 else 3) + payload
            for (split in 1 until packet.size) {
                val fixture = Fixture()
                fixture.reader.packetStarted(1_000L, 0)
                fixture.consume(packet.copyOfRange(0, split))
                fixture.consume(packet.copyOfRange(split, packet.size))
                assertArrayEquals(toPcm16(payload, bytesPerSample), fixture.track.bytes.toByteArray())
            }
        }
    }

    @Test
    fun handlesOneByteChunksIncludingSplit20BitSamples() {
        val fixture = Fixture()
        val payload = byteArrayOf(0x12, 0x34, 0x50, 0xAB.toByte(), 0xCD.toByte(), 0xE0.toByte())
        fixture.reader.packetStarted(0, 0)
        for (byte in header(payload.size, depthCode = 2) + payload) {
            fixture.consume(byteArrayOf(byte))
        }
        assertArrayEquals(toPcm16(payload, 3), fixture.track.bytes.toByteArray())
    }

    @Test
    fun stripsHeaderFromEveryPesPacket() {
        val fixture = Fixture()
        val payload = byteArrayOf(0x12, 0x34, 0x56, 0x78)
        for (timeUs in listOf(10_000L, 20_000L)) {
            fixture.reader.packetStarted(timeUs, 0)
            fixture.consume(header(payload.size) + payload)
            fixture.reader.packetFinished(false)
        }
        assertArrayEquals(toPcm16(payload + payload, 2), fixture.track.bytes.toByteArray())
        assertEquals(listOf(10_000L, 20_000L), fixture.track.timestamps)
    }

    @Test
    fun advancesTimestampsWithoutPerChunkRoundingDriftAndContinuesMissingPts() {
        for ((rateCode, rate) in listOf(1 to 48_000, 4 to 96_000, 5 to 192_000)) {
            val fixture = Fixture()
            fixture.reader.packetStarted(100_000L, 0)
            fixture.consume(header(4 * 48, rateCode = rateCode))
            repeat(48) { fixture.consume(ByteArray(4)) }
            fixture.reader.packetFinished(false)
            fixture.reader.packetStarted(C.TIME_UNSET, 0)
            fixture.consume(header(4, rateCode = rateCode) + ByteArray(4))
            assertEquals((0L..48L).map { 100_000L + it * 1_000_000L / rate }, fixture.track.timestamps)
        }
    }

    @Test
    fun seekDiscardsPartialAudioAndReadsFreshHeader() {
        val fixture = Fixture()
        fixture.reader.packetStarted(0, 0)
        fixture.consume(header(4) + byteArrayOf(0x7F, 0x7F))
        fixture.reader.seek()
        fixture.reader.packetStarted(4_000_000L, 0)
        val payload = byteArrayOf(0x12, 0x34, 0x56, 0x78)
        fixture.consume(header(4) + payload)
        assertArrayEquals(toPcm16(payload, 2), fixture.track.bytes.toByteArray())
        assertEquals(listOf(4_000_000L), fixture.track.timestamps)
    }

    @Test
    fun seekDiscardsPartialHeader() {
        val fixture = Fixture()
        fixture.reader.packetStarted(0, 0)
        fixture.consume(byteArrayOf(0x7F, 0x7F))
        fixture.reader.seek()
        fixture.reader.packetStarted(1_000_000L, 0)
        fixture.consume(header(4) + ByteArray(4))
        assertEquals(4, fixture.track.bytes.size())
        assertEquals(listOf(1_000_000L), fixture.track.timestamps)
    }

    @Test
    fun malformedPacketDoesNotPoisonNextPacketOrLeakTrailingSample() {
        val fixture = Fixture()
        fixture.reader.packetStarted(0, 0)
        fixture.consume(header(2) + byteArrayOf(0x7F, 0x7F))
        fixture.reader.packetFinished(false)
        fixture.reader.packetStarted(5_000L, 0)
        fixture.consume(byteArrayOf(0, 4, 0, 0) + ByteArray(4))
        fixture.consume(ByteArray(8))
        fixture.reader.packetFinished(false)
        fixture.reader.packetStarted(10_000L, 0)
        fixture.consume(header(4) + ByteArray(4))
        assertArrayEquals(ByteArray(4), fixture.track.bytes.toByteArray())
        assertEquals(listOf(10_000L), fixture.track.timestamps)
    }

    @Test
    fun createsTrackBeforeConsumingPayloadAndUpdatesFormatOnNewHeader() {
        val fixture = Fixture()
        verify(fixture.output).track(anyInt(), eq(C.TRACK_TYPE_AUDIO))
        fixture.reader.packetStarted(0, 0)
        fixture.consume(header(4) + ByteArray(4))
        fixture.reader.packetFinished(false)
        fixture.reader.packetStarted(1_000_000L, 0)
        fixture.consume(header(6, depthCode = 3, rateCode = 4) + ByteArray(6))
        verify(fixture.output, times(1)).track(anyInt(), eq(C.TRACK_TYPE_AUDIO))
        assertEquals(listOf(48_000, 96_000), fixture.track.formats.map { it.sampleRate })
        assertEquals(8, fixture.track.bytes.size())
    }

    private class Fixture {
        val output = mock(ExtractorOutput::class.java)
        val track = RecordingTrackOutput()
        val reader = PcmBluRayReader(language = null, roleFlags = 0)

        init {
            `when`(output.track(anyInt(), eq(C.TRACK_TYPE_AUDIO))).thenReturn(track)
            reader.createTracks(output, TsPayloadReader.TrackIdGenerator(0, 1))
        }

        fun consume(bytes: ByteArray) {
            val data = ParsableByteArray(bytes)
            reader.consume(data)
            assertEquals(0, data.bytesLeft())
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
            assertEquals(0, offset)
            committedBytes += size
            assertEquals(committedBytes, bytes.size())
            timestamps.add(timeUs)
        }
    }

    private fun header(payloadBytes: Int, depthCode: Int = 1, rateCode: Int = 1) =
        byteArrayOf(
            (payloadBytes shr 8).toByte(),
            payloadBytes.toByte(),
            (0x30 or rateCode).toByte(),
            (depthCode shl 6).toByte(),
        )

    private fun toPcm16(payload: ByteArray, bytesPerSample: Int): ByteArray =
        payload.toList().chunked(bytesPerSample).flatMap { listOf(it[1], it[0]) }.toByteArray()
}
