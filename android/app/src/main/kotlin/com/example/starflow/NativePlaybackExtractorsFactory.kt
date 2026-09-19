package com.example.starflow

import android.util.SparseArray
import androidx.media3.common.util.TimestampAdjuster
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.text.DefaultSubtitleParserFactory
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import androidx.media3.extractor.ts.PesReader
import androidx.media3.extractor.ts.TsExtractor
import androidx.media3.extractor.ts.TsPayloadReader

internal class NativePlaybackExtractorsFactory(
    private val audioCodec: String = "",
) : ExtractorsFactory {
    override fun createExtractors(): Array<Extractor> {
        return DefaultExtractorsFactory()
            .createExtractors()
            .map { extractor ->
                if (extractor !is TsExtractor) {
                    extractor
                } else {
                    TsExtractor(
                        TsExtractor.MODE_MULTI_PMT,
                        0,
                        DefaultSubtitleParserFactory(),
                        TimestampAdjuster(0),
                        NativeTsPayloadReaderFactory(audioCodec),
                        TsExtractor.DEFAULT_TIMESTAMP_SEARCH_BYTES,
                    )
                }
            }
            .toTypedArray()
    }
}

internal class NativeTsPayloadReaderFactory(
    private val audioCodec: String = "",
) : TsPayloadReader.Factory {
    private val delegate = DefaultTsPayloadReaderFactory(0)

    override fun createInitialPayloadReaders(): SparseArray<TsPayloadReader> =
        delegate.createInitialPayloadReaders()

    override fun createPayloadReader(
        streamType: Int,
        esInfo: TsPayloadReader.EsInfo,
    ): TsPayloadReader? {
        return when {
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
