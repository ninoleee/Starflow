package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
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
        val matches = tracks.filter { !codecContradicts(it.format, preferred) && matchesServer(it.format, preferred) }
        val exact = matches.filter { matchesCodec(it.format, preferred) }
        // Never compress the ordinal by filtering unsupported tracks first.
        val match = exact.singleOrNull() ?: matches.singleOrNull() ?: if (tracks.size == rows.size) {
            tracks.getOrNull(rows.indexOf(preferred))?.takeUnless { codecContradicts(it.format, preferred) }
        } else null
        return match?.takeIf { it.supported }
    }

    fun serverStream(tracks: List<NativeAudioTrack>, selected: NativeAudioTrack, target: JSONObject): JSONObject? {
        val streams = target.optJSONArray("audioStreams") ?: return null
        val rows = (0 until streams.length()).mapNotNull(streams::optJSONObject)
            .sortedBy { it.optInt("index") }
        val matches = rows.filter { !codecContradicts(selected.format, it) && matchesServer(selected.format, it) }
        val exact = matches.filter { matchesCodec(selected.format, it) }
        return exact.singleOrNull() ?: matches.singleOrNull() ?: if (tracks.size == rows.size) {
            rows.getOrNull(tracks.indexOf(selected))?.takeUnless { codecContradicts(selected.format, it) }
        } else null
    }

    private fun matchesServer(format: Format, row: JSONObject): Boolean {
        val lang = language(row.optString("language"))
        val title = row.optString("title").trim()
        return (lang.isNotEmpty() || title.isNotEmpty()) &&
            (lang.isEmpty() || language(format.language) == lang) &&
            (title.isEmpty() || format.label?.trim() == title) &&
            (row.optInt("channels") <= 0 || format.channelCount == row.optInt("channels"))
    }

    private fun matchesCodec(format: Format, row: JSONObject): Boolean {
        val mime = serverCodecMime(row)
        return mime != null && mime == format.sampleMimeType
    }

    private fun codecContradicts(format: Format, row: JSONObject): Boolean {
        val serverMime = serverCodecMime(row) ?: return false
        val localMime = format.sampleMimeType?.takeIf { it != MimeTypes.AUDIO_UNKNOWN } ?: return false
        // Server metadata often names the base codec while Media3 reports its extension.
        if (serverMime == MimeTypes.AUDIO_E_AC3 && localMime == MimeTypes.AUDIO_E_AC3_JOC) return false
        if (serverMime == MimeTypes.AUDIO_DTS &&
            localMime in listOf(MimeTypes.AUDIO_DTS_HD, MimeTypes.AUDIO_DTS_EXPRESS)) return false
        return serverMime != localMime
    }

    private fun serverCodecMime(row: JSONObject): String? {
        val codec = row.optString("codec").trim().lowercase(Locale.ROOT)
        return when (codec) {
            "aac" -> MimeTypes.AUDIO_AAC
            "ac3", "ac-3" -> MimeTypes.AUDIO_AC3
            "eac3", "e-ac-3" -> MimeTypes.AUDIO_E_AC3
            "dts" -> MimeTypes.AUDIO_DTS
            "truehd" -> MimeTypes.AUDIO_TRUEHD
            "flac" -> MimeTypes.AUDIO_FLAC
            "opus" -> MimeTypes.AUDIO_OPUS
            "mp3" -> MimeTypes.AUDIO_MPEG
            else -> MimeTypes.getAudioMediaMimeType(codec)
        }
    }

    private fun language(raw: String?): String = when (val value = raw.orEmpty().lowercase(Locale.ROOT).replace('_', '-')) {
        "eng" -> "en"
        "zho", "chi", "cmn" -> "zh"
        "jpn" -> "ja"
        else -> value
    }
}
