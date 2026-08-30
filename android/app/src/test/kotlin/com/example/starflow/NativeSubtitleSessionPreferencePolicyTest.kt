package com.example.starflow

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NativeSubtitleSessionPreferencePolicyTest {
    @Test
    fun `matches selected language when track ids change between episodes`() {
        val candidates = listOf(
            candidate("3", id = "3", label = "English", language = "en"),
            candidate("8", id = "8", label = "简体中文", language = "zh-CN"),
        )

        val selected = NativeSubtitleSessionPreferencePolicy.match(
            candidates,
            NativeSubtitleTrackFingerprint(
                id = "3",
                label = "简体中文",
                language = "zh-CN",
            ),
        )

        assertEquals("8", selected)
    }

    @Test
    fun `matches primary and secondary preferences independently`() {
        val candidates = listOf(
            candidate("zh", id = "6", label = "中文", language = "zh"),
            candidate("en", id = "7", label = "English", language = "en"),
        )
        val primary = NativeSubtitleSessionPreferencePolicy.match(
            candidates,
            NativeSubtitleTrackFingerprint(label = "简体中文", language = "zh-CN"),
        )
        val secondary = NativeSubtitleSessionPreferencePolicy.match(
            candidates,
            NativeSubtitleTrackFingerprint(label = "English SDH", language = "en"),
            excludedValues = setOfNotNull(primary),
        )

        assertEquals("zh", primary)
        assertEquals("en", secondary)
    }

    @Test
    fun `does not match unrelated subtitle by codec alone`() {
        val selected = NativeSubtitleSessionPreferencePolicy.match(
            listOf(
                candidate(
                    value = "en",
                    id = "9",
                    label = "English",
                    language = "en",
                    sampleMimeType = "text/x-ssa",
                ),
            ),
            NativeSubtitleTrackFingerprint(
                id = "4",
                label = "日本語",
                language = "ja",
                sampleMimeType = "text/x-ssa",
            ),
        )

        assertNull(selected)
    }

    @Test
    fun `does not reuse stable id when subtitle language changed`() {
        val selected = NativeSubtitleSessionPreferencePolicy.match(
            listOf(
                candidate(
                    value = "en",
                    id = "4",
                    label = "English",
                    language = "en",
                ),
            ),
            NativeSubtitleTrackFingerprint(
                id = "4",
                label = "日本語",
                language = "ja",
                sampleMimeType = "text/x-ssa",
            ),
        )

        assertNull(selected)
    }

    @Test
    fun `uses label when next episode language is unknown`() {
        val selected = NativeSubtitleSessionPreferencePolicy.match(
            listOf(
                candidate("en", id = "5", label = "English", language = "und"),
                candidate("zh", id = "6", label = "简体中文", language = "und"),
            ),
            NativeSubtitleTrackFingerprint(
                id = "1",
                label = "简体中文",
                language = "zh-CN",
            ),
        )

        assertEquals("zh", selected)
    }

    private fun candidate(
        value: String,
        id: String,
        label: String,
        language: String,
        sampleMimeType: String = "text/x-ssa",
    ): NativeSubtitleRestoreCandidate<String> {
        return NativeSubtitleRestoreCandidate(
            value = value,
            fingerprint = NativeSubtitleTrackFingerprint(
                id = id,
                label = label,
                language = language,
                sampleMimeType = sampleMimeType,
            ),
        )
    }
}
