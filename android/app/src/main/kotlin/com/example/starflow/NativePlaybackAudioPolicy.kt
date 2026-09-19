package com.example.starflow

import androidx.media3.common.MimeTypes

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

    @Suppress("UNUSED_PARAMETER")
    fun shouldEnableFfmpegAudioDecoder(
        forcePcmAudioOutput: Boolean,
        audioCodec: String,
    ): Boolean = true

    fun requiresDecodedOutput(
        mimeType: String?,
        isTelevision: Boolean,
        outputMode: NativeAudioOutputMode,
        fallbackMime: String? = null,
    ): Boolean =
        mimeType != null && MimeTypes.isAudio(mimeType) &&
            (outputMode == NativeAudioOutputMode.PCM_COMPATIBILITY ||
                mimeType == fallbackMime ||
                (outputMode == NativeAudioOutputMode.AUTO && isTelevision &&
                    mimeType in setOf(MimeTypes.AUDIO_E_AC3, MimeTypes.AUDIO_E_AC3_JOC)))

    private fun isDolbyDigitalPlus(audioCodec: String): Boolean {
        val normalizedCodec = normalizeCodec(audioCodec)
        return normalizedCodec == "eac3" ||
            normalizedCodec == "eac3_joc" ||
            normalizedCodec == "ec_3" ||
            normalizedCodec == "ddp" ||
            normalizedCodec == "ddplus" ||
            normalizedCodec == "dolby_digital_plus"
    }

    private fun normalizeCodec(audioCodec: String): String =
        audioCodec
            .trim()
            .lowercase()
            .replace('-', '_')
            .replace('.', '_')
}
