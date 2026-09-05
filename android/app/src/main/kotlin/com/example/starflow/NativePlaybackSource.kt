package com.example.starflow

import android.net.Uri
import androidx.media3.common.MimeTypes
import java.util.Locale
import org.json.JSONObject

internal object NativePlaybackSource {
    fun summarizeHeaderKeys(headersJson: String): String {
        if (headersJson.isBlank()) {
            return "-"
        }
        return try {
            val json = JSONObject(headersJson)
            val keys = mutableListOf<String>()
            val iterator = json.keys()
            while (iterator.hasNext()) {
                keys += iterator.next()
            }
            if (keys.isEmpty()) "-" else keys.joinToString("|")
        } catch (_: Throwable) {
            "invalid-json"
        }
    }

    fun summarizeUrl(raw: String): String {
        if (raw.isBlank()) {
            return "-"
        }
        return try {
            val uri = Uri.parse(raw)
            val path = uri.path?.takeIf { it.isNotBlank() } ?: "/"
            "${uri.scheme}://${uri.host ?: ""}$path"
        } catch (_: Throwable) {
            raw
        }
    }

    fun isHttpPlaybackUrl(rawUrl: String): Boolean {
        return try {
            val scheme = Uri.parse(rawUrl.trim()).scheme?.lowercase(Locale.US)
            scheme == "http" || scheme == "https"
        } catch (_: Throwable) {
            false
        }
    }

    fun guessVideoMimeType(targetObject: JSONObject, url: String): String {
        val container = targetObject.optString("container").trim().lowercase(Locale.US)
        return when {
            container == "mp4" || container == "m4v" -> MimeTypes.VIDEO_MP4
            container == "webm" -> MimeTypes.VIDEO_WEBM
            container == "mkv" -> MimeTypes.VIDEO_MATROSKA
            container == "ts" || container == "m2ts" -> MimeTypes.VIDEO_MP2T
            container == "mpg" || container == "mpeg" -> MimeTypes.VIDEO_MPEG
            url.lowercase(Locale.US).endsWith(".mp4") ||
                url.lowercase(Locale.US).endsWith(".m4v") -> MimeTypes.VIDEO_MP4
            url.lowercase(Locale.US).endsWith(".webm") -> MimeTypes.VIDEO_WEBM
            url.lowercase(Locale.US).endsWith(".mkv") -> MimeTypes.VIDEO_MATROSKA
            url.lowercase(Locale.US).endsWith(".ts") ||
                url.lowercase(Locale.US).endsWith(".m2ts") -> MimeTypes.VIDEO_MP2T
            url.lowercase(Locale.US).endsWith(".mpg") ||
                url.lowercase(Locale.US).endsWith(".mpeg") -> MimeTypes.VIDEO_MPEG
            else -> "-"
        }
    }

    fun buildTranscodedVideoFallbackUrl(rawUrl: String): String? {
        val uri = Uri.parse(rawUrl.trim())
        if (!uri.isAbsolute || uri.host.isNullOrBlank()) {
            return null
        }
        val queryParameters = LinkedHashMap<String, String>()
        for (name in uri.queryParameterNames) {
            queryParameters[name] = uri.getQueryParameter(name).orEmpty()
        }
        queryParameters["static"] = "false"
        val builder = uri.buildUpon().clearQuery()
        for ((name, value) in queryParameters) {
            builder.appendQueryParameter(name, value)
        }
        return builder.build().toString()
    }
}
