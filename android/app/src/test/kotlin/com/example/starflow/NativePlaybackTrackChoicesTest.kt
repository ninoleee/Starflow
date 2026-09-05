package com.example.starflow

import androidx.media3.common.TrackSelectionOverride
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.mock

class NativePlaybackTrackChoicesTest {
    private fun choice(
        id: String,
        language: String,
        mime: String = "text/x-ssa",
    ): NativeTrackChoice {
        val key = NativeSubtitleFormatKey(id, language, language, mime, "", -1)
        return NativeTrackChoice(
            label = language,
            override = mock(TrackSelectionOverride::class.java),
            selected = false,
            formatKey = key,
            groupFormatKeys = setOf(key),
            language = language,
            sourceLabel = language,
            sampleMimeType = mime,
        )
    }

    @Test
    fun defaultDualSelectionUsesIndependentGroups() {
        val primary = choice("1", "zh-CN")
        val secondary = choice("2", "en")
        val result =
            NativePlaybackTrackChoices.buildDefaultNativeDualSubtitleChoice(
                listOf(primary, secondary),
                NativeSubtitleLanguage.SIMPLIFIED_CHINESE,
                NativeSubtitleLanguage.ENGLISH,
            )
        assertEquals(primary, result?.primary)
        assertEquals(secondary, result?.secondary)
    }

    @Test
    fun rejectsExternalImageAndSharedGroupSecondary() {
        val primary = choice("1", "zh-CN")
        val secondary = choice("2", "en")
        val preference =
            NativeSubtitleSessionPreference(
                NativeSubtitleSessionMode.DUAL,
                primary.subtitleFingerprint,
                secondary.subtitleFingerprint,
            )
        for (invalid in
            listOf(
                secondary.copy(isExternal = true),
                choice("2", "en", "application/pgs"),
                secondary.copy(groupFormatKeys = setOf(primary.formatKey!!, secondary.formatKey!!)),
            )) {
            assertNull(
                NativePlaybackTrackChoices.restoreNativeDualSubtitleChoice(
                    listOf(primary, invalid),
                    preference,
                )
            )
        }
    }

    @Test
    fun restoresNewEpisodeTracksByFingerprintNotOldOverride() {
        val primary = choice("new-primary", "zh-CN")
        val secondary = choice("new-secondary", "en")
        val preference =
            NativeSubtitleSessionPreference(
                NativeSubtitleSessionMode.DUAL,
                primary.subtitleFingerprint.copy(id = "old-primary"),
                secondary.subtitleFingerprint.copy(id = "old-secondary"),
            )
        val result =
            NativePlaybackTrackChoices.restoreNativeDualSubtitleChoice(
                listOf(secondary, primary),
                preference,
            )
        assertSame(primary.override, result?.primary?.override)
        assertSame(secondary.override, result?.secondary?.override)
    }
}
