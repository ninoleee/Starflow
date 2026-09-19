package com.example.starflow

import android.util.SparseArray
import androidx.media3.common.util.TimestampAdjuster
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.ExtractorInput
import androidx.media3.extractor.PositionHolder
import androidx.media3.extractor.TrackOutput
import androidx.media3.common.Format
import androidx.media3.extractor.ForwardingExtractor
import androidx.media3.extractor.text.SubtitleParser
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import androidx.media3.extractor.ts.PesReader
import androidx.media3.extractor.ts.TsExtractor
import androidx.media3.extractor.ts.TsPayloadReader

internal class NativePlaybackExtractorsFactory(
    private val audioCodec: String = "",
) : ExtractorsFactory {
    private var subtitleParserFactory: SubtitleParser.Factory = NativeSubtitleParserFactory()

    override fun setSubtitleParserFactory(factory: SubtitleParser.Factory): ExtractorsFactory {
        subtitleParserFactory = factory
        return this
    }

    override fun createExtractors(): Array<Extractor> {
        val parserFactory = subtitleParserFactory
        // DefaultExtractorsFactory shares a factory across candidates. Register parsers with
        // the extractor currently executing init/read, never with a session-global reset list.
        val owner = ThreadLocal<MutableMap<String?, SubtitleParser>>()
        val scopedFactory = object : SubtitleParser.Factory by parserFactory {
            override fun create(format: Format): SubtitleParser =
                parserFactory.create(format).also {
                    checkNotNull(owner.get())[format.id] = it
                }
        }
        return DefaultExtractorsFactory()
            .setSubtitleParserFactory(scopedFactory)
            .createExtractors()
            .map { extractor ->
                val parsers = mutableMapOf<String?, SubtitleParser>()
                val actual = if (extractor !is TsExtractor) {
                    extractor
                } else {
                    TsExtractor(
                        TsExtractor.MODE_MULTI_PMT,
                        0,
                        scopedFactory,
                        TimestampAdjuster(0),
                        NativeTsPayloadReaderFactory(audioCodec) { ids ->
                            ids.forEach { parsers[it]?.reset() }
                        },
                        TS_TIMESTAMP_SEARCH_BYTES,
                    )
                }
                object : ForwardingExtractor(actual) {
                    private fun <T> owned(block: () -> T): T {
                        owner.set(parsers)
                        try { return block() } finally { owner.remove() }
                    }
                    override fun init(output: ExtractorOutput) = owned { super.init(output) }
                    override fun read(input: ExtractorInput, seekPosition: PositionHolder): Int =
                        owned { super.read(input, seekPosition) }
                    override fun seek(position: Long, timeUs: Long) = owned {
                        parsers.values.forEach { it.reset() }
                        super.seek(position, timeUs)
                    }
                    override fun release() {
                        try {
                            parsers.values.forEach { it.reset() }
                            super.release()
                        } finally {
                            parsers.clear()
                        }
                    }
                }
            }
            .toTypedArray()
    }

    internal companion object {
        // High-bitrate Blu-ray TS can leave >450 KiB between PCR packets. Media3 gives
        // up seeking if one search window contains no PCR, then reads a guessed offset.
        const val TS_TIMESTAMP_SEARCH_BYTES = 6000 * TsExtractor.TS_PACKET_SIZE
    }
}

internal class NativeTsPayloadReaderFactory(
    private val audioCodec: String = "",
    private val resetSubtitleParsers: (Set<String?>) -> Unit = {},
) : TsPayloadReader.Factory {
    // Blu-ray open GOPs can have non-IDR I slices without a TS random-access flag.
    private val delegate = DefaultTsPayloadReaderFactory(
        DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES,
    )

    override fun createInitialPayloadReaders(): SparseArray<TsPayloadReader> =
        delegate.createInitialPayloadReaders()

    override fun createPayloadReader(
        streamType: Int,
        esInfo: TsPayloadReader.EsInfo,
    ): TsPayloadReader? {
        val reader = when {
            shouldUseBluRayPcm(streamType, esInfo.descriptorBytes) ->
                PesReader(
                    PcmBluRayReader(
                        language = esInfo.language,
                        roleFlags = esInfo.getRoleFlags(),
                    ),
                )

            streamType == TS_STREAM_TYPE_HDMV_PGS ->
                PesReader(
                    PgsReader(
                        language = esInfo.language,
                        roleFlags = esInfo.getRoleFlags(),
                    ),
                )

            else -> delegate.createPayloadReader(streamType, esInfo)
        } ?: return null
        if (streamType != TS_STREAM_TYPE_HDMV_PGS && streamType != 0x59) return reader
        return object : TsPayloadReader by reader {
            private val ids = mutableSetOf<String?>()
            override fun init(adjuster: TimestampAdjuster, output: ExtractorOutput,
                idGenerator: TsPayloadReader.TrackIdGenerator) {
                reader.init(adjuster, object : ExtractorOutput by output {
                    override fun track(id: Int, type: Int): TrackOutput {
                        val track = output.track(id, type)
                        return object : TrackOutput by track {
                            override fun format(format: Format) {
                                ids += format.id
                                track.format(format)
                            }
                        }
                    }
                }, idGenerator)
            }
            override fun seek() {
                resetSubtitleParsers(ids)
                reader.seek()
            }
        }
    }

    internal fun shouldUseBluRayPcm(streamType: Int, descriptors: ByteArray): Boolean {
        if (streamType != TS_STREAM_TYPE_HDMV_LPCM) return false
        var position = 0
        var hasHdmvRegistration = false
        while (position < descriptors.size) {
            if (descriptors.size - position < 2) return false
            val tag = descriptors[position].toInt() and 0xFF
            val length = descriptors[position + 1].toInt() and 0xFF
            position += 2
            if (length > descriptors.size - position) return false
            if (tag == 0x05) {
                // Registration descriptors qualify the otherwise ambiguous 0x80 type.
                if (length < 4 ||
                    descriptors[position] != 0x48.toByte() ||
                    descriptors[position + 1] != 0x44.toByte() ||
                    descriptors[position + 2] != 0x4D.toByte() ||
                    descriptors[position + 3] != 0x56.toByte()
                ) return false
                hasHdmvRegistration = true
            }
            position += length
        }
        return hasHdmvRegistration || audioCodec.trim().equals("pcm_bluray", ignoreCase = true)
    }
}

private const val TS_STREAM_TYPE_HDMV_LPCM = 0x80
private const val TS_STREAM_TYPE_HDMV_PGS = 0x90
