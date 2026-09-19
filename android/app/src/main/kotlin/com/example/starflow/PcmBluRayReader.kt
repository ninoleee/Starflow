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

@UnstableApi
internal class PcmBluRayReader(
    private val language: String?,
    private val roleFlags: Int,
) : ElementaryStreamReader {
    private var output: TrackOutput? = null
    private var format: Format? = null
    private var formatId = ""
    private var timeUs = C.TIME_UNSET
    private var sampleFramesWritten = 0L
    private var sampleRate = 0
    private var headerBytesRead = 0
    private val header = ByteArray(4)
    private val pending = ByteArray(6)
    private var pendingBytes = 0
    private var sampleBytesPerFrame = 0
    private var bitsPerSample = 0
    private var unsupported = false

    override fun createTracks(
        extractorOutput: ExtractorOutput,
        idGenerator: TsPayloadReader.TrackIdGenerator,
    ) {
        idGenerator.generateNewId()
        formatId = idGenerator.formatId
        output = extractorOutput.track(idGenerator.trackId, C.TRACK_TYPE_AUDIO)
    }

    override fun packetStarted(pesTimeUs: Long, flags: Int) {
        if (pesTimeUs != C.TIME_UNSET) {
            timeUs = pesTimeUs
            sampleFramesWritten = 0
        }
        headerBytesRead = 0
        pendingBytes = 0
        unsupported = false
    }

    override fun consume(data: ParsableByteArray) {
        if (!unsupported && headerBytesRead < header.size && !readHeader(data)) {
            if (unsupported) data.skipBytes(data.bytesLeft())
            return
        }
        if (unsupported) {
            data.skipBytes(data.bytesLeft())
            return
        }
        val trackOutput = output ?: return
        val frameBytes = sampleBytesPerFrame
        if (frameBytes <= 0) return

        val available = data.bytesLeft()
        if (available <= 0) return
        val total = pendingBytes + available
        val completeBytes = total - total % frameBytes
        if (completeBytes == 0) {
            copyToPending(data, available)
            return
        }

        val source = ByteArray(completeBytes)
        System.arraycopy(pending, 0, source, 0, pendingBytes)
        // A TS payload can end mid-sample; only complete frames fit in source.
        data.readBytes(source, pendingBytes, completeBytes - pendingBytes)
        pendingBytes = total - completeBytes
        if (pendingBytes > 0) {
            data.readBytes(pending, 0, pendingBytes)
        }

        val converted = ByteArray(completeBytes / frameBytes * 4)
        var inputPosition = 0
        var outputPosition = 0
        while (inputPosition < completeBytes) {
            if (bitsPerSample == 16) {
                converted[outputPosition] = source[inputPosition + 1]
                converted[outputPosition + 1] = source[inputPosition]
                converted[outputPosition + 2] = source[inputPosition + 3]
                converted[outputPosition + 3] = source[inputPosition + 2]
                inputPosition += 4
            } else {
                writeInt16(
                    converted,
                    outputPosition,
                    readSigned24(source, inputPosition) shr 8,
                )
                writeInt16(
                    converted,
                    outputPosition + 2,
                    readSigned24(source, inputPosition + 3) shr 8,
                )
                inputPosition += 6
            }
            outputPosition += 4
        }
        trackOutput.sampleData(
            ParsableByteArray(converted),
            converted.size,
            TrackOutput.SAMPLE_DATA_PART_MAIN,
        )
        if (timeUs == C.TIME_UNSET) timeUs = 0
        trackOutput.sampleMetadata(
            timeUs + sampleFramesWritten * 1_000_000L / sampleRate,
            C.BUFFER_FLAG_KEY_FRAME,
            converted.size,
            0,
            null,
        )
        sampleFramesWritten += completeBytes / frameBytes
    }

    override fun packetFinished(isEndOfInput: Boolean) {
        pendingBytes = 0
    }

    override fun seek() {
        timeUs = C.TIME_UNSET
        sampleFramesWritten = 0
        headerBytesRead = 0
        pendingBytes = 0
        unsupported = false
    }

    private fun readHeader(data: ParsableByteArray): Boolean {
        val toRead = minOf(4 - headerBytesRead, data.bytesLeft())
        if (toRead <= 0) return false
        data.readBytes(header, headerBytesRead, toRead)
        headerBytesRead += toRead
        if (headerBytesRead < 4) return false

        val channelLayout = (header[2].toInt() ushr 4) and 0x0F
        val sampleRateCode = header[2].toInt() and 0x0F
        val bitDepthCode = (header[3].toInt() ushr 6) and 0x03
        val newSampleRate = when (sampleRateCode) {
            1 -> 48_000
            4 -> 96_000
            5 -> 192_000
            else -> 0
        }
        bitsPerSample = when (bitDepthCode) {
            1 -> 16
            2, 3 -> 24
            else -> 0
        }
        if (channelLayout != 3 || newSampleRate <= 0 || bitsPerSample <= 0) {
            unsupported = true
            return false
        }
        sampleBytesPerFrame = if (bitsPerSample == 16) 4 else 6
        if (sampleRate != newSampleRate) {
            if (timeUs != C.TIME_UNSET && sampleRate > 0) {
                timeUs += sampleFramesWritten * 1_000_000L / sampleRate
            }
            sampleFramesWritten = 0
            sampleRate = newSampleRate
        }

        val trackOutput = output ?: return false
        if (format?.sampleRate != sampleRate) {
            val newFormat = Format.Builder()
                .setId(formatId)
                .setContainerMimeType(MimeTypes.VIDEO_MP2T)
                .setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setPcmEncoding(C.ENCODING_PCM_16BIT)
                .setChannelCount(2)
                .setSampleRate(sampleRate)
                .setLanguage(language)
                .setRoleFlags(roleFlags)
                .build()
            trackOutput.format(newFormat)
            format = newFormat
        }
        return true
    }

    private fun copyToPending(data: ParsableByteArray, bytes: Int) {
        val target = pendingBytes
        data.readBytes(pending, target, bytes)
        pendingBytes += bytes
    }

    private fun readSigned24(bytes: ByteArray, offset: Int): Int {
        return (bytes[offset].toInt() shl 16) or
            ((bytes[offset + 1].toInt() and 0xFF) shl 8) or
            (bytes[offset + 2].toInt() and 0xFF)
    }

    private fun writeInt16(bytes: ByteArray, offset: Int, value: Int) {
        bytes[offset] = value.toByte()
        bytes[offset + 1] = (value shr 8).toByte()
    }
}
