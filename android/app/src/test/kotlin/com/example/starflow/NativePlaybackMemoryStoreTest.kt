package com.example.starflow

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class NativePlaybackMemoryStoreTest {
    private var raw: String? = null
    private var tick = 0
    private val writes = mutableListOf<Boolean>()
    private val store =
        NativePlaybackMemoryStore(
            readSnapshot = { raw },
            writeSnapshot = { value, synchronous ->
                raw = value
                writes += synchronous
                true
            },
            now = { (++tick).toString().padStart(8, '0') },
            log = {},
        )

    private fun save(
        key: String = "item",
        position: Long = 20_000L,
        duration: Long = 100_000L,
        sync: Boolean = false,
    ) {
        store.savePlaybackEntry(
            """{"title":"Episode","seriesTitle":"Series"}""",
            key,
            "series",
            position,
            duration,
            sync,
        )
    }

    @Test
    fun invalidSnapshotAndMissingKeyAreSafe() {
        raw = "invalid"
        assertEquals(0L, store.loadResumePositionMs("item"))
        assertNull(store.loadSeriesSkipPreference("series"))
        assertNull(store.loadSeriesSubtitlePreference("series"))
        save(key = " ", sync = true)
        assertTrue(writes.isEmpty())
        save()
        assertEquals(20_000L, store.loadResumePositionMs("item"))
    }

    @Test
    fun forcedSavesCommitAndRegularSavesApply() {
        save()
        save(position = 30_000L, sync = true)
        assertEquals(listOf(false, true), writes)
        assertEquals(30_000L, store.loadResumePositionMs("item"))
        val snapshot = JSONObject(raw!!)
        assertEquals(
            snapshot.getJSONObject("items").getJSONObject("item").toString(),
            snapshot.getJSONObject("series").getJSONObject("series").toString(),
        )
    }

    @Test
    fun resumeBoundariesRemainUnchanged() {
        save(position = 4_999L)
        assertEquals(0L, store.loadResumePositionMs("item"))
        save(position = 5_000L)
        assertEquals(5_000L, store.loadResumePositionMs("item"))
        save(position = 87_999L)
        assertEquals(87_999L, store.loadResumePositionMs("item"))
        save(position = 88_000L)
        assertEquals(0L, store.loadResumePositionMs("item"))
        save(position = 985_000L, duration = 1_000_000L)
        assertEquals(0L, store.loadResumePositionMs("item"))
    }

    @Test
    fun clampsProgressAndHandlesUnknownDuration() {
        save(position = -1L)
        var entry = JSONObject(raw!!).getJSONObject("items").getJSONObject("item")
        assertEquals(0L, entry.getLong("positionMs"))
        save(position = 200_000L)
        entry = JSONObject(raw!!).getJSONObject("items").getJSONObject("item")
        assertEquals(100_000L, entry.getLong("positionMs"))
        assertTrue(entry.getBoolean("completed"))
        save(position = 20_000L, duration = -1L)
        assertEquals(20_000L, store.loadResumePositionMs("item"))
    }

    @Test
    fun preservesSubtitleAndSkipPreferencesAcrossProgressWrites() {
        val preference =
            NativeSubtitleSessionPreference(
                NativeSubtitleSessionMode.DUAL,
                NativeSubtitleTrackFingerprint(language = "zh", label = "Primary"),
                NativeSubtitleTrackFingerprint(language = "en", label = "Secondary"),
            )
        store.saveSeriesSubtitlePreference(" series ", preference)
        store.saveSeriesSkipPreference("series", "Series", true, 1_000L, 2_000L)
        save()
        assertEquals(preference, store.loadSeriesSubtitlePreference("series"))
        assertEquals(2_000L, store.loadSeriesSkipPreference("series")?.getLong("outroDurationMs"))
        store.saveSeriesSubtitlePreference(
            "other",
            NativeSubtitleSessionPreference(NativeSubtitleSessionMode.OFF),
        )
        store.clearSeriesSubtitlePreference(" series ")
        assertNull(store.loadSeriesSubtitlePreference("series"))
        assertEquals(
            NativeSubtitleSessionMode.OFF,
            store.loadSeriesSubtitlePreference("other")?.mode,
        )
        assertEquals(20_000L, store.loadResumePositionMs("item"))
        assertTrue(store.loadSeriesSkipPreference("series")!!.getBoolean("enabled"))
    }

    @Test
    fun prunesOnlyRecentItemsNotSeriesOrPreferences() {
        store.saveSeriesSkipPreference("series", "Series", true, -1L, 1_000L)
        repeat(25) { save(key = "item$it") }
        val snapshot = JSONObject(raw!!)
        assertEquals(20, snapshot.getJSONObject("items").length())
        assertFalse(snapshot.getJSONObject("items").has("item0"))
        assertTrue(snapshot.getJSONObject("items").has("item24"))
        assertEquals(
            "item24",
            snapshot.getJSONObject("series").getJSONObject("series").getString("key"),
        )
        assertEquals(0L, store.loadSeriesSkipPreference("series")?.getLong("introDurationMs"))
    }

    @Test
    fun blankPreferenceKeysDoNotWrite() {
        store.saveSeriesSubtitlePreference(
            " ",
            NativeSubtitleSessionPreference(NativeSubtitleSessionMode.OFF),
        )
        store.saveSeriesSubtitlePreference("series", null)
        store.clearSeriesSubtitlePreference(" ")
        store.saveSeriesSkipPreference(" ", "", false, 0L, 0L)
        assertTrue(writes.isEmpty())
    }
}
