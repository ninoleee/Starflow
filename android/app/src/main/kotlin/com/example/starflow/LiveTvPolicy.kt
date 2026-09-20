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

internal class LiveTvHlsFallbackPolicy(url: String) {
    private val extensionless = LiveTvHttpPolicy.parse(url).path.orEmpty().substringAfterLast('/').let {
        it.isEmpty() || !it.contains('.')
    }
    private var attempted = false

    fun tryFallback(unrecognizedContainer: Boolean): Boolean {
        if (!extensionless || attempted || !unrecognizedContainer) return false
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
        require(origin.scheme != "https" || target.scheme == "https") { "Insecure live request" }
        return if (sameOrigin(origin, target)) headers.toMap() else emptyMap()
    }

    fun redirect(from: String, location: String): String {
        val source = parse(from)
        val target = parse(source.resolve(location).toString())
        require(source.scheme != "https" || target.scheme == "https") { "Insecure live redirect" }
        requestHeaders(target.toString())
        return target.toString()
    }

    companion object {
        private val HEADER_NAME = Regex("[!#$%&'*+.^_`|~0-9A-Za-z-]+")
        private val BLOCKED_HEADERS = setOf(
            "host", "connection", "content-length", "transfer-encoding", "te", "trailer",
            "upgrade", "keep-alive", "range", "accept-encoding",
        )

        fun parse(url: String): URI {
            val uri = try { URI(url) } catch (_: Exception) { throw IllegalArgumentException("Invalid live URL") }
            val scheme = uri.scheme?.lowercase(Locale.ROOT)
            require(scheme in setOf("http", "https") && !uri.host.isNullOrEmpty() &&
                uri.rawUserInfo == null && (uri.port == -1 || uri.port in 1..65535)) { "Invalid live URL" }
            return URI(scheme + url.substring(url.indexOf(':')))
        }

        private fun sameOrigin(a: URI, b: URI): Boolean =
            a.scheme == b.scheme && a.host.equals(b.host, ignoreCase = true) && port(a) == port(b)

        private fun port(uri: URI) = if (uri.port != -1) uri.port else if (uri.scheme == "https") 443 else 80
    }
}
