package com.example.starflow

import org.junit.Assert.assertEquals
import org.junit.Test

class NativePlaybackTargetTest {
    @Test
    fun episodeTitlesAndSearchQuery() {
        val target =
            NativePlaybackTarget { "Episode" }
                .apply {
                    playbackTargetJson =
                        """{"itemType":"episode","title":"Episode","seriesTitle":"Series","seasonNumber":2,"episodeNumber":3,"year":2026}"""
                }
        assertEquals("Series", target.buildPlaybackPagePrimaryTitle())
        assertEquals("Episode · S02E03", target.buildSystemSessionTitle())
        assertEquals("Series S02E03", target.buildSubtitleSearchQuery())
    }

    @Test
    fun titleProviderIsReadAfterMediaReplacement() {
        var title = "First"
        val target = NativePlaybackTarget { title }
        assertEquals("First", target.buildPlaybackPagePrimaryTitle())
        title = "Next"
        assertEquals("Next", target.buildPlaybackPagePrimaryTitle())
        title = " "
        target.playbackTargetJson = "invalid"
        assertEquals("Starflow", target.buildPlaybackPagePrimaryTitle())
        assertEquals("", target.buildSubtitleSearchQuery())
    }
}
