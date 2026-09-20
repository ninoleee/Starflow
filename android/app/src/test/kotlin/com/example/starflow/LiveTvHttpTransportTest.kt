package com.example.starflow

import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URI
import java.util.concurrent.CopyOnWriteArrayList
import java.util.zip.GZIPOutputStream
import org.junit.After
import org.junit.Assert.*
import org.junit.Test

class LiveTvHttpTransportTest {
    private val servers = mutableListOf<ServerSocket>()
    private val workers = mutableListOf<Thread>()
    private val serverErrors = CopyOnWriteArrayList<Throwable>()

    @After
    fun stopServers() {
        servers.forEach { it.close() }
        workers.forEach { it.join(2000) }
        assertTrue("HTTP fixture failures: $serverErrors", serverErrors.isEmpty())
    }

    private fun server(handler: (HttpExchange) -> Unit): String {
        val server = ServerSocket(0, 10, InetAddress.getByName("127.0.0.1"))
        servers.add(server)
        workers.add(Thread {
            while (!server.isClosed) {
                val socket = try { server.accept() } catch (error: IOException) {
                    if (!server.isClosed) serverErrors.add(error)
                    break
                }
                socket.use {
                    try {
                        socket.soTimeout = 2000
                        handler(HttpExchange(socket))
                    } catch (error: Throwable) { serverErrors.add(error) }
                }
            }
        }.apply { isDaemon = true; start() })
        return "http://127.0.0.1:${server.localPort}"
    }

    private class Headers : LinkedHashMap<String, List<String>>() {
        fun set(name: String, value: String) { put(name.lowercase(), listOf(value)) }
        fun getFirst(name: String): String? = get(name.lowercase())?.firstOrNull()
    }

    private class HttpExchange(socket: Socket) {
        val requestHeaders = Headers()
        val responseHeaders = Headers()
        val requestURI: URI
        val responseBody = socket.getOutputStream()

        init {
            val reader = socket.getInputStream().bufferedReader(Charsets.ISO_8859_1)
            requestURI = URI(reader.readLine().split(' ')[1])
            while (true) {
                val line = reader.readLine() ?: break
                if (line.isEmpty()) break
                requestHeaders.set(line.substringBefore(':'), line.substringAfter(':').trim())
            }
        }

        fun sendResponseHeaders(code: Int, length: Long) {
            responseHeaders.set("Content-Length", length.coerceAtLeast(0).toString())
            responseHeaders.set("Connection", "close")
            val headers = buildString {
                append("HTTP/1.1 $code Test\r\n")
                responseHeaders.forEach { (name, values) -> append("$name: ${values.first()}\r\n") }
                append("\r\n")
            }
            responseBody.write(headers.toByteArray(Charsets.ISO_8859_1))
        }
    }

    private fun HttpExchange.reply(body: ByteArray, code: Int = 200) {
        sendResponseHeaders(code, body.size.toLong())
        responseBody.write(body)
    }

    private fun read(transport: LiveTvHttpTransport, url: String, position: Long = 0, length: Long = -1, gzip: Boolean = false): String {
        val response = transport.open(url, position, length, gzip)
        return try { response.stream.bufferedReader().use { it.readText() } } finally { response.connection.disconnect() }
    }

    @Test
    fun `same origin redirect preserves headers but next cross port hop strips every provider header`() {
        val seen = CopyOnWriteArrayList<Map<String, List<String>>>()
        val cdn = server { exchange ->
            seen.add(exchange.requestHeaders.mapKeys { it.key.lowercase() })
            exchange.reply("segment".toByteArray())
        }
        val source = server { exchange ->
            seen.add(exchange.requestHeaders.mapKeys { it.key.lowercase() })
            exchange.responseHeaders.set("Location", if (exchange.requestURI.path == "/start") "/next" else "$cdn/segment")
            exchange.sendResponseHeaders(302, -1)
        }
        val policy = LiveTvHttpPolicy("$source/start", mapOf("Authorization" to "Bearer secret", "Cookie" to "session=secret", "X-Token" to "secret", "Referer" to "$source/private", "User-Agent" to "Provider"))
        assertEquals("segment", read(LiveTvHttpTransport(policy), "$source/start"))
        assertEquals(3, seen.size)
        for (request in seen.take(2)) {
            assertEquals(listOf("Bearer secret"), request["authorization"])
            assertEquals(listOf("session=secret"), request["cookie"])
            assertEquals(listOf("Provider"), request["user-agent"])
        }
        for (name in listOf("authorization", "cookie", "x-token", "referer")) assertNull(seen.last()[name])
        assertEquals(listOf("Starflow"), seen.last()["user-agent"])
    }

    @Test
    fun `independent manifest key and segment data sources apply the same origin policy`() {
        val requests = CopyOnWriteArrayList<String?>()
        val cdn = server { exchange ->
            requests.add(exchange.requestHeaders.getFirst("X-Secret") ?: "absent")
            exchange.reply("data".toByteArray())
        }
        val source = server { exchange ->
            requests.add(exchange.requestHeaders.getFirst("X-Secret"))
            exchange.reply("#EXTM3U".toByteArray())
        }
        val policy = LiveTvHttpPolicy("$source/live", mapOf("X-Secret" to "secret"))
        for (url in listOf("$source/live", "$source/variant", "$cdn/key", "$cdn/segment.ts")) {
            read(LiveTvHttpTransport(policy), url)
        }
        assertEquals(listOf("secret", "secret", "absent", "absent"), requests)
    }

    @Test
    fun `redirect loop is bounded to eleven requests`() {
        val calls = CopyOnWriteArrayList<String>()
        val source = server { exchange ->
            calls.add(exchange.requestURI.path)
            exchange.responseHeaders.set("Location", "/loop")
            exchange.sendResponseHeaders(307, -1)
        }
        val transport = LiveTvHttpTransport(LiveTvHttpPolicy("$source/loop", emptyMap<String, String>()))
        val error = assertThrows(IOException::class.java) { transport.open("$source/loop", 0, -1, false) }
        assertEquals("Too many live redirects", error.message)
        assertEquals(11, calls.size)
    }

    @Test
    fun `range requests validate partial responses and skip when server ignores range`() {
        val ranges = CopyOnWriteArrayList<String>()
        val source = server { exchange ->
            ranges.add(exchange.requestHeaders.getFirst("Range"))
            when (exchange.requestURI.path) {
                "/partial" -> {
                    exchange.responseHeaders.set("Content-Range", "bytes 3-5/6")
                    exchange.reply("def".toByteArray(), 206)
                }
                "/bad" -> {
                    exchange.responseHeaders.set("Content-Range", "bytes 0-2/6")
                    exchange.reply("abc".toByteArray(), 206)
                }
                else -> exchange.reply("abcdef".toByteArray())
            }
        }
        val transport = LiveTvHttpTransport(LiveTvHttpPolicy("$source/live", mapOf("Range" to "bytes=0-1")))
        assertEquals("def", read(transport, "$source/partial", 3, 3))
        assertEquals("def", read(transport, "$source/full", 3, 3))
        assertThrows(IOException::class.java) { transport.open("$source/bad", 3, 3, false) }
        assertThrows(EOFException::class.java) { transport.open("$source/full", 10, -1, false) }
        assertEquals(listOf("bytes=3-5", "bytes=3-5", "bytes=3-5", "bytes=10-"), ranges)
    }

    @Test
    fun `gzip is decoded with unknown decompressed length using API23 compatible header parsing`() {
        val bytes = ByteArrayOutputStream().apply {
            GZIPOutputStream(this).use { it.write("#EXTM3U\n#EXT-X-ENDLIST\n".toByteArray()) }
        }.toByteArray()
        val source = server { exchange ->
            exchange.responseHeaders.set("Content-Encoding", "gzip")
            exchange.reply(bytes)
        }
        val response = LiveTvHttpTransport(LiveTvHttpPolicy(source, emptyMap<String, String>())).open(source, 0, -1, true)
        try {
            assertEquals(-1L, response.length)
            assertEquals("#EXTM3U\n#EXT-X-ENDLIST\n", response.stream.bufferedReader().use { it.readText() })
        } finally { response.connection.disconnect() }
    }

    @Test
    fun `HTTP errors do not include private response bodies or URLs`() {
        val source = server { exchange -> exchange.reply("secret body".toByteArray(), 403) }
        val transport = LiveTvHttpTransport(LiveTvHttpPolicy(source, emptyMap<String, String>()))
        val error = assertThrows(IOException::class.java) { transport.open("$source/private?token=secret", 0, -1, false) }
        assertEquals("Live HTTP status 403", error.message)
    }
}
