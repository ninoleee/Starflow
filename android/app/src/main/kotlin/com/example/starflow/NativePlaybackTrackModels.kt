package com.example.starflow

import android.net.Uri
import androidx.media3.common.TrackSelectionOverride
import org.json.JSONObject

internal data class ExternalSubtitleSource(
    val originalUri: Uri,
    val mimeType: String,
    val displayName: String,
)

internal data class NativeTrackChoice(
    val label: String,
    val override: TrackSelectionOverride,
    val selected: Boolean,
    val formatKey: NativeSubtitleFormatKey? = null,
    val groupFormatKeys: Set<NativeSubtitleFormatKey> = emptySet(),
    val language: String = "",
    val sourceLabel: String = "",
    val sampleMimeType: String = "",
    val codecs: String = "",
    val isDefault: Boolean = false,
    val isForced: Boolean = false,
    val isExternal: Boolean = false,
)

internal val NativeTrackChoice.subtitleFingerprint: NativeSubtitleTrackFingerprint
    get() =
        NativeSubtitleTrackFingerprint(
            id = formatKey?.id.orEmpty(),
            label = sourceLabel,
            language = language,
            sampleMimeType = sampleMimeType,
            codecs = codecs,
            isDefault = isDefault,
            isForced = isForced,
            accessibilityChannel = formatKey?.accessibilityChannel ?: -1,
        )

internal val NativeTrackChoice.restoreCandidate: NativeSubtitleRestoreCandidate<NativeTrackChoice>
    get() = NativeSubtitleRestoreCandidate(value = this, fingerprint = subtitleFingerprint)

internal val NativeTrackChoice.subtitleCandidate: NativeSubtitleTrackCandidate<NativeTrackChoice>
    get() =
        NativeSubtitleTrackCandidate(
            value = this,
            language = language,
            label = sourceLabel,
            isForced = isForced,
            isDefault = isDefault,
        )

internal val NativeTrackChoice.canUseInDualSubtitleMode: Boolean
    get() =
        !isExternal &&
            formatKey != null &&
            NativeDualSubtitleTrackPolicy.isCompatibleTextSubtitle(
                sampleMimeType = sampleMimeType,
                codecs = codecs,
            )

internal sealed interface NativeSubtitleRestoreResult {
    data object Disabled : NativeSubtitleRestoreResult

    data class Single(val choice: NativeTrackChoice) : NativeSubtitleRestoreResult

    data class Dual(val primary: NativeTrackChoice, val secondary: NativeTrackChoice) :
        NativeSubtitleRestoreResult
}

internal fun NativeSubtitleSessionPreference.toJson(
    seriesKey: String,
    updatedAt: String,
): JSONObject =
    JSONObject().apply {
        put("seriesKey", seriesKey)
        put("updatedAt", updatedAt)
        put(
            "mode",
            when (mode) {
                NativeSubtitleSessionMode.OFF -> "off"
                NativeSubtitleSessionMode.SINGLE -> "single"
                NativeSubtitleSessionMode.DUAL -> "dual"
            },
        )
        primary?.let { put("primary", it.toJson()) }
        secondary?.let { put("secondary", it.toJson()) }
    }

internal fun NativeSubtitleTrackFingerprint.toJson(): JSONObject =
    JSONObject().apply {
        put("id", id)
        put("label", label)
        put("language", language)
        put("codec", sampleMimeType.ifEmpty { codecs })
        put("sampleMimeType", sampleMimeType)
        put("codecs", codecs)
        put("isDefault", isDefault)
        put("isForced", isForced)
        put("accessibilityChannel", accessibilityChannel)
    }

internal fun JSONObject.toSubtitleFingerprint(): NativeSubtitleTrackFingerprint =
    NativeSubtitleTrackFingerprint(
        id = optString("id"),
        label = optString("label"),
        language = optString("language"),
        sampleMimeType = optString("sampleMimeType").ifEmpty { optString("codec") },
        codecs = optString("codecs"),
        isDefault = optBoolean("isDefault", false),
        isForced = optBoolean("isForced", false),
        accessibilityChannel = optInt("accessibilityChannel", -1),
    )

internal enum class NativeDefaultSubtitle(val preferredLanguages: List<String>) {
    DUAL(emptyList()),
    SIMPLIFIED_CHINESE(listOf("zh-cn")),
    TRADITIONAL_CHINESE(listOf("zh-tw")),
    ENGLISH(listOf("en")),
    JAPANESE(listOf("ja")),
    SYSTEM_LANGUAGE(emptyList());

    companion object {
        fun fromRaw(raw: String): NativeDefaultSubtitle =
            when (raw.trim()) {
                "dual" -> DUAL
                "simplifiedChinese" -> SIMPLIFIED_CHINESE
                "traditionalChinese" -> TRADITIONAL_CHINESE
                "english" -> ENGLISH
                "japanese" -> JAPANESE
                else -> SYSTEM_LANGUAGE
            }
    }
}

internal enum class NativeSubtitleLanguage(val preferredLanguages: List<String>) {
    SIMPLIFIED_CHINESE(listOf("zh-cn")),
    TRADITIONAL_CHINESE(listOf("zh-tw")),
    ENGLISH(listOf("en")),
    JAPANESE(listOf("ja")),
    SYSTEM_LANGUAGE(emptyList());

    fun resolveLanguages(systemLanguage: String): List<String> =
        preferredLanguages.ifEmpty { listOf(systemLanguage) }

    companion object {
        fun fromRaw(raw: String, fallback: NativeSubtitleLanguage): NativeSubtitleLanguage =
            when (raw.trim()) {
                "simplifiedChinese" -> SIMPLIFIED_CHINESE
                "traditionalChinese" -> TRADITIONAL_CHINESE
                "english" -> ENGLISH
                "japanese" -> JAPANESE
                "systemLanguage" -> SYSTEM_LANGUAGE
                else -> fallback
            }
    }
}
