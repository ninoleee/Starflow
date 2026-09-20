package com.example.starflow

import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.InterruptedIOException
import java.net.HttpURLConnection
import java.net.URL

/** No automatic redirects: every manifest, key, segment and redirect gets an origin check. */
internal class LiveTvHttpTransport(private val policy: LiveTvHttpPolicy) {
    data class Response(
        val connection: HttpURLConnection,
        val stream: InputStream,
        val length: Long,
    )

    fun open(url: String, position: Long, length: Long, gzip: Boolean): Response {
        var target = url
        repeat(11) { redirectCount ->
            val headers = try { policy.requestHeaders(target) } catch (_: IllegalArgumentException) {
                throw IOException("Invalid live request")
            }
            val connection = URL(target).openConnection() as HttpURLConnection
            try {
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 10000
                connection.readTimeout = 10000
                connection.useCaches = false
                connection.setRequestProperty("User-Agent", "Starflow")
                headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
                // Range is controlled by Media3, never by subscription-supplied headers.
                if (position > 0 || length >= 0) {
                    if (length > 0 && position > Long.MAX_VALUE - (length - 1)) throw IOException("Invalid live byte range")
                    val end = if (length >= 0) (position + length - 1).toString() else ""
                    connection.setRequestProperty("Range", "bytes=$position-$end")
                }
                connection.setRequestProperty("Accept-Encoding", if (gzip) "gzip" else "identity")
                val code = connection.responseCode
                if (code in setOf(300, 301, 302, 303, 307, 308)) {
                    if (redirectCount == 10) throw IOException("Too many live redirects")
                    val location = connection.getHeaderField("Location") ?: throw IOException("Missing live redirect")
                    target = try { policy.redirect(target, location) } catch (_: IllegalArgumentException) {
                        throw IOException("Invalid live redirect")
                    }
                    connection.disconnect()
                    return@repeat
                }
                if (code !in 200..299) throw IOException("Live HTTP status $code")
                if (code == 206) {
                    val rangeStart = connection.getHeaderField("Content-Range")
                        ?.let { Regex("bytes (\\d+)-\\d+/.*").matchEntire(it)?.groupValues?.get(1)?.toLongOrNull() }
                    if (rangeStart != position) throw IOException("Invalid live byte range")
                }
                val compressed = connection.getHeaderField("Content-Encoding").equals("gzip", true)
                val stream = if (compressed) java.util.zip.GZIPInputStream(connection.inputStream) else connection.inputStream
                val skip = if (code == 200) position else 0L
                try {
                    skipFully(stream, skip)
                } catch (error: Exception) {
                    stream.close()
                    throw error
                }
                // getContentLengthLong is API 24; parse the header to retain API 23 support.
                val contentLength = connection.getHeaderField("Content-Length")?.toLongOrNull()?.takeIf { it >= 0 }
                val remaining = if (length >= 0) length else if (!compressed && contentLength != null) {
                    (contentLength - skip).coerceAtLeast(0)
                } else -1L
                return Response(connection, stream, remaining)
            } catch (error: Exception) {
                connection.disconnect()
                throw error
            }
        }
        throw IOException("Too many live redirects")
    }

    private fun skipFully(stream: InputStream, count: Long) {
        var remaining = count
        val buffer = ByteArray(4096)
        while (remaining > 0) {
            if (Thread.currentThread().isInterrupted) throw InterruptedIOException()
            val read = stream.read(buffer, 0, minOf(remaining, buffer.size.toLong()).toInt())
            if (read == -1) throw EOFException("Live byte range unavailable")
            remaining -= read
        }
    }
}
