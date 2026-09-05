package com.example.starflow

import org.json.JSONObject

internal object NativePlaybackMarkers {
    fun buildPlaybackMarkerPositionsMs(
        durationMs: Long,
        targetObject: JSONObject,
        skipPreference: JSONObject?,
    ): LongArray {
        val markers = linkedSetOf<Long>()
        if (skipPreference?.optBoolean("enabled", false) == true) {
            addMarkerIfInRange(markers, skipPreference.optLong("introDurationMs", 0L), durationMs)
            val outroDurationMs = skipPreference.optLong("outroDurationMs", 0L)
            if (outroDurationMs > 0L && outroDurationMs < durationMs) {
                addMarkerIfInRange(markers, durationMs - outroDurationMs, durationMs)
            }
        }
        collectChapterMarkers(targetObject, durationMs, markers)
        return markers.sorted().toLongArray()
    }

    private fun collectChapterMarkers(
        targetObject: JSONObject,
        durationMs: Long,
        markers: MutableSet<Long>,
    ) {
        listOf("chapterTimesMs", "chapterPositionsMs", "chapterStartTimesMs", "chapterMarkersMs")
            .forEach { key ->
                appendMarkersFromArray(targetObject.optJSONArray(key), durationMs, markers)
            }
        val chapters = targetObject.optJSONArray("chapters") ?: return
        for (index in 0 until chapters.length()) {
            addMarkerIfInRange(markers, extractMarkerTimeMs(chapters.opt(index)), durationMs)
        }
    }

    private fun appendMarkersFromArray(
        array: org.json.JSONArray?,
        durationMs: Long,
        markers: MutableSet<Long>,
    ) {
        if (array == null) {
            return
        }
        for (index in 0 until array.length()) {
            addMarkerIfInRange(markers, extractMarkerTimeMs(array.opt(index)), durationMs)
        }
    }

    private fun extractMarkerTimeMs(value: Any?): Long {
        return when (value) {
            is Number -> value.toLong()
            is String -> value.toLongOrNull() ?: 0L
            is JSONObject -> {
                listOf("startPositionMs", "startMs", "positionMs", "timeMs").forEach { key ->
                    val candidate = value.optLong(key, Long.MIN_VALUE)
                    if (candidate != Long.MIN_VALUE) {
                        return candidate
                    }
                }
                listOf("startSeconds", "positionSeconds", "timeSeconds").forEach { key ->
                    val candidate = value.optLong(key, Long.MIN_VALUE)
                    if (candidate != Long.MIN_VALUE) {
                        return candidate * 1000L
                    }
                }
                0L
            }
            else -> 0L
        }
    }

    private fun addMarkerIfInRange(
        markers: MutableSet<Long>,
        markerTimeMs: Long,
        durationMs: Long,
    ) {
        if (markerTimeMs > 0L && markerTimeMs < durationMs) {
            markers += markerTimeMs
        }
    }
}
