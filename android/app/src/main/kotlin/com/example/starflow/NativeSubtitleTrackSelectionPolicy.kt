package com.example.starflow

import java.util.Locale

data class NativeSubtitleTrackCandidate<T>(
    val value: T,
    val language: String = "",
    val label: String = "",
    val isForced: Boolean = false,
    val isDefault: Boolean = false,
)

object NativeSubtitleTrackSelectionPolicy {
    fun <T> select(
        candidates: Iterable<NativeSubtitleTrackCandidate<T>>,
        preferredLanguages: List<String>,
    ): T? {
        var selected: NativeSubtitleTrackCandidate<T>? = null
        var selectedPriority = 0
        var selectedLanguageScore = 0

        candidates.forEach { candidate ->
            val languageScore = languageScore(candidate, preferredLanguages)
            val priority = when {
                languageScore > 0 -> 3
                candidate.isForced || isForcedLabel(candidate.label) -> 2
                candidate.isDefault -> 1
                else -> 0
            }
            if (priority > selectedPriority ||
                (priority == selectedPriority && languageScore > selectedLanguageScore)
            ) {
                selected = candidate
                selectedPriority = priority
                selectedLanguageScore = languageScore
            }
        }
        return selected?.value
    }

    fun <T> selectWithSystemFallback(
        candidates: Iterable<NativeSubtitleTrackCandidate<T>>,
        preferredLanguages: List<String>,
        systemLanguage: String,
    ): T? {
        val snapshot = candidates.toList()
        val preferred = selectLanguage(snapshot, preferredLanguages)
        if (preferred != null) {
            return preferred
        }
        val system = selectLanguage(snapshot, listOf(systemLanguage))
        if (system != null) {
            return system
        }
        return select(snapshot, emptyList())
    }

    fun <T> selectLanguage(
        candidates: Iterable<NativeSubtitleTrackCandidate<T>>,
        preferredLanguages: List<String>,
    ): T? {
        var selected: NativeSubtitleTrackCandidate<T>? = null
        var selectedScore = 0
        candidates.forEach { candidate ->
            val score = languageScore(candidate, preferredLanguages)
            if (score > selectedScore) {
                selected = candidate
                selectedScore = score
            }
        }
        return selected?.value
    }

    private fun <T> languageScore(
        candidate: NativeSubtitleTrackCandidate<T>,
        preferredLanguages: List<String>,
    ): Int {
        val language = canonicalLanguage(candidate.language)
        val searchable = normalizeText("${candidate.language} ${candidate.label}")
        preferredLanguages.forEachIndexed { index, rawPreference ->
            val preference = canonicalLanguage(rawPreference)
            if (preference.isEmpty()) {
                return@forEachIndexed
            }
            val match = languageMatches(language, preference) ||
                subtitleLanguageTokens(preference).any { containsToken(searchable, it) }
            if (match) {
                return (preferredLanguages.size - index).coerceAtLeast(1)
            }
        }
        return 0
    }

    private fun canonicalLanguage(raw: String): String {
        val normalized = raw.trim().lowercase(Locale.ROOT).replace('_', '-')
        return when (normalized) {
            "english", "eng", "英语", "英語", "英文", "英字" -> "en"
            "japanese", "jp", "jpn", "日语", "日語", "日文", "日字", "日本語" -> "ja"
            "korean", "kr", "kor", "韩语", "韓語", "韩文", "韓文" -> "ko"
            "chinese", "ch", "chi", "zho", "中文" -> "zh"
            "zh-hans", "zh-sg", "chs", "chn", "cn", "sc", "gb", "简中", "简体", "簡體" -> "zh-cn"
            "zh-hant", "zh-hk", "zh-mo", "cht", "tc", "big5", "繁中", "繁体", "繁體" -> "zh-tw"
            else -> normalized
        }
    }

    private fun languageMatches(language: String, preference: String): Boolean {
        if (language.isEmpty()) {
            return false
        }
        if (language == preference) {
            return true
        }
        val languageRoot = language.substringBefore('-')
        val preferenceRoot = preference.substringBefore('-')
        return languageRoot == preferenceRoot &&
            (languageRoot != "zh" || language == "zh" || preference == "zh")
    }

    private fun subtitleLanguageTokens(language: String): List<String> = when (language) {
        "zh-cn" -> listOf("zh cn", "zh hans", "zhcn", "zhhans", "chs", "chn", "chi", "zho", "cn", "sc", "简体", "簡體", "简中")
        "zh-tw" -> listOf("zh tw", "zh hant", "zhtw", "zhhant", "cht", "chi", "zho", "tc", "big5", "繁体", "繁體", "繁中")
        "zh" -> listOf("chinese", "中文", "国语", "國語")
        "en" -> listOf("en", "english", "eng", "英语", "英語", "英文", "英字", "中英")
        "ja" -> listOf("ja", "japanese", "jp", "jpn", "日语", "日語", "日文", "日字", "日本語")
        "ko" -> listOf("ko", "korean", "kr", "kor", "韩语", "韓語", "한국어")
        else -> listOf(language.replace("-", ""))
    }

    private fun isForcedLabel(label: String): Boolean {
        val normalized = normalizeText(label)
        return listOf(
            "forced",
            "force",
            "signs",
            "强制",
            "強制",
            "强迫",
            "仅外语",
            "僅外語",
            "外语对白",
            "外語對白",
        ).any { containsToken(normalized, it) }
    }

    private fun containsToken(text: String, token: String): Boolean =
        if (token.all { it.code < 128 }) {
            text.contains(" ${normalizeText(token).trim()} ")
        } else text.contains(token)

    private fun normalizeText(raw: String): String =
        " ${raw.trim().lowercase(Locale.ROOT).replace(Regex("[^\\p{L}\\p{N}]+"), " ")} "
}
