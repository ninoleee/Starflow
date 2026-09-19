package com.example.starflow

import android.graphics.Bitmap
import android.text.Layout
import androidx.media3.common.text.Cue
import androidx.media3.common.text.CueGroup
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test
import org.mockito.Mockito.mock

class NativeSubtitlePositionPolicyTest {
    @Test
    fun `position and padding reach the bottom without a five percent dead zone`() {
        for (percent in 50..100) {
            assertEquals(percent / 100f, NativeSubtitlePositionPolicy.positionFraction(percent.toDouble(), 80.0), 0.0001f)
            assertEquals((100 - percent) / 100f, NativeSubtitlePositionPolicy.bottomPaddingFraction(percent.toDouble()), 0.0001f)
        }
        assertEquals(1f, NativeSubtitlePositionPolicy.positionFraction(100.0, 90.0), 0f)
        assertEquals(0f, NativeSubtitlePositionPolicy.bottomPaddingFraction(100.0), 0f)
    }

    @Test
    fun `invalid positions use role defaults and finite positions stay within bounds`() {
        assertEquals(0.8f, NativeSubtitlePositionPolicy.positionFraction(Double.NaN, 80.0), 0f)
        assertEquals(0.9f, NativeSubtitlePositionPolicy.positionFraction(Double.POSITIVE_INFINITY, 90.0), 0f)
        assertEquals(0.5f, NativeSubtitlePositionPolicy.positionFraction(-10.0, 80.0), 0f)
        assertEquals(1f, NativeSubtitlePositionPolicy.positionFraction(110.0, 90.0), 0f)
    }

    @Test
    fun `single text cues use application padding without changing horizontal styling or timing`() {
        for (lineType in listOf(Cue.LINE_TYPE_FRACTION, Cue.LINE_TYPE_NUMBER)) {
            val cue = Cue.Builder()
                .setText("First line\nSecond line")
                .setTextAlignment(Layout.Alignment.ALIGN_CENTER)
                .setLine(0.8f, lineType)
                .setLineAnchor(Cue.ANCHOR_TYPE_END)
                .setPosition(0.4f)
                .setPositionAnchor(Cue.ANCHOR_TYPE_MIDDLE)
                .setSize(0.7f)
                .setWindowColor(0x12345678)
                .build()
            val group = NativeSubtitlePositionPolicy.applyPrimaryPosition(CueGroup(listOf(cue), 123L))
            val positioned = group.cues.single()
            assertEquals(123L, group.presentationTimeUs)
            assertEquals(Cue.DIMEN_UNSET, positioned.line, 0f)
            assertEquals(Cue.TYPE_UNSET, positioned.lineType)
            assertEquals(Cue.TYPE_UNSET, positioned.lineAnchor)
            assertEquals(cue.text, positioned.text)
            assertEquals(cue.textAlignment, positioned.textAlignment)
            assertEquals(cue.position, positioned.position, 0f)
            assertEquals(cue.positionAnchor, positioned.positionAnchor)
            assertEquals(cue.size, positioned.size, 0f)
            assertEquals(cue.windowColor, positioned.windowColor)
            assertEquals(0.8f, cue.line, 0f)
        }
    }

    @Test
    fun `bitmap cues retain authored geometry and empty groups still clear subtitles`() {
        val cue = Cue.Builder().setBitmap(mock(Bitmap::class.java))
            .setLine(0.9f, Cue.LINE_TYPE_FRACTION)
            .setLineAnchor(Cue.ANCHOR_TYPE_END)
            .build()
        assertSame(cue, NativeSubtitlePositionPolicy.applyPrimaryPosition(CueGroup(listOf(cue), 0L)).cues.single())
        assertEquals(0, NativeSubtitlePositionPolicy.applyPrimaryPosition(CueGroup.EMPTY_TIME_ZERO).cues.size)
    }
}
