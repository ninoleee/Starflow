package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.TrackOutput
import androidx.media3.extractor.ts.ElementaryStreamReader
import androidx.media3.extractor.ts.TsPayloadReader
import java.io.ByteArrayOutputStream

@UnstableApi
internal class PgsReader(
    private val language: String?,
    private val roleFlags: Int,
) : ElementaryStreamReader {
    private var output: TrackOutput? = null
    private var sampleTimeUs = C.TIME_UNSET
    private var packetTimeUs = C.TIME_UNSET
    private var segmentTimeUs = C.TIME_UNSET
    private var discardDisplaySet = false
    private var segmentType = -1
    private var segmentLength = 0
    private var segmentBytesRead = 0
    private val segmentHeader = ByteArray(SEGMENT_HEADER_SIZE)
    private val displaySet = ByteArrayOutputStream()

    override fun createTracks(
        extractorOutput: ExtractorOutput,
        idGenerator: TsPayloadReader.TrackIdGenerator,
    ) {
        idGenerator.generateNewId()
        val trackOutput = extractorOutput.track(idGenerator.trackId, C.TRACK_TYPE_TEXT)
        trackOutput.format(
            Format.Builder()
                .setId(idGenerator.formatId)
                .setContainerMimeType(MimeTypes.VIDEO_MP2T)
                .setSampleMimeType(MimeTypes.APPLICATION_PGS)
                .setCodecs(CODEC_PGS)
                .setLanguage(language)
                .setRoleFlags(roleFlags or C.ROLE_FLAG_SUBTITLE)
                .build(),
        )
        output = trackOutput
    }

    override fun packetStarted(timeUs: Long, flags: Int) {
        if (timeUs != C.TIME_UNSET) {
            packetTimeUs = timeUs
        }
    }

    override fun consume(data: ParsableByteArray) {
        // Blu-ray TS commonly splits one PGS display set across several PES packets.
        while (data.bytesLeft() > 0) {
            if (segmentType < 0 && !readSegmentHeader(data)) {
                return
            }
            val bytesToCopy = minOf(
                data.bytesLeft(),
                segmentLength - segmentBytesRead,
            )
            if (bytesToCopy <= 0) {
                finishSegment()
                continue
            }
            if (!discardDisplaySet) {
                displaySet.write(data.data, data.position, bytesToCopy)
            }
            data.skipBytes(bytesToCopy)
            segmentBytesRead += bytesToCopy
            if (segmentBytesRead == segmentLength) {
                finishSegment()
            }
        }
    }

    override fun packetFinished(isEndOfInput: Boolean) = Unit

    override fun seek() {
        resetSegment()
        displaySet.reset()
        sampleTimeUs = C.TIME_UNSET
        packetTimeUs = C.TIME_UNSET
        segmentTimeUs = C.TIME_UNSET
        discardDisplaySet = false
    }

    private fun readSegmentHeader(data: ParsableByteArray): Boolean {
        if (segmentBytesRead == 0) segmentTimeUs = packetTimeUs
        val bytesToRead = minOf(
            SEGMENT_HEADER_SIZE - segmentBytesRead,
            data.bytesLeft(),
        )
        if (bytesToRead <= 0) return false
        data.readBytes(segmentHeader, segmentBytesRead, bytesToRead)
        segmentBytesRead += bytesToRead
        if (segmentBytesRead < SEGMENT_HEADER_SIZE) return false

        segmentType = segmentHeader[0].toInt() and 0xFF
        segmentLength =
            ((segmentHeader[1].toInt() and 0xFF) shl 8) or
                (segmentHeader[2].toInt() and 0xFF)
        segmentBytesRead = 0
        // PCS carries presentation time; the following palette/object/END PES timestamps
        // describe decoder scheduling and can be earlier than the composition timestamp.
        if (segmentType == SEGMENT_TYPE_PRESENTATION) {
            displaySet.reset()
            discardDisplaySet = false
            sampleTimeUs = segmentTimeUs
        } else if (displaySet.size() == 0 && !discardDisplaySet) {
            sampleTimeUs = segmentTimeUs
        }
        if (displaySet.size() + SEGMENT_HEADER_SIZE + segmentLength > MAX_DISPLAY_SET_BYTES) {
            displaySet.reset()
            discardDisplaySet = true
        }
        if (!discardDisplaySet) displaySet.write(segmentHeader, 0, segmentHeader.size)
        if (segmentLength == 0) {
            finishSegment()
        }
        return true
    }

    private fun finishSegment() {
        val finishedType = segmentType
        resetSegment()
        if (finishedType == SEGMENT_TYPE_END) {
            emitDisplaySet()
        }
    }

    private fun emitDisplaySet() {
        if (displaySet.size() > 0 && sampleTimeUs != C.TIME_UNSET) {
            val data = ParsableByteArray(displaySet.toByteArray())
            output?.sampleData(
                data,
                data.bytesLeft(),
                TrackOutput.SAMPLE_DATA_PART_MAIN,
            )
            output?.sampleMetadata(
                sampleTimeUs,
                C.BUFFER_FLAG_KEY_FRAME,
                data.limit(),
                0,
                null,
            )
        }
        displaySet.reset()
        sampleTimeUs = C.TIME_UNSET
        discardDisplaySet = false
    }

    private fun resetSegment() {
        segmentType = -1
        segmentLength = 0
        segmentBytesRead = 0
    }

    private companion object {
        const val SEGMENT_HEADER_SIZE = 3
        const val SEGMENT_TYPE_END = 0x80
        const val SEGMENT_TYPE_PRESENTATION = 0x16
        const val MAX_DISPLAY_SET_BYTES = 4 * 1024 * 1024
        const val CODEC_PGS = "S_HDMV/PGS"
    }
}
