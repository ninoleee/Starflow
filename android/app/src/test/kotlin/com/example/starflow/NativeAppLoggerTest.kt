package com.example.starflow

import android.content.Context
import java.io.File
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class NativeAppLoggerTest {
    @Test
    fun ordinaryLogsUseWriterAndRotateCompleteTailRecords() {
        val directory = Files.createTempDirectory("starflow-native-logs-").toFile()
        val context = mock(Context::class.java)
        `when`(context.filesDir).thenReturn(directory)
        val contextField = NativeAppLogger::class.java.getDeclaredField("applicationContext")
            .apply { isAccessible = true }
        val configField = NativeAppLogger::class.java.getDeclaredField("cachedConfig")
            .apply { isAccessible = true }
        val writer = NativeAppLogger::class.java.getDeclaredField("writer")
            .apply { isAccessible = true }.get(NativeAppLogger) as ThreadPoolExecutor
        val previous = contextField.get(NativeAppLogger)
        val previousConfig = configField.get(NativeAppLogger)
        try {
            File(directory, "starflow-native-logging.json").writeText(
                """{"enabled":true,"maxBytes":65536,"recordedLevels":["info"]}""",
            )
            contextField.set(NativeAppLogger, context)
            configField.set(NativeAppLogger, null)
            val held = CountDownLatch(1)
            val release = CountDownLatch(1)
            writer.execute {
                held.countDown()
                release.await(5, TimeUnit.SECONDS)
            }
            assertTrue(held.await(5, TimeUnit.SECONDS))
            try {
                repeat(100) { index ->
                    NativeAppLogger.info("test", "record-$index-" + "x".repeat(600))
                }
                assertFalse(File(directory, "logs/starflow-native.log").exists())
            } finally {
                release.countDown()
            }
            val finished = CountDownLatch(1)
            writer.execute { finished.countDown() }
            assertTrue(finished.await(10, TimeUnit.SECONDS))
            val file = File(directory, "logs/starflow-native.log")
            assertTrue(file.length() <= 16 * 1024)
            val records = file.readLines().filter { it.isNotBlank() }.map(::JSONObject)
            assertTrue(records.isNotEmpty())
            assertTrue(records.last().getString("message").startsWith("record-99-"))
        } finally {
            contextField.set(NativeAppLogger, previous)
            configField.set(NativeAppLogger, previousConfig)
            directory.deleteRecursively()
        }
    }
}
