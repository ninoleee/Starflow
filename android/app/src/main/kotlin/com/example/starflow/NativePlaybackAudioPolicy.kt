package com.example.starflow

import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.C

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
    fun encodingLabel(encoding: Int?): String = when (encoding) {
        null, C.ENCODING_INVALID, -1 -> "unknown"
        C.ENCODING_PCM_16BIT -> "PCM16"
        C.ENCODING_PCM_24BIT -> "PCM24"
        C.ENCODING_PCM_32BIT -> "PCM32"
        C.ENCODING_PCM_FLOAT -> "Float32"
        C.ENCODING_AC3 -> "AC3"
        C.ENCODING_E_AC3 -> "EAC3"
        C.ENCODING_DTS -> "DTS"
        C.ENCODING_DTS_HD -> "DTS-HD"
        C.ENCODING_DOLBY_TRUEHD -> "TrueHD"
        else -> "encoding($encoding)"
    }

    fun useHighPrecisionPcm(
        outputMode: NativeAudioOutputMode,
        parameters: PlaybackParameters,
        compatibilityFallback: Boolean,
    ): Boolean = outputMode != NativeAudioOutputMode.PCM_COMPATIBILITY &&
        !compatibilityFallback && parameters == PlaybackParameters.DEFAULT

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
        parameters: PlaybackParameters = PlaybackParameters.DEFAULT,
        outputFallback: Boolean = false,
    ): Boolean =
        mimeType != null && MimeTypes.isAudio(mimeType) &&
            (outputMode == NativeAudioOutputMode.PCM_COMPATIBILITY ||
                parameters != PlaybackParameters.DEFAULT || outputFallback ||
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
