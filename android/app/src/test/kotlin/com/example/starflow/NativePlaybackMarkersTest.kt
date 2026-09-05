package com.example.starflow

import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Test

class NativePlaybackMarkersTest {
    @Test
    fun sortsDeduplicatesAndFiltersBoundaries() {
        val target =
            JSONObject(
                """{"chapterTimesMs":[0,3000,"2000",10000,-1],"chapters":[{"startSeconds":3},{"startMs":4000}]}"""
            )
        val skip = JSONObject("""{"enabled":true,"introDurationMs":2000,"outroDurationMs":1000}""")
        assertArrayEquals(
            longArrayOf(2000, 3000, 4000, 9000),
            NativePlaybackMarkers.buildPlaybackMarkerPositionsMs(10_000L, target, skip),
        )
    }

    @Test
    fun disabledSkipAndUnknownDuration() {
        val target =
            JSONObject(
                """{"chapterPositionsMs":[1000],"chapterStartTimesMs":[2000],"chapterMarkersMs":[3000]}"""
            )
        val skip = JSONObject("""{"enabled":false,"introDurationMs":4000}""")
        assertArrayEquals(
            longArrayOf(1000, 2000, 3000),
            NativePlaybackMarkers.buildPlaybackMarkerPositionsMs(10_000L, target, skip),
        )
        assertArrayEquals(
            longArrayOf(),
            NativePlaybackMarkers.buildPlaybackMarkerPositionsMs(0L, target, skip),
        )
    }

    @Test
    fun millisecondsTakePrecedenceOverSeconds() {
        val target =
            JSONObject(
                """{"chapters":[{"timeMs":1500,"startSeconds":9},{"positionSeconds":2},{"timeSeconds":3},{"startPositionMs":4000},{"positionMs":5000},"invalid",null]}"""
            )
        assertArrayEquals(
            longArrayOf(1500, 2000, 3000, 4000, 5000),
            NativePlaybackMarkers.buildPlaybackMarkerPositionsMs(10_000L, target, null),
        )
    }
}
