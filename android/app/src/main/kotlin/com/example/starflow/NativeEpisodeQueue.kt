package com.example.starflow

import org.json.JSONObject

internal data class NativeEpisodeQueueEntry(
    val playbackTargetJson: String,
    val playbackItemKey: String,
    val seriesKey: String,
    val mediaMimeType: String = "",
) {
    private fun targetObject(): JSONObject {
        return try {
            JSONObject(playbackTargetJson)
        } catch (_: Throwable) {
            JSONObject()
        }
    }

    fun url(): String = targetObject().optString("streamUrl").trim()

    fun title(): String = targetObject().optString("title").trim()

    fun needsResolution(): Boolean {
        val target = targetObject()
        val streamUrl = target.optString("streamUrl").trim().lowercase()
        val actualAddress = target.optString("actualAddress").trim().lowercase()
        val sourceKind = target.optString("sourceKind").trim().lowercase()
        val streamPath = streamUrl.substringBefore('?').substringBefore('#')
        return streamUrl.isBlank() ||
            streamPath.endsWith(".strm") ||
            (sourceKind == "nas" &&
                streamUrl.isBlank() &&
                actualAddress.substringBefore('?').substringBefore('#').endsWith(".strm"))
    }

    fun headersJson(): String {
        return targetObject().optJSONObject("headers")?.toString() ?: "{}"
    }
}

internal data class NativeEpisodeQueue(
    val entries: List<NativeEpisodeQueueEntry>,
    val currentIndex: Int = 0,
) {
    fun hasPrevious(): Boolean {
        return currentIndex > 0 && currentIndex < entries.size
    }

    fun hasNext(): Boolean {
        return currentIndex >= 0 && currentIndex + 1 < entries.size
    }

    fun currentEntry(): NativeEpisodeQueueEntry? {
        return entries.getOrNull(currentIndex)
    }

    fun replaceEntry(index: Int, entry: NativeEpisodeQueueEntry): NativeEpisodeQueue {
        if (index !in entries.indices) {
            return this
        }
        val nextEntries = entries.toMutableList()
        nextEntries[index] = entry
        return copy(entries = nextEntries)
    }

    fun withCurrentMediaMimeType(mediaMimeType: String): NativeEpisodeQueue {
        val normalizedMimeType = mediaMimeType.trim()
        val current = currentEntry()
        if (normalizedMimeType.isEmpty() || current == null) {
            return this
        }
        return replaceEntry(currentIndex, current.copy(mediaMimeType = normalizedMimeType))
    }

    fun moveToNext(): NativeEpisodeQueue? {
        return if (hasNext()) copy(currentIndex = currentIndex + 1) else null
    }

    fun moveToPrevious(): NativeEpisodeQueue? {
        return if (hasPrevious()) copy(currentIndex = currentIndex - 1) else null
    }

    fun toJsonString(): String {
        val entriesJson = org.json.JSONArray()
        entries.forEach { entry ->
            entriesJson.put(
                JSONObject().apply {
                    put(
                        "target",
                        try {
                            JSONObject(entry.playbackTargetJson)
                        } catch (_: Throwable) {
                            JSONObject()
                        },
                    )
                    put("playbackItemKey", entry.playbackItemKey)
                    put("seriesKey", entry.seriesKey)
                    put("mediaMimeType", entry.mediaMimeType)
                }
            )
        }
        return JSONObject()
            .apply {
                put("currentIndex", currentIndex)
                put("entries", entriesJson)
            }
            .toString()
    }

    companion object {
        fun fromJsonString(raw: String): NativeEpisodeQueue? {
            if (raw.isBlank()) {
                return null
            }
            return try {
                val json = JSONObject(raw)
                val entriesArray = json.optJSONArray("entries") ?: return null
                val entries = mutableListOf<NativeEpisodeQueueEntry>()
                for (index in 0 until entriesArray.length()) {
                    val entryObject = entriesArray.optJSONObject(index) ?: continue
                    entries +=
                        NativeEpisodeQueueEntry(
                            playbackTargetJson =
                                entryObject.optJSONObject("target")?.toString() ?: "{}",
                            playbackItemKey = entryObject.optString("playbackItemKey").trim(),
                            seriesKey = entryObject.optString("seriesKey").trim(),
                            mediaMimeType = entryObject.optString("mediaMimeType").trim(),
                        )
                }
                if (entries.isEmpty()) {
                    return null
                }
                NativeEpisodeQueue(
                    entries = entries,
                    currentIndex = json.optInt("currentIndex", 0).coerceIn(0, entries.lastIndex),
                )
            } catch (_: Throwable) {
                null
            }
        }
    }
}
