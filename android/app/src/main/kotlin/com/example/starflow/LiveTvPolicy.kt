package com.example.starflow

import java.net.URI
import java.util.Locale

internal object LiveTvVideoPolicy {
    const val DEFAULT_RATIO = 16f / 9f

    fun ratio(width: Int, height: Int, pixelRatio: Float): Float? {
        if (width <= 0 || height <= 0 || !pixelRatio.isFinite() || pixelRatio <= 0) return null
        return (width.toDouble() * pixelRatio / height).toFloat().takeIf { it.isFinite() && it > 0 }
    }

    fun scale(width: Int, height: Int, ratio: Float): Pair<Float, Float> {
        if (width <= 0 || height <= 0 || !ratio.isFinite() || ratio <= 0) return 1f to 1f
        val actual = width.toFloat() / height
        return if (actual > ratio) ratio / actual to 1f else 1f to actual / ratio
    }
}

internal class LiveTvHlsFallbackPolicy {
    private var attempted = false

    fun tryFallback(unrecognizedContainer: Boolean): Boolean {
        if (attempted || !unrecognizedContainer) return false
        attempted = true
        return true
    }
}

/** A native identity is separate from the caller's generation, which may be reused. */
internal class LiveTvSessionPolicy {
    private var serial = 0L
    private var active = false
    private var terminal = false
    private var position: Long? = null
    var generation = 0L
        private set
    val token get() = serial
    fun acceptsAudio(generation: Long?, token: Long?) =
        generation == this.generation && token != null && accepts(token)

    fun open(generation: Long): Long {
        invalidate()
        this.generation = generation
        active = true
        return serial
    }

    fun invalidate() {
        serial++
        active = false
        terminal = false
        position = null
    }

    fun accepts(token: Long) = active && !terminal && token == serial

    fun event(token: Long, state: String): Boolean {
        if (!accepts(token)) return false
        if (state == "error" || state == "ended") terminal = true
        return true
    }

    fun resetProgress() { position = null }

    fun progress(token: Long, currentPosition: Long, playing: Boolean): Boolean {
        if (!accepts(token)) return false
        val previous = position
        position = currentPosition.takeIf { playing && it >= 0 }
        return playing && previous != null && currentPosition > previous
    }
}

internal object LiveTvPausePolicy {
    fun state(playWhenReady: Boolean, suppressionReason: Int, changeReason: Int): String = when {
        !playWhenReady -> "paused:$changeReason"
        suppressionReason != 0 -> "suppressed:$suppressionReason"
        else -> "resumed"
    }
}

internal enum class MediaHttpRejection {
    MALFORMED_URL, UNSUPPORTED_SCHEME, INVALID_HOST, EMBEDDED_CREDENTIALS, INVALID_PORT,
    HTTPS_DOWNGRADE,
}

/** Fixed reasons only: URI parser exceptions can contain signed URLs or credentials. */
internal class MediaHttpPolicyException(val reason: MediaHttpRejection) :
    IllegalArgumentException("Media HTTP policy rejected: ${reason.name}")

internal class LiveTvHttpPolicy(url: String, headers: Map<*, *>) {
    private val origin = parse(url)
    private val headers = linkedMapOf<String, String>().apply {
        headers.forEach { (key, value) ->
            if (key is String && value is String && HEADER_NAME.matches(key) &&
                value.all { it == '\t' || it.code in 32..126 || it.code in 128..255 }) {
                val name = key.lowercase(Locale.ROOT)
                if (name !in BLOCKED_HEADERS && !name.startsWith("proxy-")) put(name, value)
            }
        }
    }

    fun requestHeaders(url: String): Map<String, String> {
        val target = parse(url)
        if (origin.scheme == "https" && target.scheme != "https") {
            throw MediaHttpPolicyException(MediaHttpRejection.HTTPS_DOWNGRADE)
        }
        return if (sameOrigin(origin, target)) headers.toMap() else emptyMap()
    }

    fun redirect(from: String, location: String): String {
        val source = parse(from)
        val resolved = try { source.resolve(encodeResourceReference(location)).toString() } catch (_: IllegalArgumentException) {
            throw MediaHttpPolicyException(MediaHttpRejection.MALFORMED_URL)
        }
        val target = parse(resolved)
        if (source.scheme == "https" && target.scheme != "https") {
            throw MediaHttpPolicyException(MediaHttpRejection.HTTPS_DOWNGRADE)
        }
        requestHeaders(target.toString())
        return target.toString()
    }

    companion object {
        private val HEADER_NAME = Regex("[!#$%&'*+.^_`|~0-9A-Za-z-]+")
        private val ABSOLUTE_AUTHORITY = Regex("^[A-Za-z][A-Za-z0-9+.-]*://")
        private val BLOCKED_HEADERS = setOf(
            "host", "connection", "content-length", "transfer-encoding", "te", "trailer",
            "upgrade", "keep-alive", "range", "accept-encoding",
        )

        fun parse(url: String): URI {
            val uri = try { URI(encodeResourceReference(url)) } catch (_: java.net.URISyntaxException) {
                throw MediaHttpPolicyException(MediaHttpRejection.MALFORMED_URL)
            }
            val scheme = uri.scheme?.lowercase(Locale.ROOT)
            if (scheme !in setOf("http", "https")) {
                throw MediaHttpPolicyException(MediaHttpRejection.UNSUPPORTED_SCHEME)
            }
            if (uri.rawUserInfo != null) {
                throw MediaHttpPolicyException(MediaHttpRejection.EMBEDDED_CREDENTIALS)
            }
            if (uri.host.isNullOrEmpty()) throw MediaHttpPolicyException(MediaHttpRejection.INVALID_HOST)
            if (uri.port != -1 && uri.port !in 1..65535) {
                throw MediaHttpPolicyException(MediaHttpRejection.INVALID_PORT)
            }
            val encoded = uri.toASCIIString()
            return URI(scheme + encoded.substring(encoded.indexOf(':')))
        }

        /** Quote resource text only; never repair an authority or re-encode signed escapes. */
        private fun encodeResourceReference(value: String): String {
            if (value.any { it.code < 32 || it.code in 127..159 || it == '\\' }) {
                throw MediaHttpPolicyException(MediaHttpRejection.MALFORMED_URL)
            }
            val authorityStart = when {
                value.startsWith("//") -> 2
                ABSOLUTE_AUTHORITY.containsMatchIn(value) -> value.indexOf("://") + 3
                else -> -1
            }
            val resourceStart = if (authorityStart >= 0) {
                value.indexOfAny(charArrayOf('/', '?', '#'), authorityStart)
                    .let { if (it < 0) value.length else it }
            } else 0
            var path = true
            return buildString {
                value.forEachIndexed { index, char ->
                    if (index >= resourceStart && (char == '?' || char == '#')) path = false
                    val quote = index >= resourceStart &&
                        (char in " <>\"{}|^`" || (path && char in "[]"))
                    if (quote) {
                        append('%')
                        append(char.code.toString(16).uppercase(Locale.ROOT).padStart(2, '0'))
                    } else append(char)
                }
            }
        }

        private fun sameOrigin(a: URI, b: URI): Boolean =
            a.scheme == b.scheme && a.host.equals(b.host, ignoreCase = true) && port(a) == port(b)

        private fun port(uri: URI) = if (uri.port != -1) uri.port else if (uri.scheme == "https") 443 else 80
    }
}
