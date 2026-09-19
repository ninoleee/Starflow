package androidx.media3.extractor.ts

import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.common.util.TimestampAdjuster
import androidx.media3.extractor.DefaultExtractorInput
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.PositionHolder
import com.example.starflow.NativePlaybackExtractorsFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StarflowTsTimestampSearchTest {
    @Test
    fun sparsePcrSeekDoesNotStopAtTheInitialByteEstimate() {
        val media = transportStream()
        val targetUs = 878_381L
        val defaultResult = seek(media, targetUs, TsExtractor.DEFAULT_TIMESTAMP_SEARCH_BYTES)
        assertEquals(defaultResult.initialEstimate, defaultResult.position)
        assertTrue("The old window must reproduce an inaccurate seek", defaultResult.pcrUs < targetUs - 100_000)

        val result = seek(media, targetUs, NativePlaybackExtractorsFactory.TS_TIMESTAMP_SEARCH_BYTES)
        assertNotEquals(result.initialEstimate, result.position)
        assertTrue("Seek should converge within Media3's PCR tolerance", kotlin.math.abs(result.pcrUs - targetUs) <= 100_000)
    }

    @Test
    fun sparseTailPcrStillProvidesDurationInsteadOfDisablingSeek() {
        val media = transportStream()
        assertEquals(C.TIME_UNSET, duration(media, TsExtractor.DEFAULT_TIMESTAMP_SEARCH_BYTES))
        assertEquals(DURATION_US, duration(media, NativePlaybackExtractorsFactory.TS_TIMESTAMP_SEARCH_BYTES))
    }

    private fun duration(media: ByteArray, window: Int): Long {
        val reader = TsDurationReader(window)
        var input = input(media, 0)
        val position = PositionHolder()
        repeat(10) {
            if (reader.isDurationReadFinished) return reader.durationUs
            if (reader.readDuration(input, position, PCR_PID) == Extractor.RESULT_SEEK) {
                input = input(media, position.position)
            }
        }
        error("Duration reader did not finish")
    }

    private data class SeekResult(val initialEstimate: Long, val position: Long, val pcrUs: Long)

    private fun seek(media: ByteArray, targetUs: Long, window: Int): SeekResult {
        val adjuster = TimestampAdjuster(0)
        adjuster.adjustTsTimestamp(BASE_PCR)
        val seeker = TsBinarySearchSeeker(adjuster, DURATION_US, media.size.toLong(), PCR_PID, window)
        val estimate = seeker.seekMap.getSeekPoints(targetUs).first.position
        var input = input(media, estimate)
        val position = PositionHolder()
        seeker.setSeekTargetUs(targetUs)
        repeat(30) {
            val result = seeker.handlePendingSeek(input, position)
            if (result == Extractor.RESULT_SEEK) input = input(media, position.position)
            if (!seeker.isSeeking) {
                val buffer = androidx.media3.common.util.ParsableByteArray(media)
                var offset = input.position.toInt()
                while (offset + TsExtractor.TS_PACKET_SIZE <= media.size) {
                    if (media[offset] == 0x47.toByte()) {
                        val pcr = TsUtil.readPcrFromPacket(buffer, offset, PCR_PID)
                        if (pcr != C.TIME_UNSET) {
                            return SeekResult(estimate, input.position, TimestampAdjuster.ptsToUs(pcr - BASE_PCR))
                        }
                    }
                    offset++
                }
                error("No PCR after seek position")
            }
        }
        error("Binary search did not converge")
    }

    private fun input(media: ByteArray, position: Long): DefaultExtractorInput {
        var offset = position.toInt()
        return DefaultExtractorInput(DataReader { target, start, length ->
            val size = minOf(length, media.size - offset)
            if (size == 0) C.RESULT_END_OF_INPUT else {
                media.copyInto(target, start, offset, offset + size)
                offset += size
                size
            }
        }, position, media.size.toLong())
    }

    private fun transportStream(): ByteArray {
        val data = ByteArray(32_000 * TsExtractor.TS_PACKET_SIZE) { 0xFF.toByte() }
        for (packet in 0 until 32_000) {
            val offset = packet * TsExtractor.TS_PACKET_SIZE
            data[offset] = 0x47
            data[offset + 1] = 0x1F
            data[offset + 2] = 0xFF.toByte()
            data[offset + 3] = 0x10
        }
        // Sparse PCRs and a variable byte/time distribution expose the interpolation fallback.
        val timesMs = listOf(0, 100, 200, 300, 400, 500, 550, 600, 650, 727, 878, 1000, 1200, 1300, 1400)
        for ((index, timeMs) in timesMs.withIndex()) {
            val offset = (index * 2200 + 10) * TsExtractor.TS_PACKET_SIZE
            val pcr = BASE_PCR + timeMs * 90L
            data[offset + 1] = (PCR_PID shr 8).toByte()
            data[offset + 2] = PCR_PID.toByte()
            data[offset + 3] = 0x20
            data[offset + 4] = 183.toByte()
            data[offset + 5] = 0x10
            data[offset + 6] = (pcr shr 25).toByte()
            data[offset + 7] = (pcr shr 17).toByte()
            data[offset + 8] = (pcr shr 9).toByte()
            data[offset + 9] = (pcr shr 1).toByte()
            data[offset + 10] = (((pcr and 1) shl 7) or 0x7E).toByte()
            data[offset + 11] = 0
        }
        return data
    }

    private companion object {
        const val PCR_PID = 4097
        const val BASE_PCR = 600 * 90_000L
        const val DURATION_US = 1_400_000L
    }
}
