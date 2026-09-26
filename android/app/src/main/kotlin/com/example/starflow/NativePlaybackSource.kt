package com.example.starflow

import android.net.Uri
import androidx.media3.common.MimeTypes
import java.util.Locale
import java.net.URI
import org.json.JSONObject

internal object NativePlaybackSource {
    fun buildRequestHeaders(headersJson: String): Map<String, String> {
        val headers = linkedMapOf<String, String>()
        if (headersJson.isNotBlank()) {
            try {
                val json = JSONObject(headersJson)
                val keys = json.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    headers[key] = json.optString(key)
                }
            } catch (_: Throwable) {
                // Fall back to the app user agent below.
            }
        }
        if (headers.keys.none { it.equals("User-Agent", ignoreCase = true) }) {
            headers["User-Agent"] = "Starflow"
        }
        return headers
    }

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

    fun supportsVideoTranscodeFallback(rawUrl: String, sourceKind: String): Boolean {
        if (sourceKind != "emby") return false
        val uri = runCatching { URI(rawUrl.trim()) }.getOrNull() ?: return false
        if (uri.scheme?.lowercase(Locale.US) !in setOf("http", "https") ||
            uri.host.isNullOrBlank()) return false
        // Only the media server's direct-stream endpoint accepts this switch.
        // Relay URLs are opaque capabilities, never transcode endpoints.
        val path = uri.path.orEmpty()
        if (path.contains("/playback-relay/", ignoreCase = true)) return false
        return Regex("(?:^|/)Videos/[^/]+/stream(?:\\.[a-zA-Z0-9]+)?$",
            RegexOption.IGNORE_CASE).containsMatchIn(path)
    }

    fun buildTranscodedVideoFallbackUrl(rawUrl: String, sourceKind: String): String? {
        if (!supportsVideoTranscodeFallback(rawUrl, sourceKind)) return null
        val uri = Uri.parse(rawUrl.trim())
        if (!uri.isAbsolute || uri.host.isNullOrBlank()) {
            return null
        }
        val queryParameters = LinkedHashMap<String, String>()
        for (name in uri.queryParameterNames) {
            queryParameters[name] = uri.getQueryParameter(name).orEmpty()
        }
        if (queryParameters["static"].equals("false", ignoreCase = true)) return null
        queryParameters["static"] = "false"
        val builder = uri.buildUpon().clearQuery()
        for ((name, value) in queryParameters) {
            builder.appendQueryParameter(name, value)
        }
        return builder.build().toString()
    }
}
