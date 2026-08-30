package com.example.starflow

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeDualSubtitleTrackPolicyTest {
    @Test
    fun `accepts text subtitles and rejects image subtitles`() {
        assertTrue(
            NativeDualSubtitleTrackPolicy.isCompatibleTextSubtitle(
                "application/x-subrip",
            ),
        )
        assertTrue(
            NativeDualSubtitleTrackPolicy.isCompatibleTextSubtitle(
                "text/x-ssa",
            ),
        )
        assertFalse(
            NativeDualSubtitleTrackPolicy.isCompatibleTextSubtitle(
                "application/pgs",
            ),
        )
        assertFalse(
            NativeDualSubtitleTrackPolicy.isCompatibleTextSubtitle(
                sampleMimeType = "application/x-media3-cues",
                codecs = "application/vobsub",
            ),
        )
    }

    @Test
    fun `recognizes Chinese and English subtitle metadata`() {
        assertTrue(
            NativeDualSubtitleTrackPolicy.isLikelyChinese(
                language = "zh-CN",
                label = "简体中文",
            ),
        )
        assertTrue(
            NativeDualSubtitleTrackPolicy.isLikelyEnglish(
                language = "eng",
                label = "English SDH",
            ),
        )
    }

    @Test
    fun `routes the selected English group to the secondary renderer`() {
        val primary = NativeSubtitleFormatKey("1", "中文", "zh", "text/x-ssa", "", -1)
        val secondary = NativeSubtitleFormatKey("2", "English", "en", "text/x-ssa", "", -1)

        assertTrue(
            NativeDualSubtitleTrackPolicy.routesToPrimary(
                primary,
                setOf(secondary),
            ),
        )
        assertFalse(
            NativeDualSubtitleTrackPolicy.routesToPrimary(
                secondary,
                setOf(secondary),
            ),
        )
        assertTrue(
            NativeDualSubtitleTrackPolicy.routesToSecondary(
                secondary,
                secondary,
            ),
        )
    }

    @Test
    fun `uses a smaller default English subtitle scale`() {
        assertTrue(NativeDualSubtitleLayoutPolicy.SECONDARY_TEXT_SCALE == 0.50f)
    }
}
