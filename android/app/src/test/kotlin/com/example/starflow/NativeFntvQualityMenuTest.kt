package com.example.starflow

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class NativeFntvQualityMenuTest {
    private val qualities = listOf(
        JSONObject("""{"index":0,"resolution":"原画"}"""),
        JSONObject("""{"index":-1,"resolution":"2160","bitrate":20000000}"""),
        JSONObject("""{"index":-2,"resolution":"1080","bitrate":8000000}"""),
        JSONObject("""{"index":-3,"resolution":"1080P","bitrate":4000000}"""),
        JSONObject("""{"index":-4,"resolution":"720","bitrate":2000000}"""),
    )
    @Test fun groupsResolutionsAndRetainsFirstServerBitrate() {
        val presets = NativeFntvQualityMenu.presets(qualities, 0)
        assertEquals(listOf("原画", "4K", "1080P", "720P"), presets.map(NativeFntvQualityMenu::title))
        assertEquals(listOf(0, -1, -2, -4), presets.map { it.optInt("index") })
        assertEquals(5, qualities.size)
    }
    @Test fun currentCustomBitrateRemainsSelected() {
        assertEquals(listOf(0, -1, -3, -4), NativeFntvQualityMenu.presets(qualities, -3).map { it.optInt("index") })
        assertEquals("1080P · 4.0 Mbps", NativeFntvQualityMenu.detail(qualities[3]))
        assertTrue(NativeFntvQualityMenu.presets(emptyList(), 0).isEmpty())
    }
    @Test fun preservesProviderLabelsAndNormalizesOriginal() {
        assertEquals("原画", NativeFntvQualityMenu.title(JSONObject("""{"resolution":"Original"}""")))
        assertEquals("流畅", NativeFntvQualityMenu.title(JSONObject("""{"resolution":"流畅"}""")))
    }
}
