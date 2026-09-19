package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.ParserException
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
    private val header = ByteArray(4)
    private var headerBytesRead = 0
    private val frame = ByteArray(24)
    private var frameBytesRead = 0
    private var frameSize = 0
    private var bytesPerSample = 0
    private var channels = intArrayOf(0, 1)
    private var sampleRate = 0
    private var payloadRemaining = 0
    private var timeUs = C.TIME_UNSET
    private var framesWritten = 0L
    // At most 10 ms at 192 kHz, eight channels, PCM16. Reused for every PES.
    private val pcm = ByteArray(30_720)
    private val pcmData = ParsableByteArray(pcm)
    private var pcmSize = 0

    override fun createTracks(output: ExtractorOutput, idGenerator: TsPayloadReader.TrackIdGenerator) {
        idGenerator.generateNewId()
        formatId = idGenerator.formatId
        this.output = output.track(idGenerator.trackId, C.TRACK_TYPE_AUDIO)
    }

    override fun packetStarted(pesTimeUs: Long, flags: Int) {
        flush()
        if (pesTimeUs != C.TIME_UNSET) {
            timeUs = pesTimeUs
            framesWritten = 0
        }
        headerBytesRead = 0
        frameBytesRead = 0
        payloadRemaining = 0
    }

    override fun consume(data: ParsableByteArray) {
        if (headerBytesRead < 4) {
            val count = minOf(4 - headerBytesRead, data.bytesLeft())
            data.readBytes(header, headerBytesRead, count)
            headerBytesRead += count
            if (headerBytesRead < 4) return
            parseHeader()
        }
        while (data.bytesLeft() > 0 && payloadRemaining > 0) {
            val count = minOf(frameSize - frameBytesRead, data.bytesLeft(), payloadRemaining)
            data.readBytes(frame, frameBytesRead, count)
            frameBytesRead += count
            payloadRemaining -= count
            if (frameBytesRead == frameSize) {
                for (channel in channels) {
                    val offset = channel * bytesPerSample
                    pcm[pcmSize++] = frame[offset + 1]
                    pcm[pcmSize++] = frame[offset]
                }
                frameBytesRead = 0
                if (pcmSize >= sampleRate / 100 * channels.size * 2) flush()
            }
        }
        if (payloadRemaining == 0) {
            if (frameBytesRead != 0) fail("Truncated Blu-ray LPCM sample frame")
            flush()
        }
        data.skipBytes(data.bytesLeft())
    }

    override fun packetFinished(isEndOfInput: Boolean) {
        if (headerBytesRead in 1..3) fail("Truncated Blu-ray LPCM header")
        flush()
        frameBytesRead = 0
    }

    override fun seek() {
        pcmSize = 0
        frameBytesRead = 0
        headerBytesRead = 0
        payloadRemaining = 0
        timeUs = C.TIME_UNSET
        framesWritten = 0
    }

    private fun parseHeader() {
        val layout = (header[2].toInt() ushr 4) and 15
        // HDMV source order: FL FR FC SL BL BR SR LFE for 7.1.
        channels = when (layout) {
            1 -> MONO
            3 -> STEREO
            9 -> SURROUND_51
            11 -> SURROUND_71
            else -> fail("Unsupported Blu-ray LPCM channel layout: $layout; use MPV")
        }
        val rate = when (header[2].toInt() and 15) {
            1 -> 48_000
            4 -> 96_000
            5 -> 192_000
            else -> fail("Invalid Blu-ray LPCM sample rate")
        }
        bytesPerSample = when ((header[3].toInt() ushr 6) and 3) {
            1 -> 2
            2, 3 -> 3
            else -> fail("Invalid Blu-ray LPCM sample depth")
        }
        frameSize = ((channels.size + 1) / 2 * 2) * bytesPerSample
        payloadRemaining = ((header[0].toInt() and 255) shl 8) or (header[1].toInt() and 255)
        if (payloadRemaining == 0 || payloadRemaining % frameSize != 0) {
            fail("Invalid Blu-ray LPCM payload length")
        }
        if (sampleRate != rate) {
            if (sampleRate > 0 && timeUs != C.TIME_UNSET) timeUs += framesWritten * 1_000_000L / sampleRate
            framesWritten = 0
            sampleRate = rate
        }
        if (format?.sampleRate != rate || format?.channelCount != channels.size) {
            val next = Format.Builder().setId(formatId)
                .setContainerMimeType(MimeTypes.VIDEO_MP2T).setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setPcmEncoding(C.ENCODING_PCM_16BIT).setChannelCount(channels.size)
                .setSampleRate(rate).setLanguage(language).setRoleFlags(roleFlags).build()
            output!!.format(next)
            format = next
        }
    }

    private fun flush() {
        if (pcmSize == 0) return
        val track = output ?: return
        if (timeUs == C.TIME_UNSET) timeUs = 0
        pcmData.reset(pcm, pcmSize)
        track.sampleData(pcmData, pcmSize, TrackOutput.SAMPLE_DATA_PART_MAIN)
        track.sampleMetadata(timeUs + framesWritten * 1_000_000L / sampleRate,
            C.BUFFER_FLAG_KEY_FRAME, pcmSize, 0, null)
        framesWritten += pcmSize / (channels.size * 2)
        pcmSize = 0
    }

    private fun fail(message: String): Nothing =
        throw ParserException.createForUnsupportedContainerFeature(message)

    private companion object {
        val MONO = intArrayOf(0)
        val STEREO = intArrayOf(0, 1)
        val SURROUND_51 = intArrayOf(0, 1, 2, 5, 3, 4)
        val SURROUND_71 = intArrayOf(0, 1, 2, 7, 4, 5, 3, 6)
    }
}
