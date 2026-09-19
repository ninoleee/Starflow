package com.example.starflow

import java.io.File
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PlaybackMemoryPolicyTest {
    @Test fun storePrunesByInstantAndStableKeyAndAdvancesTimestamp() {
        val items = JSONObject()
        repeat(21) { i ->
            val key = "item${i.toString().padStart(2, '0')}"
            items.put(key, JSONObject().put("key", key).put("updatedAt",
                if (i % 2 == 0) "2026-09-20T10:00:00Z" else "2026-09-20T18:00:00.000+08:00"))
        }
        var raw = JSONObject().put("items", items).toString()
        val store = NativePlaybackMemoryStore(readSnapshot = { raw },
            writeSnapshot = { value, _ -> raw = value; true },
            now = { "2026-09-20T10:00:00Z" }, log = {})
        store.savePlaybackEntry("{}", "new", "", 20000, 100000, false)
        val saved = JSONObject(raw).getJSONObject("items")
        assertEquals(20, saved.length())
        assertFalse(saved.has("item00"))
        assertFalse(saved.has("item01"))
        assertTrue(saved.has("item20"))
        assertEquals("2026-09-20T10:00:00.001Z", saved.getJSONObject("new").getString("updatedAt"))
    }

    @Test fun sharedContract() {
        val fixture = JSONObject(File("../../test/fixtures/playback_memory_contract.json").readText())
        val cases = fixture.getJSONArray("cases")
        for (i in 0 until cases.length()) {
            val c = cases.getJSONObject(i)
            assertEquals("resume $i", c.getLong("resumeMs"), PlaybackMemoryPolicy.resume(
                c.getLong("positionMs"), c.getLong("durationMs"), c.getDouble("progress"), c.getBoolean("completed")))
            assertEquals("completed $i", c.getBoolean("isCompleted"), PlaybackMemoryPolicy.completed(
                c.getLong("positionMs"), c.getLong("durationMs"), c.getDouble("progress")))
        }
        val raw = fixture.getJSONArray("timestamps")
        val timestamps = (0 until raw.length()).map { raw.getString(it) }
        assertEquals(1, timestamps.map(PlaybackMemoryPolicy::timestamp).toSet().size)
        assertEquals(fixture.getString("nextTimestamp"), PlaybackMemoryPolicy.nextTimestamp(timestamps.first(), timestamps))
        assertEquals(20, PlaybackPolicyValues.memoryRecentLimit)
    }
}
