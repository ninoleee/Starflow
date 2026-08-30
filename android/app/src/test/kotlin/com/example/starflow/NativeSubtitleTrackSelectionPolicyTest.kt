package com.example.starflow

import org.junit.Assert.assertEquals
import org.junit.Test

class NativeSubtitleTrackSelectionPolicyTest {
    @Test
    fun `selects preferred language before forced and default tracks`() {
        val candidates = listOf(
            NativeSubtitleTrackCandidate("default", language = "fr", isDefault = true),
            NativeSubtitleTrackCandidate("forced", language = "ja", isForced = true),
            NativeSubtitleTrackCandidate("preferred", language = "en"),
        )

        assertEquals(
            "preferred",
            NativeSubtitleTrackSelectionPolicy.select(candidates, listOf("en")),
        )
    }

    @Test
    fun `falls back from forced track to source default track`() {
        val defaultTrack = NativeSubtitleTrackCandidate(
            "default",
            language = "fr",
            isDefault = true,
        )
        val forcedTrack = NativeSubtitleTrackCandidate(
            "forced",
            label = "Japanese Forced",
        )

        assertEquals(
            "forced",
            NativeSubtitleTrackSelectionPolicy.select(
                listOf(defaultTrack, forcedTrack),
                listOf("en"),
            ),
        )
        assertEquals(
            "default",
            NativeSubtitleTrackSelectionPolicy.select(
                listOf(defaultTrack),
                listOf("en"),
            ),
        )
    }

    @Test
    fun `missing configured language falls back to system language`() {
        val candidates = listOf(
            NativeSubtitleTrackCandidate("english", language = "en"),
            NativeSubtitleTrackCandidate("japanese", language = "ja"),
        )

        assertEquals(
            "japanese",
            NativeSubtitleTrackSelectionPolicy.selectWithSystemFallback(
                candidates = candidates,
                preferredLanguages = listOf("ko"),
                systemLanguage = "ja-JP",
            ),
        )
    }

    @Test
    fun `recognizes common subtitle language aliases`() {
        val candidates = listOf(
            NativeSubtitleTrackCandidate("simplified", language = "chs"),
            NativeSubtitleTrackCandidate("traditional", label = "繁中"),
            NativeSubtitleTrackCandidate("english", language = "eng"),
            NativeSubtitleTrackCandidate("japanese", language = "jp"),
        )

        assertEquals(
            "simplified",
            NativeSubtitleTrackSelectionPolicy.selectLanguage(candidates, listOf("zh-cn")),
        )
        assertEquals(
            "traditional",
            NativeSubtitleTrackSelectionPolicy.selectLanguage(candidates, listOf("zh-tw")),
        )
        assertEquals(
            "english",
            NativeSubtitleTrackSelectionPolicy.selectLanguage(candidates, listOf("en")),
        )
        assertEquals(
            "japanese",
            NativeSubtitleTrackSelectionPolicy.selectLanguage(candidates, listOf("ja")),
        )
    }
}
