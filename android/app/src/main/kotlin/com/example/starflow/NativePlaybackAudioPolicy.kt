package com.example.starflow

enum class NativeAudioOutputMode(
    val rawValue: String,
    val displayLabel: String,
) {
    AUTO("auto", "自动（推荐）"),
    PCM_COMPATIBILITY("pcmCompatibility", "PCM 兼容"),
    DEVICE_PASSTHROUGH("devicePassthrough", "设备直通"),
    ;

    companion object {
        fun fromRaw(raw: String): NativeAudioOutputMode =
            entries.firstOrNull { it.rawValue == raw.trim() } ?: AUTO
    }
}

object NativePlaybackAudioPolicy {
    fun shouldForcePcmOutput(
        isTelevision: Boolean,
        audioCodec: String,
        outputMode: NativeAudioOutputMode = NativeAudioOutputMode.AUTO,
    ): Boolean {
        when (outputMode) {
            NativeAudioOutputMode.PCM_COMPATIBILITY -> return true
            NativeAudioOutputMode.DEVICE_PASSTHROUGH -> return false
            NativeAudioOutputMode.AUTO -> if (!isTelevision) return false
        }
        return isDolbyDigitalPlus(audioCodec)
    }

    fun shouldEnableFfmpegAudioDecoder(
        forcePcmAudioOutput: Boolean,
        audioCodec: String,
    ): Boolean =
        (forcePcmAudioOutput && isAc3Family(audioCodec)) ||
            isTrueHdFamily(audioCodec) ||
            isDtsFamily(audioCodec) ||
            isMpegAudioFamily(audioCodec)

    private fun isDolbyDigitalPlus(audioCodec: String): Boolean {
        val normalizedCodec = normalizeCodec(audioCodec)
        return normalizedCodec == "eac3" ||
            normalizedCodec == "eac3_joc" ||
            normalizedCodec == "ec_3" ||
            normalizedCodec == "ddp" ||
            normalizedCodec == "ddplus" ||
            normalizedCodec == "dolby_digital_plus"
    }

    private fun isAc3Family(audioCodec: String): Boolean {
        val normalizedCodec = normalizeCodec(audioCodec)
        return isDolbyDigitalPlus(normalizedCodec) ||
            normalizedCodec == "ac3" ||
            normalizedCodec == "ac_3" ||
            normalizedCodec == "dolby_digital"
    }

    private fun isTrueHdFamily(audioCodec: String): Boolean {
        val normalizedCodec = normalizeCodec(audioCodec)
        return normalizedCodec.startsWith("truehd") ||
            normalizedCodec == "mlp" ||
            normalizedCodec == "mha"
    }

    private fun isDtsFamily(audioCodec: String): Boolean {
        val normalizedCodec = normalizeCodec(audioCodec)
        return normalizedCodec.startsWith("dts") ||
            normalizedCodec == "dca"
    }

    private fun isMpegAudioFamily(audioCodec: String): Boolean {
        val normalizedCodec = normalizeCodec(audioCodec)
        return normalizedCodec == "mp1" ||
            normalizedCodec == "mp2" ||
            normalizedCodec == "mpa"
    }

    private fun normalizeCodec(audioCodec: String): String =
        audioCodec
            .trim()
            .lowercase()
            .replace('-', '_')
            .replace('.', '_')
}
