package com.example.starflow

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.CopyOnWriteArrayList
import java.util.zip.GZIPOutputStream
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackHttpDataSourceTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()
    private val servers = mutableListOf<ServerSocket>()
    private val workers = mutableListOf<Thread>()
    private val failures = CopyOnWriteArrayList<Throwable>()
    private val credentials = mapOf(
        "Authorization" to "Basic c3ludGhldGljOnRlc3Q=",
        "Cookie" to "session=synthetic", "X-Emby-Token" to "synthetic-token",
        "Referer" to "https://private.test/path", "User-Agent" to "ProviderAgent",
    )
    private data class Request(val path: String, val headers: Map<String, String>)
    private data class Reply(val status: Int = 200, val body: ByteArray = "video".toByteArray(),
        val headers: Map<String, String> = emptyMap())

    private fun server(handle: (Request) -> Reply): String {
        val server = ServerSocket(0, 10, InetAddress.getByName("127.0.0.1"))
        servers.add(server)
        workers.add(Thread {
            while (!server.isClosed) {
                val socket = try { server.accept() } catch (error: IOException) {
                    if (!server.isClosed) failures.add(error)
                    break
                }
                socket.use {
                    try {
                        socket.soTimeout = 3000
                        val reader = socket.getInputStream().bufferedReader(Charsets.ISO_8859_1)
                        val path = reader.readLine().split(' ')[1]
                        val headers = linkedMapOf<String, String>()
                        while (true) {
                            val line = reader.readLine() ?: break
                            if (line.isEmpty()) break
                            headers[line.substringBefore(':').lowercase()] = line.substringAfter(':').trim()
                        }
                        val reply = handle(Request(path, headers))
                        val output = socket.getOutputStream()
                        output.write(buildString {
                            append("HTTP/1.1 ${reply.status} Test\r\nConnection: close\r\n")
                            append("Content-Length: ${reply.body.size}\r\n")
                            reply.headers.forEach { (name, value) -> append("$name: $value\r\n") }
                            append("\r\n")
                        }.toByteArray(Charsets.ISO_8859_1))
                        output.write(reply.body)
                    } catch (error: Throwable) { failures.add(error) }
                }
            }
        }.apply { isDaemon = true; start() })
        return "http://127.0.0.1:${server.localPort}"
    }

    @After fun closeServers() {
        servers.forEach { it.close() }
        workers.forEach { it.join(4000) }
        assertTrue("Loopback fixture errors: $failures", failures.isEmpty())
    }

    private fun spec(url: String, position: Long = 0, length: Long = C.LENGTH_UNSET.toLong(),
        headers: Map<String, String> = emptyMap(), gzip: Boolean = false): DataSpec {
        val uri = mock(Uri::class.java)
        `when`(uri.toString()).thenReturn(url)
        return DataSpec.Builder().setUri(uri).setPosition(position).setLength(length)
            .setHttpRequestHeaders(headers).setFlags(if (gzip) DataSpec.FLAG_ALLOW_GZIP else 0).build()
    }

    private fun read(source: NativePlaybackHttpDataSource, spec: DataSpec): String {
        try {
            source.open(spec)
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(4)
            while (true) {
                val count = source.read(buffer, 0, buffer.size)
                if (count == C.RESULT_END_OF_INPUT) break
                output.write(buffer, 0, count)
            }
            return output.toString("UTF-8")
        } finally { source.close() }
    }

    private fun assertForeign(request: Request) {
        for (name in credentials.keys) {
            if (name == "User-Agent") continue
            assertNull("Leaked $name to ${request.path}", request.headers[name.lowercase()])
        }
        assertNull(request.headers["x-request-secret"])
        assertEquals("Starflow", request.headers["user-agent"])
    }

    @Test fun sameOriginThenForeignPortRedirectStripsAllCredentialsButKeepsRange() {
        val seen = CopyOnWriteArrayList<Request>()
        val foreign = server { request ->
            seen.add(request)
            Reply(206, "def".toByteArray(), mapOf("Content-Range" to "bytes 3-5/6"))
        }
        val origin = server { request ->
            seen.add(request)
            Reply(302, headers = mapOf("Location" to if (request.path == "/start") "/next" else "$foreign/file"))
        }
        val source = NativePlaybackHttpDataSource("$origin/start", credentials)
        assertEquals("def", read(source, spec("$origin/start", 3, 3, mapOf("X-Request-Secret" to "synthetic"))))
        assertEquals(3, seen.size)
        seen.take(2).forEach {
            assertEquals(credentials["Authorization"], it.headers["authorization"])
            assertEquals("synthetic", it.headers["x-request-secret"])
        }
        assertForeign(seen.last())
        assertTrue(seen.all { it.headers["range"] == "bytes=3-5" })
    }

    @Test fun foreignHostAndIndependentManifestKeySegmentAndSubtitleDoNotInheritHeaders() {
        val seen = CopyOnWriteArrayList<Request>()
        val origin = server { request -> seen.add(request); Reply() }
        val foreign = origin.replace("127.0.0.1", "localhost")
        for (path in listOf("/variant.m3u8", "/key", "/segment.ts", "/subtitle.vtt")) {
            val source = NativePlaybackHttpDataSource("$origin/video", credentials)
            assertEquals("video", read(source, spec("$foreign$path", headers = credentials)))
        }
        assertEquals(4, seen.size)
        seen.forEach(::assertForeign)
    }

    @Test fun everyHopChecksOriginalOriginIncludingForeignBackToOrigin() {
        val seen = CopyOnWriteArrayList<Request>()
        lateinit var foreign: String
        val origin = server { request ->
            seen.add(request)
            if (request.path == "/start") Reply(307, headers = mapOf("Location" to "$foreign/hop")) else Reply()
        }
        foreign = server { request ->
            seen.add(request)
            Reply(308, headers = mapOf("Location" to "$origin/final"))
        }
        assertEquals("video", read(NativePlaybackHttpDataSource(origin, credentials), spec("$origin/start")))
        assertEquals(3, seen.size)
        assertForeign(seen[1])
        assertEquals(credentials["Authorization"], seen.last().headers["authorization"])
    }

    @Test fun schemeHostAndEffectivePortAreAllPartOfOriginAndDowngradeIsRejected() {
        val policy = LiveTvHttpPolicy("http://EXAMPLE.test/video", credentials)
        assertEquals(credentials["Authorization"], policy.requestHeaders("http://example.test:80/key")["authorization"])
        assertTrue(policy.requestHeaders("http://example.test:81/key").isEmpty())
        assertTrue(policy.requestHeaders("http://cdn.test/key").isEmpty())
        assertTrue(policy.requestHeaders("https://example.test:80/key").isEmpty())
        val secure = LiveTvHttpPolicy("https://example.test/video", credentials)
        assertThrows(IllegalArgumentException::class.java) { secure.redirect("https://example.test/video", "http://example.test/video") }
        assertThrows(IllegalArgumentException::class.java) { policy.redirect("http://example.test/video", "http://user:secret@example.test/file") }
        assertThrows(IllegalArgumentException::class.java) { policy.redirect("http://example.test/video", "file:///private") }
    }

    @Test fun sameOriginNetworkSubtitlesRetainAuthentication() {
        val seen = CopyOnWriteArrayList<Request>()
        val origin = server { request -> seen.add(request); Reply(body = "WEBVTT".toByteArray()) }
        assertEquals("WEBVTT", read(NativePlaybackHttpDataSource("$origin/video", credentials),
            spec("$origin/subtitle.vtt")))
        assertEquals(credentials["Authorization"], seen.single().headers["authorization"])
        assertEquals(credentials["Cookie"], seen.single().headers["cookie"])
    }

    @Test fun secureOriginRejectsPlainHttpBeforeSendingAnyCredentials() {
        val seen = CopyOnWriteArrayList<Request>()
        val origin = server { request -> seen.add(request); Reply() }
        val source = NativePlaybackHttpDataSource(origin.replace("http:", "https:"), credentials)
        val error = assertThrows(LiveTvHttpTransport.PolicyException::class.java) { read(source, spec(origin)) }
        assertEquals(MediaHttpRejection.HTTPS_DOWNGRADE, error.rejection.reason)
        assertEquals("Media HTTP request rejected: HTTPS_DOWNGRADE", error.message)
        assertTrue(seen.isEmpty())
    }

    @Test fun malformedPlaybackRequestRetainsOnlySafeReason() {
        val source = NativePlaybackHttpDataSource("file:///local/video.mkv", credentials)
        val error = assertThrows(LiveTvHttpTransport.PolicyException::class.java) {
            read(source, spec("https://cdn.test/secret%ZZ?token=secret"))
        }
        assertEquals(MediaHttpRejection.MALFORMED_URL, error.rejection.reason)
        assertFalse(error.stackTraceToString().contains("secret"))
    }

    @Test fun hlsResourceAndRedirectUseTheSameEncodedUrlAsCredentialValidation() {
        val seen = CopyOnWriteArrayList<Request>()
        val foreign = server { request -> seen.add(request); Reply() }
        val origin = server { request ->
            seen.add(request)
            if (request.path.startsWith("/segment")) {
                Reply(302, headers = mapOf("Location" to "$foreign/final [1].ts?auth=a|b&sig=%2f+%25"))
            } else Reply()
        }
        val source = NativePlaybackHttpDataSource("$origin/master.m3u8", credentials)
        assertEquals("video", read(source, spec("$origin/segment [1].ts?auth=a|b&sig=%2f+%25")))
        assertEquals("/segment%20%5B1%5D.ts?auth=a%7Cb&sig=%2f+%25", seen[0].path)
        assertEquals(credentials["Cookie"], seen[0].headers["cookie"])
        assertEquals("/final%20%5B1%5D.ts?auth=a%7Cb&sig=%2f+%25", seen[1].path)
        assertForeign(seen[1])
    }

    @Test fun quarkOssProcessBracesAreEncodedBeforeJavaUriAndHttpOpen() {
        val seen = CopyOnWriteArrayList<Request>()
        val origin = server { request -> seen.add(request); Reply() }
        val source = NativePlaybackHttpDataSource("$origin/media.m3u8", credentials)
        val raw = "$origin/media-0.ts?auth_key=a&" +
            "x-oss-process=if_status_eq_404{hls/ts,from_L3F2}&token=b"
        assertEquals("video", read(source, spec(raw)))
        assertEquals(
            "/media-0.ts?auth_key=a&" +
                "x-oss-process=if_status_eq_404%7Bhls/ts,from_L3F2%7D&token=b",
            seen.single().path,
        )
        assertEquals(credentials["Cookie"], seen.single().headers["cookie"])
    }

    @Test fun ignoredRangeGzipAndExactEndOfFileKeepPlaybackCompatibility() {
        val zipped = ByteArrayOutputStream().apply {
            GZIPOutputStream(this).use { it.write("subtitle".toByteArray()) }
        }.toByteArray()
        val origin = server { request -> when (request.path) {
            "/gzip" -> Reply(body = zipped, headers = mapOf("Content-Encoding" to "gzip"))
            "/eof" -> Reply(416, headers = mapOf("Content-Range" to "bytes */6"))
            else -> Reply(body = "abcdef".toByteArray())
        } }
        val source = NativePlaybackHttpDataSource(origin, credentials)
        assertEquals("de", read(source, spec("$origin/full", 3, 2)))
        assertEquals("subtitle", read(source, spec("$origin/gzip", gzip = true)))
        assertEquals("", read(source, spec("$origin/eof", 6)))
    }

    @Test fun statusCodesSurviveForAddressRefreshAndRetries() {
        val origin = server { request -> Reply(request.path.drop(1).toInt(), "private response".toByteArray()) }
        for (status in listOf(401, 403, 404, 429, 500, 503)) {
            val source = NativePlaybackHttpDataSource(origin, credentials)
            val error = assertThrows(IOException::class.java) { read(source, spec("$origin/$status")) }
            assertEquals(status, NativePlaybackErrorPolicy.httpResponseCode(error))
            assertFalse(error.message.orEmpty().contains("private response"))
        }
    }

    @Test fun transferListenerSeesBytesAndOneEndPerOpen() {
        val origin = server { Reply() }
        val listener = mock(TransferListener::class.java)
        var bytesTransferred = 0
        doAnswer { call -> bytesTransferred += call.getArgument<Int>(3); null }
            .`when`(listener).onBytesTransferred(any(), any(), eq(true), anyInt())
        val source = NativePlaybackHttpDataSource(origin, credentials)
        source.addTransferListener(listener)
        val request = spec(origin)
        assertEquals("video", read(source, request))
        source.close()
        verify(listener).onTransferInitializing(source, request, true)
        verify(listener).onTransferStart(source, request, true)
        assertEquals(5, bytesTransferred)
        verify(listener).onTransferEnd(source, request, true)
    }
}
