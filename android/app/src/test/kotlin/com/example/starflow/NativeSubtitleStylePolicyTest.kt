package com.example.starflow

import org.junit.Assert.assertEquals
import org.junit.Test

class NativeSubtitleStylePolicyTest {
    @Test
    fun `default size uses Media3 readable fraction and TV safe area`() {
        val config = NativeSubtitleStylePolicy.resolve(
            rawScale = NativeSubtitleStylePolicy.DEFAULT_SCALE,
            isTelevision = true,
        )

        assertEquals(0.0533f, config.textSizeFraction, 0.0001f)
        assertEquals(0.08f, config.bottomPaddingFraction, 0.0001f)
    }

    @Test
    fun `phone uses larger bottom safe area`() {
        val config = NativeSubtitleStylePolicy.resolve(
            rawScale = NativeSubtitleStylePolicy.DEFAULT_SCALE,
            isTelevision = false,
        )

        assertEquals(0.10f, config.bottomPaddingFraction, 0.0001f)
    }

    @Test
    fun `configured size remains within readable fractional bounds`() {
        val smallest = NativeSubtitleStylePolicy.resolve(-100.0, true)
        val largest = NativeSubtitleStylePolicy.resolve(1_000.0, true)

        assertEquals(0.035f, smallest.textSizeFraction, 0.0001f)
        assertEquals(0.09f, largest.textSizeFraction, 0.0001f)
    }
}
