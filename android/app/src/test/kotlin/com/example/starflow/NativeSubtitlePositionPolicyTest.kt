package com.example.starflow

import org.junit.Assert.assertEquals
import org.junit.Test

class NativeSubtitlePositionPolicyTest {
    @Test
    fun `offers five percent playback options from 50 through 100`() {
        assertEquals(11, NativeSubtitlePositionPolicy.options.size)
        assertEquals(50.0, NativeSubtitlePositionPolicy.options.first(), 0.0)
        assertEquals(100.0, NativeSubtitlePositionPolicy.options.last(), 0.0)
        NativeSubtitlePositionPolicy.options.zipWithNext { left, right ->
            assertEquals(5.0, right - left, 0.0)
        }
    }
}
