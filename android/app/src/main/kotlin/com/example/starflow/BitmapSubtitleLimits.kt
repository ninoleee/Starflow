package com.example.starflow

import java.io.ByteArrayOutputStream
import java.util.zip.Inflater

/** Limits apply before allocation, including zlib output and retained encoded objects. */
internal object BitmapSubtitleLimits {
    const val MAX_SAMPLE_BYTES = 4 * 1024 * 1024
    const val MAX_CACHE_BYTES = 8 * 1024 * 1024
    const val MAX_PIXELS = 3840 * 2160
    const val MAX_DIMENSION = 4096

    @JvmStatic fun checkDimensions(width: Int, height: Int) {
        require(width in 1..MAX_DIMENSION && height in 1..MAX_DIMENSION &&
            width.toLong() * height <= MAX_PIXELS) { "bitmap dimensions exceed budget" }
    }

    @JvmStatic fun sample(data: ByteArray, offset: Int, length: Int): ByteArray {
        require(offset >= 0 && length in 0..MAX_SAMPLE_BYTES && offset <= data.size - length) {
            "sample exceeds budget or bounds"
        }
        val zlib = length >= 2 && data[offset] == 0x78.toByte() &&
            (((data[offset].toInt() and 255) shl 8) + (data[offset + 1].toInt() and 255)) % 31 == 0
        if (!zlib) return data.copyOfRange(offset, offset + length)
        val inflater = Inflater()
        try {
            inflater.setInput(data, offset, length)
            val output = ByteArrayOutputStream()
            val chunk = ByteArray(8192)
            while (!inflater.finished()) {
                val count = inflater.inflate(chunk)
                require(count > 0 && output.size() + count <= MAX_SAMPLE_BYTES) {
                    "invalid or oversized zlib subtitle"
                }
                output.write(chunk, 0, count)
            }
            return output.toByteArray()
        } finally {
            inflater.end()
        }
    }
}

internal class BitmapSubtitleDiagnostics(private val codec: String) {
    private var dropped = 0L
    private var lastLogNs = 0L
    private var lastDecodeLogNs = 0L

    fun decoded(startNs: Long, pixels: Long, cacheBytes: Int) {
        val now = System.nanoTime()
        if (lastDecodeLogNs != 0L && now - lastDecodeLogNs < 30_000_000_000L) return
        lastDecodeLogNs = now
        NativeAppLogger.log("info", "subtitle.decode", "Bitmap subtitle decoded",
            fields = mapOf("codec" to codec, "decodeUs" to (now - startNs) / 1000,
                "pixels" to pixels, "cacheBytes" to cacheBytes))
    }

    fun drop(reason: String) {
        dropped++
        val now = System.nanoTime()
        if (lastLogNs != 0L && now - lastLogNs < 5_000_000_000L) return
        lastLogNs = now
        NativeAppLogger.log("warning", "subtitle.decode.drop", "Invalid bitmap subtitle dropped",
            fields = mapOf("codec" to codec, "reason" to reason, "dropped" to dropped))
    }
}

internal object NativeBitmapSubtitlePolicy {
    fun isBitmap(vararg types: String?): Boolean = types.any {
        it?.trim()?.lowercase() in setOf("application/pgs", "application/vobsub", "application/dvbsubs",
            "pgs", "sup", "idx", "hdmv_pgs_subtitle", "dvd_subtitle", "dvb_subtitle", "vobsub",
            "xsub", "s_hdmv/pgs", "s_vobsub", "s_dvbsub")
    }
}
