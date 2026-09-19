package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import java.util.Locale
import org.json.JSONObject

internal data class NativeAudioTrack(
    val format: Format,
    val override: TrackSelectionOverride,
    val selected: Boolean,
    val supported: Boolean,
)

internal object NativePlaybackAudioTracks {
    fun list(tracks: Tracks): List<NativeAudioTrack> = tracks.groups.flatMap { group ->
        if (group.type != C.TRACK_TYPE_AUDIO) emptyList() else (0 until group.length).map { index ->
            NativeAudioTrack(group.getTrackFormat(index),
                TrackSelectionOverride(group.mediaTrackGroup, index),
                group.isTrackSelected(index), group.isTrackSupported(index))
        }
    }

    fun match(tracks: List<NativeAudioTrack>, previous: Format): NativeAudioTrack? {
        val supported = tracks.filter { it.supported }
        return supported.filter {
            !previous.id.isNullOrBlank() && it.format.id == previous.id &&
                language(it.format.language) == language(previous.language) &&
                it.format.sampleMimeType == previous.sampleMimeType
        }.singleOrNull() ?: supported.filter {
            language(it.format.language) == language(previous.language) &&
                it.format.label == previous.label &&
                it.format.sampleMimeType == previous.sampleMimeType &&
                it.format.channelCount == previous.channelCount
        }.singleOrNull()
    }

    fun serverDefault(tracks: List<NativeAudioTrack>, target: JSONObject): NativeAudioTrack? {
        val streams = target.optJSONArray("audioStreams") ?: return null
        val preferredId = target.optString("preferredAudioStreamId").trim()
        if (preferredId.isEmpty()) return null
        val rows = (0 until streams.length()).mapNotNull(streams::optJSONObject)
            .sortedBy { it.optInt("index") }
        val preferred = rows.firstOrNull { it.optString("id").trim() == preferredId }
            ?: return null
        val matches = tracks.filter { track ->
            val lang = language(preferred.optString("language"))
            val title = preferred.optString("title").trim()
            (lang.isNotEmpty() || title.isNotEmpty()) &&
                (lang.isEmpty() || language(track.format.language) == lang) &&
                (title.isEmpty() || track.format.label?.trim() == title) &&
                (preferred.optInt("channels") <= 0 || track.format.channelCount == preferred.optInt("channels"))
        }
        // Never compress the ordinal by filtering unsupported tracks first.
        val match = matches.singleOrNull() ?: if (tracks.size == rows.size) {
            tracks.getOrNull(rows.indexOf(preferred))
        } else null
        return match?.takeIf { it.supported }
    }

    private fun language(raw: String?): String = when (val value = raw.orEmpty().lowercase(Locale.ROOT).replace('_', '-')) {
        "eng" -> "en"
        "zho", "chi", "cmn" -> "zh"
        "jpn" -> "ja"
        else -> value
    }
}
