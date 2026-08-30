package com.example.starflow

import java.util.Locale

object NativeSubtitleTrackLabelPolicy {
    fun format(
        title: String,
        language: String,
        isDefault: Boolean,
        isForced: Boolean,
        isExternal: Boolean = false,
        fallbackIndex: Int,
    ): String {
        val resolvedTitle = title.trim()
        val resolvedLanguage = normalizeLanguageLabel(language)
        val parts = mutableListOf<String>()

        if (resolvedTitle.isNotEmpty()) {
            parts += resolvedTitle
        }
        if (resolvedLanguage.isNotEmpty() &&
            !resolvedLanguage.equals(resolvedTitle, ignoreCase = true)
        ) {
            parts += resolvedLanguage
        }
        if (isDefault && !isExternal && !containsDefaultMarker(resolvedTitle)) {
            parts += "默认"
        }
        if (isForced && !containsForcedMarker(resolvedTitle)) {
            parts += "强制"
        }

        return if (parts.isEmpty()) {
            "字幕 ${fallbackIndex.coerceAtLeast(1)}"
        } else {
            parts.joinToString(" · ")
        }
    }

    private fun normalizeLanguageLabel(raw: String): String {
        val normalized = raw.trim().replace('_', '-')
        if (normalized.isEmpty() ||
            normalized.equals("und", ignoreCase = true) ||
            normalized.equals("zxx", ignoreCase = true)
        ) {
            return ""
        }
        return normalized.uppercase(Locale.ROOT)
    }

    private fun containsDefaultMarker(title: String): Boolean {
        val normalized = normalizeMarkerText(title)
        return normalized.contains("default") || normalized.contains("默认")
    }

    private fun containsForcedMarker(title: String): Boolean {
        val normalized = normalizeMarkerText(title)
        return normalized.contains("forced") ||
            normalized.contains("force") ||
            normalized.contains("强制") ||
            normalized.contains("強制")
    }

    private fun normalizeMarkerText(value: String): String =
        value.trim().lowercase(Locale.ROOT).replace(Regex("[^\\p{L}\\p{N}]+"), "")
}
