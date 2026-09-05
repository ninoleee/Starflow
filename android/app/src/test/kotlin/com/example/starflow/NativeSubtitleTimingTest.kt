package com.example.starflow

import androidx.media3.common.MimeTypes
import org.junit.Assert.assertEquals
import org.junit.Test

class NativeSubtitleTimingTest {
    @Test
    fun srtNegativeDelayClampsAndPreservesText() {
        val source = "1\n00:00:01,000 --> 00:00:02,500\nHello\n"
        assertEquals(
            "1\n00:00:00,000 --> 00:00:00,500\nHello\n",
            NativeSubtitleTiming.shiftSubtitleContent(source, MimeTypes.APPLICATION_SUBRIP, -2_000L),
        )
    }

    @Test
    fun srtPositiveDelayCrossesHourBoundary() {
        assertEquals(
            "01:00:00,500 --> 01:00:01,500",
            NativeSubtitleTiming.shiftSubtitleContent(
                "00:59:59,500 --> 01:00:00,500",
                MimeTypes.APPLICATION_SUBRIP,
                1_000L,
            ),
        )
    }

    @Test
    fun vttPreservesCueSettings() {
        val source = "WEBVTT\n\n00:01.000 --> 00:03.000 align:start position:10%\nText"
        assertEquals(
            "WEBVTT\n\n00:01.500 --> 00:03.500 align:start position:10%\nText",
            NativeSubtitleTiming.shiftSubtitleContent(source, MimeTypes.TEXT_VTT, 500L),
        )
    }

    @Test
    fun assPreservesStyleAndCommas() {
        val source = "[Events]\nDialogue: 0,0:00:01.00,0:00:03.25,Default,,0,0,0,,Hello, world"
        assertEquals(
            "[Events]\nDialogue: 0,0:00:00.00,0:00:01.25,Default,,0,0,0,,Hello, world",
            NativeSubtitleTiming.shiftSubtitleContent(source, MimeTypes.TEXT_SSA, -2_000L),
        )
    }

    @Test
    fun unknownFormatIsUntouched() {
        assertEquals("raw", NativeSubtitleTiming.shiftSubtitleContent("raw", "unknown", 5_000L))
    }
}
