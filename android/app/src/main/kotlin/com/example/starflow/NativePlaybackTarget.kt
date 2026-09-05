package com.example.starflow

import android.net.Uri
import org.json.JSONObject

internal class NativePlaybackTarget(private val currentTitle: () -> String) {

    var playbackTargetJson = "{}"

    var playbackItemKey = ""

    var seriesKey = ""

    var resolverSessionId = ""

    fun decodePlaybackTargetObject(): JSONObject {
        return try {
            JSONObject(playbackTargetJson)
        } catch (_: Throwable) {
            JSONObject()
        }
    }

    fun buildPlaybackPagePrimaryTitle(): String {
        val targetObject = decodePlaybackTargetObject()
        val title = currentTitle().trim()
        val seriesTitle = targetObject.optString("seriesTitle").trim()
        val itemType = targetObject.optString("itemType").trim().lowercase()
        return when {
            itemType == "episode" && seriesTitle.isNotEmpty() -> seriesTitle
            title.isNotEmpty() -> title
            else -> "Starflow"
        }
    }

    fun buildPlaybackPageSecondaryTitle(): String {
        val targetObject = decodePlaybackTargetObject()
        val title = currentTitle().trim()
        val itemType = targetObject.optString("itemType").trim().lowercase()
        val seasonNumber = targetObject.optInt("seasonNumber", 0)
        val episodeNumber = targetObject.optInt("episodeNumber", 0)
        val primaryTitle = buildPlaybackPagePrimaryTitle()
        val parts = mutableListOf<String>()
        if (title.isNotEmpty() && title != primaryTitle) {
            parts += title
        }
        if (itemType == "episode" && seasonNumber > 0 && episodeNumber > 0) {
            parts +=
                "S${seasonNumber.toString().padStart(2, '0')}" +
                    "E${episodeNumber.toString().padStart(2, '0')}"
        }
        val subtitle = buildSystemSessionSubtitle()
        if (subtitle.isNotEmpty()) {
            parts += subtitle
        }
        return parts.joinToString(" · ")
    }

    fun buildSystemSessionTitle(): String {
        val title = currentTitle().trim()
        val targetObject =
            try {
                JSONObject(playbackTargetJson)
            } catch (_: Throwable) {
                JSONObject()
            }
        val seasonNumber = targetObject.optInt("seasonNumber", 0)
        val episodeNumber = targetObject.optInt("episodeNumber", 0)
        if (seasonNumber > 0 && episodeNumber > 0 && title.isNotEmpty()) {
            return "$title · S${seasonNumber.toString().padStart(2, '0')}" +
                "E${episodeNumber.toString().padStart(2, '0')}"
        }
        return if (title.isEmpty()) "Starflow" else title
    }

    fun buildSystemSessionSubtitle(): String {
        val targetObject =
            try {
                JSONObject(playbackTargetJson)
            } catch (_: Throwable) {
                JSONObject()
            }
        val itemType = targetObject.optString("itemType").trim().lowercase()
        val seriesTitle = targetObject.optString("seriesTitle").trim()
        if (itemType == "episode" && seriesTitle.isNotEmpty()) {
            return seriesTitle
        }
        val sourceName = targetObject.optString("sourceName").trim()
        val formatParts = buildList {
            val container = targetObject.optString("container").trim()
            val videoCodec = targetObject.optString("videoCodec").trim()
            val audioCodec = targetObject.optString("audioCodec").trim()
            if (sourceName.isNotEmpty()) {
                add(sourceName)
            }
            if (container.isNotEmpty()) {
                add(container.uppercase())
            }
            if (videoCodec.isNotEmpty()) {
                add(videoCodec.uppercase())
            }
            if (audioCodec.isNotEmpty()) {
                add(audioCodec.uppercase())
            }
        }
        return formatParts.joinToString(" · ")
    }

    fun buildSeriesSkipPreferenceTitle(): String {
        val targetObject = decodePlaybackTargetObject()
        return targetObject.optString("seriesTitle").trim().ifBlank {
            if (targetObject.optString("itemType").trim().lowercase() == "series") {
                targetObject.optString("title").trim()
            } else {
                buildPlaybackPagePrimaryTitle()
            }
        }
    }

    fun buildSubtitleSearchQuery(): String {
        val targetObject =
            try {
                JSONObject(playbackTargetJson)
            } catch (_: Throwable) {
                JSONObject()
            }
        val seriesTitle = targetObject.optString("seriesTitle").trim()
        val title = targetObject.optString("title").trim()
        val itemType = targetObject.optString("itemType").trim().lowercase()
        val seasonNumber = targetObject.optInt("seasonNumber", 0)
        val episodeNumber = targetObject.optInt("episodeNumber", 0)
        val year = targetObject.optInt("year", 0)

        val parts = mutableListOf<String>()
        val baseTitle = if (seriesTitle.isNotEmpty()) seriesTitle else title
        if (baseTitle.isNotEmpty()) {
            parts += baseTitle
        }
        if (seasonNumber > 0 && episodeNumber > 0) {
            parts +=
                "S${seasonNumber.toString().padStart(2, '0')}E${episodeNumber.toString().padStart(2, '0')}"
        }
        if (itemType != "episode" && year > 0) {
            parts += year.toString()
        }
        return parts.joinToString(" ").trim()
    }

    fun buildSubtitleSearchRoute(query: String): String {
        val title = buildSubtitleSearchTitle()
        return Uri.Builder()
            .path("/subtitle-search")
            .appendQueryParameter("q", query)
            .appendQueryParameter("title", title)
            .appendQueryParameter("input", title.ifBlank { query })
            .appendQueryParameter("mode", "downloadAndApply")
            .appendQueryParameter("standalone", "1")
            .build()
            .toString()
    }

    private fun buildSubtitleSearchTitle(): String {
        val targetObject =
            try {
                JSONObject(playbackTargetJson)
            } catch (_: Throwable) {
                JSONObject()
            }
        val seriesTitle = targetObject.optString("seriesTitle").trim()
        val title = targetObject.optString("title").trim()
        return if (seriesTitle.isNotEmpty()) seriesTitle else title
    }
}
