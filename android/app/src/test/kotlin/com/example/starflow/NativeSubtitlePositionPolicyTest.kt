package com.example.starflow

import org.junit.Assert.assertEquals
import org.junit.Test

class NativeSubtitlePositionPolicyTest {
    @Test
    fun `offers every one percent position from 50 through 95`() {
        assertEquals(46, NativeSubtitlePositionPolicy.options.size)
        assertEquals(50.0, NativeSubtitlePositionPolicy.options.first(), 0.0)
        assertEquals(95.0, NativeSubtitlePositionPolicy.options.last(), 0.0)
        NativeSubtitlePositionPolicy.options.zipWithNext { left, right ->
            assertEquals(1.0, right - left, 0.0)
        }
    }
}
