package com.example.starflow

import org.junit.Assert.assertEquals
import org.junit.Test

class NativeEpisodePickerNavigationTest {
    @Test fun `horizontal movement stops at row and range edges`() {
        assertEquals(3, episodePickerNeighbor(3, 65, true, 1))
        assertEquals(4, episodePickerNeighbor(4, 65, true, -1))
        assertEquals(29, episodePickerNeighbor(29, 65, true, 1))
        assertEquals(30, episodePickerNeighbor(30, 65, true, -1))
    }

    @Test fun `vertical movement crosses ranges using local columns`() {
        assertEquals(33, episodePickerNeighbor(27, 65, true, 4))
        assertEquals(31, episodePickerNeighbor(29, 65, true, 4))
        assertEquals(29, episodePickerNeighbor(33, 65, true, -4))
        assertEquals(28, episodePickerNeighbor(30, 65, true, -4))
    }

    @Test fun `partial final row clamps before leaving for footer`() {
        assertEquals(64, episodePickerNeighbor(63, 65, true, 4))
        assertEquals(65, episodePickerNeighbor(64, 65, true, 4))
        assertEquals(-4, episodePickerNeighbor(0, 65, true, -4))
    }

    @Test fun `list navigation keeps adjacent episodes across ranges`() {
        assertEquals(30, episodePickerNeighbor(29, 65, false, 1))
        assertEquals(29, episodePickerNeighbor(30, 65, false, -1))
    }
}
