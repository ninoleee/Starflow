package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.Consumer
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.extractor.text.CuesWithTiming
import androidx.media3.extractor.text.DefaultSubtitleParserFactory
import androidx.media3.extractor.text.SubtitleParser

internal class NativeSubtitleParserFactory : SubtitleParser.Factory {
    private val delegate = DefaultSubtitleParserFactory()
    override fun supportsFormat(format: Format) = delegate.supportsFormat(format)
    override fun getCueReplacementBehavior(format: Format) = delegate.getCueReplacementBehavior(format)
    override fun create(format: Format): SubtitleParser = when (format.sampleMimeType) {
        MimeTypes.APPLICATION_PGS -> BoundedPgsParser()
        MimeTypes.APPLICATION_VOBSUB -> BoundedVobsubParser(format.initializationData)
        MimeTypes.APPLICATION_DVBSUBS -> {
            val init = format.initializationData.firstOrNull()
            val page = if (init != null && init.size >= 2)
                ((init[0].toInt() and 255) shl 8) or (init[1].toInt() and 255) else -1
            BoundedDvbParser(page) { delegate.create(format) }
        }
        else -> delegate.create(format)
    }
}

/** Validate DVB allocation-bearing headers before handing pixel decoding to Media3. */
internal class BoundedDvbParser(
    private val primaryPageId: Int = -1,
    private val create: () -> SubtitleParser,
) : SubtitleParser {
    private var delegate = create()
    private val retained = mutableMapOf<Long, Int>()
    private val regions = mutableMapOf<Long, Long>()
    private val diagnostics = BitmapSubtitleDiagnostics("dvb")
    override fun getCueReplacementBehavior() = delegate.cueReplacementBehavior
    override fun reset() {
        // Recreate as DvbParser.reset() retains the canvas bitmap.
        delegate = create()
        retained.clear()
        regions.clear()
    }

    override fun parse(data: ByteArray, offset: Int, length: Int,
        outputOptions: SubtitleParser.OutputOptions, output: Consumer<CuesWithTiming>) {
        var result: CuesWithTiming? = null
        try {
            val bytes = BitmapSubtitleLimits.sample(data, offset, length)
            val b = ParsableByteArray(bytes)
            while (b.bytesLeft() >= 6 && b.readUnsignedByte() == 0x0f) {
                val type = b.readUnsignedByte()
                val page = b.readUnsignedShort()
                val size = b.readUnsignedShort()
                require(size <= b.bytesLeft()) { "truncated DVB segment" }
                val start = b.position
                val end = start + size
                if (type == 0x10 && page == primaryPageId && size >= 2 &&
                    (bytes[start + 1].toInt() and 0x0c) != 0) {
                    retained.keys.removeAll { it shr 24 == page.toLong() }
                    regions.keys.removeAll { it shr 16 == page.toLong() }
                }
                if (type == 0x14) {
                    require(size >= 5)
                    val flags = b.readUnsignedByte()
                    val w = b.readUnsignedShort() + 1
                    val h = b.readUnsignedShort() + 1
                    BitmapSubtitleLimits.checkDimensions(w, h)
                    require(flags and 8 == 0 || size >= 13) { "short DVB window" }
                }
                if (type == 0x11) {
                    require(size >= 10)
                    val id = b.readUnsignedByte()
                    b.skipBytes(1)
                    val w = b.readUnsignedShort()
                    val h = b.readUnsignedShort()
                    BitmapSubtitleLimits.checkDimensions(w, h)
                    regions[(page.toLong() shl 16) or id.toLong()] = w.toLong() * h
                    require(regions.values.sum() <= BitmapSubtitleLimits.MAX_PIXELS) { "DVB regions exceed budget" }
                }
                if (type in 0x10..0x13) {
                    require(size >= 2)
                    val id = if (type == 0x10) 0 else if (type == 0x13)
                        ((bytes[start].toInt() and 255) shl 8) or (bytes[start + 1].toInt() and 255)
                        else bytes[start].toInt() and 255
                    val key = (page.toLong() shl 24) or (type.toLong() shl 16) or id.toLong()
                    // Region object lists can merge in normal mode: count updates conservatively.
                    retained[key] = if (type == 0x11) (retained[key] ?: 0) + size else size
                    require(retained.size <= 4096 && retained.values.sum().toLong() <= BitmapSubtitleLimits.MAX_CACHE_BYTES) {
                        "DVB cache exceeds budget"
                    }
                }
                b.position = end
            }
            // Slice to offset zero: Media3 1.10.1 incorrectly treats byte offsets as bits.
            delegate.parse(bytes, 0, bytes.size, outputOptions) { result = it }
        } catch (e: Exception) {
            diagnostics.drop(e.message ?: e.javaClass.simpleName)
            reset()
            result = CuesWithTiming(emptyList(), C.TIME_UNSET, C.TIME_UNSET)
        }
        result?.let(output::accept)
    }
}
