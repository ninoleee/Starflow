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

    @Test fun `partial final row clamps and stops at the bottom`() {
        assertEquals(64, episodePickerNeighbor(63, 65, true, 4))
        assertEquals(64, episodePickerNeighbor(64, 65, true, 4))
        assertEquals(-4, episodePickerNeighbor(0, 65, true, -4))
    }

    @Test fun `season end stops downward in both layouts`() {
        for (count in listOf(1, 30, 64, 65)) {
            assertEquals(count - 1, episodePickerNeighbor(count - 1, count, false, 1))
            val pageStart = (count - 1) / 30 * 30
            val rowStart = pageStart + (count - 1 - pageStart) / 4 * 4
            for (index in rowStart until count) {
                assertEquals(index, episodePickerNeighbor(index, count, true, 4))
            }
        }
    }

    @Test fun `list navigation keeps adjacent episodes across ranges`() {
        assertEquals(30, episodePickerNeighbor(29, 65, false, 1))
        assertEquals(29, episodePickerNeighbor(30, 65, false, -1))
    }

    @Test fun `only the first overall row exits upward for season selection`() {
        assertEquals(-1, episodePickerNeighbor(0, 65, false, -1))
        for (column in 0..3) {
            assertEquals(column - 4, episodePickerNeighbor(column, 65, true, -4))
            assertEquals(column, episodePickerNeighbor(4 + column, 65, true, -4))
            assertEquals(28 + minOf(column, 1), episodePickerNeighbor(30 + column, 65, true, -4))
        }
    }
}
