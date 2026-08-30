package com.example.starflow

import java.util.Locale

enum class NativeSubtitleSessionMode {
    OFF,
    SINGLE,
    DUAL,
}

data class NativeSubtitleTrackFingerprint(
    val id: String = "",
    val label: String = "",
    val language: String = "",
    val sampleMimeType: String = "",
    val codecs: String = "",
    val isDefault: Boolean = false,
    val isForced: Boolean = false,
    val accessibilityChannel: Int = -1,
)

data class NativeSubtitleSessionPreference(
    val mode: NativeSubtitleSessionMode,
    val primary: NativeSubtitleTrackFingerprint? = null,
    val secondary: NativeSubtitleTrackFingerprint? = null,
)

data class NativeSubtitleRestoreCandidate<T>(
    val value: T,
    val fingerprint: NativeSubtitleTrackFingerprint,
)

object NativeSubtitleSessionPreferencePolicy {
    fun <T> match(
        candidates: Iterable<NativeSubtitleRestoreCandidate<T>>,
        fingerprint: NativeSubtitleTrackFingerprint,
        excludedValues: Set<T> = emptySet(),
    ): T? {
        var selected: T? = null
        var selectedScore = 0
        candidates.forEach { candidate ->
            if (candidate.value in excludedValues) {
                return@forEach
            }
            val score = score(candidate.fingerprint, fingerprint)
            if (score > selectedScore) {
                selected = candidate.value
                selectedScore = score
            }
        }
        return selected.takeIf { selectedScore >= MIN_MATCH_SCORE }
    }

    private fun score(
        candidate: NativeSubtitleTrackFingerprint,
        preferred: NativeSubtitleTrackFingerprint,
    ): Int {
        val candidateLanguage = canonicalLanguage(candidate.language)
        val preferredLanguage = canonicalLanguage(preferred.language)
        val candidateLabel = normalizeText(candidate.label)
        val preferredLabel = normalizeText(preferred.label)
        var score = 0

        if (candidateLanguage.isNotEmpty() && preferredLanguage.isNotEmpty()) {
            score += when {
                candidateLanguage == preferredLanguage -> 120
                candidateLanguage.substringBefore('-') == preferredLanguage.substringBefore('-') -> 72
                else -> -200
            }
        }
        if (candidateLabel.isNotEmpty() && preferredLabel.isNotEmpty()) {
            score += when {
                candidateLabel == preferredLabel -> 100
                candidateLabel.contains(preferredLabel) || preferredLabel.contains(candidateLabel) -> 54
                else -> 0
            }
        }
        if (preferred.id.isNotEmpty() && candidate.id == preferred.id) {
            score += 36
        }
        if (candidate.sampleMimeType.isNotEmpty() &&
            candidate.sampleMimeType.equals(preferred.sampleMimeType, ignoreCase = true)
        ) {
            score += 14
        }
        if (candidate.codecs.isNotEmpty() &&
            candidate.codecs.equals(preferred.codecs, ignoreCase = true)
        ) {
            score += 8
        }
        if (candidate.isDefault == preferred.isDefault) {
            score += 5
        }
        if (candidate.isForced == preferred.isForced) {
            score += 5
        }
        if (candidate.accessibilityChannel == preferred.accessibilityChannel) {
            score += 3
        }
        return score
    }

    private fun canonicalLanguage(raw: String): String {
        val normalized = raw.trim().lowercase(Locale.ROOT).replace('_', '-')
        return when (normalized) {
            "und", "zxx", "null", "unknown" -> ""
            "english", "eng" -> "en"
            "japanese", "jpn" -> "ja"
            "korean", "kor" -> "ko"
            "chinese", "chi", "zho" -> "zh"
            "zh-hans", "zh-sg" -> "zh-cn"
            "zh-hant", "zh-hk", "zh-mo" -> "zh-tw"
            else -> normalized
        }
    }

    private fun normalizeText(raw: String): String =
        raw.trim().lowercase(Locale.ROOT).replace(Regex("[^\\p{L}\\p{N}]+"), "")

    private const val MIN_MATCH_SCORE = 30
}
