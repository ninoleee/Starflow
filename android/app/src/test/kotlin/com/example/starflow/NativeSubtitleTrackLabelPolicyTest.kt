package com.example.starflow

import org.junit.Assert.assertEquals
import org.junit.Test

class NativeSubtitleTrackLabelPolicyTest {
    @Test
    fun `formats subtitle title language and flags like mpv`() {
        assertEquals(
            "简英双语 · ZH-CN · 默认",
            NativeSubtitleTrackLabelPolicy.format(
                title = "简英双语",
                language = "zh-CN",
                isDefault = true,
                isForced = false,
                fallbackIndex = 1,
            ),
        )
    }

    @Test
    fun `keeps forced marker without repeating it`() {
        assertEquals(
            "English Forced · EN",
            NativeSubtitleTrackLabelPolicy.format(
                title = "English Forced",
                language = "en",
                isDefault = false,
                isForced = true,
                fallbackIndex = 2,
            ),
        )
    }

    @Test
    fun `uses external subtitle filename without undefined language`() {
        assertEquals(
            "movie.zh-Hans.srt",
            NativeSubtitleTrackLabelPolicy.format(
                title = "movie.zh-Hans.srt",
                language = "und",
                isDefault = true,
                isForced = false,
                isExternal = true,
                fallbackIndex = 3,
            ),
        )
    }

    @Test
    fun `falls back to a stable subtitle index`() {
        assertEquals(
            "字幕 4",
            NativeSubtitleTrackLabelPolicy.format(
                title = "",
                language = "zxx",
                isDefault = false,
                isForced = false,
                fallbackIndex = 4,
            ),
        )
    }
}
