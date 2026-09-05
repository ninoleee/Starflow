package com.example.starflow

import android.content.SharedPreferences
import org.json.JSONObject

internal class NativePlaybackMemoryStore(
    private val readSnapshot: () -> String?,
    private val writeSnapshot: (String, Boolean) -> Boolean,
    private val now: () -> String = NativePlaybackFormatting::isoNow,
    private val log: (String) -> Unit = { NativePlaybackFormatting.logPlayback(it) },
) {
    constructor(
        preferences: SharedPreferences
    ) : this(
        readSnapshot = { preferences.getString(PLAYBACK_MEMORY_STORAGE_KEY, null) },
        writeSnapshot = { value, synchronous ->
            val editor = preferences.edit().putString(PLAYBACK_MEMORY_STORAGE_KEY, value)
            if (synchronous) editor.commit()
            else {
                editor.apply()
                true
            }
        },
    )

    fun loadResumePositionMs(itemKey: String): Long {
        val entry = loadPlaybackEntry(itemKey) ?: return 0L
        val positionMs = entry.optLong("positionMs", 0L)
        val durationMs = entry.optLong("durationMs", 0L)
        val progress = entry.optDouble("progress", 0.0)
        val completed = entry.optBoolean("completed", false)
        if (completed || positionMs < 5_000L) {
            return 0L
        }
        if (durationMs > 0L && durationMs - positionMs <= 12_000L) {
            return 0L
        }
        if (progress >= 0.985) {
            return 0L
        }
        return positionMs
    }

    private fun loadPlaybackEntry(itemKey: String): JSONObject? {
        if (itemKey.isBlank()) {
            return null
        }
        val snapshot = loadPlaybackSnapshot()
        val items = snapshot.optJSONObject("items") ?: return null
        return items.optJSONObject(itemKey)
    }

    private fun loadPlaybackSnapshot(): JSONObject {
        val raw = readSnapshot()
        if (raw.isNullOrBlank()) {
            return JSONObject()
        }
        return try {
            JSONObject(raw)
        } catch (_: Throwable) {
            JSONObject()
        }
    }

    fun loadSeriesSubtitlePreference(seriesKey: String): NativeSubtitleSessionPreference? {
        val normalizedSeriesKey = seriesKey.trim()
        if (normalizedSeriesKey.isEmpty()) {
            return null
        }
        val raw =
            loadPlaybackSnapshot()
                .optJSONObject("subtitlePreferences")
                ?.optJSONObject(normalizedSeriesKey) ?: return null
        val mode =
            when (raw.optString("mode")) {
                "off" -> NativeSubtitleSessionMode.OFF
                "dual" -> NativeSubtitleSessionMode.DUAL
                else -> NativeSubtitleSessionMode.SINGLE
            }
        return NativeSubtitleSessionPreference(
            mode = mode,
            primary = raw.optJSONObject("primary")?.toSubtitleFingerprint(),
            secondary = raw.optJSONObject("secondary")?.toSubtitleFingerprint(),
        )
    }

    fun saveSeriesSubtitlePreference(
        seriesKey: String,
        preference: NativeSubtitleSessionPreference?,
    ) {
        val normalizedSeriesKey = seriesKey.trim()
        if (normalizedSeriesKey.isEmpty() || preference == null) {
            return
        }
        val snapshot = loadPlaybackSnapshot()
        val subtitlePreferences = snapshot.optJSONObject("subtitlePreferences") ?: JSONObject()
        subtitlePreferences.put(
            normalizedSeriesKey,
            preference.toJson(seriesKey = normalizedSeriesKey, updatedAt = now()),
        )
        snapshot.put("subtitlePreferences", subtitlePreferences)
        writeSnapshot(snapshot.toString(), false)
    }

    fun clearSeriesSubtitlePreference(seriesKey: String) {
        val normalizedSeriesKey = seriesKey.trim()
        if (normalizedSeriesKey.isEmpty()) {
            return
        }
        val snapshot = loadPlaybackSnapshot()
        val subtitlePreferences = snapshot.optJSONObject("subtitlePreferences") ?: return
        subtitlePreferences.remove(normalizedSeriesKey)
        snapshot.put("subtitlePreferences", subtitlePreferences)
        writeSnapshot(snapshot.toString(), false)
    }

    fun savePlaybackEntry(
        targetJson: String,
        itemKey: String,
        seriesKey: String,
        positionMs: Long,
        durationMs: Long,
        synchronous: Boolean,
    ) {
        if (itemKey.isBlank()) {
            if (synchronous) {
                log("native.playback.progress.skipped reason=empty-item-key")
            }
            return
        }

        val clampedDuration = durationMs.coerceAtLeast(0L)
        val safePosition =
            if (clampedDuration > 0L) {
                positionMs.coerceIn(0L, clampedDuration)
            } else {
                positionMs.coerceAtLeast(0L)
            }
        val progress =
            if (clampedDuration <= 0L) {
                0.0
            } else {
                (safePosition.toDouble() / clampedDuration.toDouble()).coerceIn(0.0, 1.0)
            }
        val completed =
            isCompleted(
                positionMs = safePosition,
                durationMs = clampedDuration,
                progress = progress,
            )

        val snapshot = loadPlaybackSnapshot()
        val items = snapshot.optJSONObject("items") ?: JSONObject()
        val series = snapshot.optJSONObject("series") ?: JSONObject()
        val skipPreferences = snapshot.optJSONObject("skipPreferences") ?: JSONObject()
        val subtitlePreferences = snapshot.optJSONObject("subtitlePreferences") ?: JSONObject()
        val targetObject =
            try {
                JSONObject(targetJson)
            } catch (_: Throwable) {
                JSONObject()
            }
        val seriesTitle =
            targetObject.optString("seriesTitle").ifBlank {
                if (targetObject.optString("itemType").trim().lowercase() == "series") {
                    targetObject.optString("title")
                } else {
                    ""
                }
            }

        val entry =
            JSONObject().apply {
                put("key", itemKey)
                put("target", targetObject)
                put("updatedAt", now())
                put("seriesKey", seriesKey)
                put("seriesTitle", seriesTitle)
                put("positionMs", safePosition)
                put("durationMs", clampedDuration)
                put("progress", progress)
                put("completed", completed)
            }

        items.put(itemKey, entry)
        pruneRecentItems(items)
        if (seriesKey.isNotBlank()) {
            series.put(seriesKey, entry)
        }

        val nextSnapshot =
            JSONObject().apply {
                put("items", items)
                put("series", series)
                put("skipPreferences", skipPreferences)
                put("subtitlePreferences", subtitlePreferences)
            }
        val committed = writeSnapshot(nextSnapshot.toString(), synchronous)
        if (synchronous) {
            log(
                "native.playback.progress.saved " +
                    "positionMs=$safePosition durationMs=$clampedDuration " +
                    "committed=$committed"
            )
        }
    }

    private fun pruneRecentItems(items: JSONObject) {
        val keyedEntries = mutableListOf<Pair<String, JSONObject>>()
        val keys = items.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = items.optJSONObject(key) ?: continue
            keyedEntries.add(key to value)
        }
        if (keyedEntries.size <= RECENT_ENTRY_LIMIT) {
            return
        }
        keyedEntries.sortByDescending { (_, value) -> value.optString("updatedAt") }
        keyedEntries.drop(RECENT_ENTRY_LIMIT).forEach { (key, _) -> items.remove(key) }
    }

    private fun isCompleted(positionMs: Long, durationMs: Long, progress: Double): Boolean {
        if (durationMs <= 0L) {
            return progress >= 0.995
        }
        val remaining = durationMs - positionMs
        return progress >= 0.985 || remaining <= 8_000L
    }

    fun loadSeriesSkipPreference(seriesKey: String): JSONObject? {
        if (seriesKey.isBlank()) {
            return null
        }
        return loadPlaybackSnapshot().optJSONObject("skipPreferences")?.optJSONObject(seriesKey)
    }

    fun saveSeriesSkipPreference(
        seriesKey: String,
        seriesTitle: String,
        enabled: Boolean,
        introDurationMs: Long,
        outroDurationMs: Long,
    ) {
        val normalizedSeriesKey = seriesKey.trim()
        if (normalizedSeriesKey.isEmpty()) return
        val snapshot = loadPlaybackSnapshot()
        val skipPreferences = snapshot.optJSONObject("skipPreferences") ?: JSONObject()
        skipPreferences.put(
            normalizedSeriesKey,
            JSONObject().apply {
                put("seriesKey", normalizedSeriesKey)
                put("updatedAt", now())
                put("seriesTitle", seriesTitle)
                put("enabled", enabled)
                put("introDurationMs", introDurationMs.coerceAtLeast(0L))
                put("outroDurationMs", outroDurationMs.coerceAtLeast(0L))
            },
        )
        val nextSnapshot =
            JSONObject().apply {
                put("items", snapshot.optJSONObject("items") ?: JSONObject())
                put("series", snapshot.optJSONObject("series") ?: JSONObject())
                put("skipPreferences", skipPreferences)
                put(
                    "subtitlePreferences",
                    snapshot.optJSONObject("subtitlePreferences") ?: JSONObject(),
                )
            }
        writeSnapshot(nextSnapshot.toString(), false)
    }
}
