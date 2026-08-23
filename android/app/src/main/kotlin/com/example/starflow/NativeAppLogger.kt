package com.example.starflow

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Process
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.system.exitProcess

object NativeAppLogger {
    private const val DEFAULT_MAX_BYTES = 20 * 1024 * 1024
    private const val MIN_NATIVE_BYTES = 16 * 1024
    private const val MAX_NATIVE_BYTES = 4 * 1024 * 1024
    private const val MAX_EXIT_TRACE_READ_CHARS = 768 * 1024
    private const val MAX_EXIT_TRACE_LOG_CHARS = 32_000
    private const val MAX_EXIT_TRACE_THREADS = 8
    private const val MAX_MAIN_THREAD_LOG_CHARS = 6_000
    private const val MAX_SECONDARY_THREAD_LOG_CHARS = 3_200
    private const val CONFIG_FILE_NAME = "starflow-native-logging.json"
    private const val PLAYBACK_SESSION_FILE_NAME = "starflow-native-playback-session.json"
    private const val EXIT_STATE_PREFERENCES = "starflow_native_exit_state"
    private const val LAST_EXIT_TIMESTAMP_KEY = "last_exit_timestamp"

    private val timestampFormatter = SimpleDateFormat(
        "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
        Locale.US,
    ).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }
    private val bearerPattern = Regex(
        "Bearer\\s+[A-Za-z0-9._~+\\-/]+=*",
        RegexOption.IGNORE_CASE,
    )
    private val inlineSecretPattern = Regex(
        "((?:access[_-]?token|token|api[_-]?key|auth[_-]?key|password|cookie|authorization|secret|sign(?:ature)?|session)=)[^&\\s,;]+",
        RegexOption.IGNORE_CASE,
    )
    private val traceThreadHeaderPattern = Regex(
        pattern = "(?m)^\"([^\"]+)\"\\s+(?:daemon\\s+)?prio=",
    )

    @Volatile
    private var applicationContext: Context? = null

    @Volatile
    private var installed = false

    fun install(context: Context) {
        applicationContext = context.applicationContext
        if (installed) {
            return
        }
        synchronized(this) {
            if (installed) {
                return
            }
            installed = true
            recordUnclosedPlaybackSession(context.applicationContext)
            recordPreviousProcessExit(context.applicationContext)
            val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
            Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
                log(
                    level = "error",
                    category = "native.uncaught",
                    message = "Uncaught native exception on ${thread.name}",
                    error = throwable,
                    forceSync = true,
                )
                if (previousHandler != null) {
                    previousHandler.uncaughtException(thread, throwable)
                } else {
                    Process.killProcess(Process.myPid())
                    exitProcess(10)
                }
            }
        }
    }

    fun info(category: String, message: String) {
        log(level = "info", category = category, message = message)
    }

    fun warning(category: String, message: String, error: Throwable? = null) {
        log(
            level = "warning",
            category = category,
            message = message,
            error = error,
        )
    }

    fun error(category: String, message: String, error: Throwable? = null) {
        log(
            level = "error",
            category = category,
            message = message,
            error = error,
            forceSync = true,
        )
    }

    fun markPlaybackStarted(fields: Map<String, Any?> = emptyMap()) {
        val context = applicationContext ?: return
        val config = readConfig(context)
        if (!config.enabled ||
            (!config.recordedLevels.contains("warning") &&
                !config.recordedLevels.contains("error"))
        ) {
            clearPlaybackSessionMarker(context)
            return
        }
        try {
            val marker = JSONObject().apply {
                put("startedAt", timestampFormatter.format(Date()))
                put("startedAtMs", System.currentTimeMillis())
                put("fields", JSONObject(fields.mapValues { (_, value) ->
                    sanitize(value?.toString().orEmpty(), 1_000)
                }))
            }
            val file = File(context.filesDir, PLAYBACK_SESSION_FILE_NAME)
            FileOutputStream(file, false).use { output ->
                output.write(marker.toString().toByteArray(Charsets.UTF_8))
                output.flush()
                output.fd.sync()
            }
        } catch (_: Throwable) {
            // A diagnostic marker must not interfere with playback startup.
        }
    }

    fun markPlaybackEnded() {
        applicationContext?.let(::clearPlaybackSessionMarker)
    }

    @Synchronized
    fun log(
        level: String,
        category: String,
        message: String,
        fields: Map<String, Any?> = emptyMap(),
        error: Throwable? = null,
        nativeStackTrace: String = "",
        forceSync: Boolean = false,
    ) {
        val context = applicationContext ?: return
        val config = readConfig(context)
        if (!config.enabled || !config.recordedLevels.contains(level)) {
            return
        }
        try {
            val record = JSONObject().apply {
                put("timestamp", timestampFormatter.format(Date()))
                put("level", level)
                put("category", sanitize(category, 160))
                put("message", sanitize(message, 4_000))
                if (fields.isNotEmpty()) {
                    put(
                        "fields",
                        JSONObject(
                            fields.mapValues { (_, value) ->
                                sanitize(value?.toString().orEmpty(), 2_000)
                            },
                        ),
                    )
                }
                if (error != null) {
                    put("error", sanitize(error.toString(), 8_000))
                    put("stackTrace", sanitize(stackTrace(error), 12_000))
                } else if (nativeStackTrace.isNotBlank()) {
                    put(
                        "stackTrace",
                        sanitize(nativeStackTrace, MAX_EXIT_TRACE_LOG_CHARS),
                    )
                }
            }
            appendRecord(
                context = context,
                line = record.toString() + "\n",
                maxBytes = config.maxBytes,
                forceSync = forceSync,
            )
        } catch (_: Throwable) {
            // Crash logging must never trigger another application failure.
        }
    }

    private fun readConfig(context: Context): NativeLogConfig {
        val file = File(context.filesDir, CONFIG_FILE_NAME)
        if (!file.exists()) {
            return NativeLogConfig()
        }
        return try {
            val json = JSONObject(file.readText())
            val levelsArray = json.optJSONArray("recordedLevels") ?: JSONArray()
            val levels = buildSet {
                for (index in 0 until levelsArray.length()) {
                    val value = levelsArray.optString(index).trim()
                    if (value.isNotEmpty()) {
                        add(value)
                    }
                }
            }
            NativeLogConfig(
                enabled = json.optBoolean("enabled", true),
                maxBytes = json.optInt("maxBytes", DEFAULT_MAX_BYTES)
                    .coerceAtLeast(64 * 1024),
                recordedLevels = levels,
            )
        } catch (_: Throwable) {
            NativeLogConfig()
        }
    }

    private fun appendRecord(
        context: Context,
        line: String,
        maxBytes: Int,
        forceSync: Boolean,
    ) {
        val directory = File(context.filesDir, "logs").apply { mkdirs() }
        val file = File(directory, "starflow-native.log")
        val limit = (maxBytes / 5).coerceIn(MIN_NATIVE_BYTES, MAX_NATIVE_BYTES)
        var bytes = line.toByteArray(Charsets.UTF_8)
        if (bytes.size > limit) {
            bytes = bytes.takeLast(limit).toByteArray()
        }
        val retainedBytes = (limit - bytes.size).coerceAtLeast(0)
        if (file.exists() && file.length() + bytes.size > limit) {
            val existing = file.readBytes()
            file.writeBytes(existing.takeLast(retainedBytes).toByteArray())
        }
        FileOutputStream(file, true).use { output ->
            output.write(bytes)
            output.flush()
            if (forceSync) {
                output.fd.sync()
            }
        }
    }

    private fun recordPreviousProcessExit(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return
        }
        try {
            val activityManager = context.getSystemService(ActivityManager::class.java)
            val exit = activityManager
                .getHistoricalProcessExitReasons(context.packageName, 0, 8)
                .maxByOrNull { it.timestamp }
                ?: return
            val preferences = context.getSharedPreferences(
                EXIT_STATE_PREFERENCES,
                Context.MODE_PRIVATE,
            )
            val lastTimestamp = preferences.getLong(LAST_EXIT_TIMESTAMP_KEY, 0L)
            if (exit.timestamp <= lastTimestamp) {
                return
            }
            preferences.edit().putLong(LAST_EXIT_TIMESTAMP_KEY, exit.timestamp).apply()
            if (!isDiagnosticExitReason(exit.reason)) {
                return
            }
            val trace = readExitTrace(exit)
            val fields = linkedMapOf<String, Any?>(
                "reason" to exitReasonLabel(exit.reason),
                "reasonCode" to exit.reason,
                "status" to exit.status,
                "importance" to exit.importance,
                "pssKb" to exit.pss,
                "rssKb" to exit.rss,
                "timestampMs" to exit.timestamp,
                "description" to exit.description.orEmpty(),
                "traceAvailable" to trace.isNotBlank(),
            )
            log(
                level = if (exit.reason == ApplicationExitInfo.REASON_LOW_MEMORY) {
                    "warning"
                } else {
                    "error"
                },
                category = "native.previous-exit",
                message = "Previous process ended: ${exitReasonLabel(exit.reason)}",
                fields = fields,
                nativeStackTrace = trace,
                forceSync = true,
            )
        } catch (_: Throwable) {
            // Exit history is best-effort and varies across Android vendors.
        }
    }

    private fun recordUnclosedPlaybackSession(context: Context) {
        val file = File(context.filesDir, PLAYBACK_SESSION_FILE_NAME)
        if (!file.exists()) {
            return
        }
        val marker = try {
            file.readText().take(8_000)
        } catch (_: Throwable) {
            ""
        }
        clearPlaybackSessionMarker(context)
        log(
            level = "warning",
            category = "native.previous-playback",
            message = "Previous native playback did not close cleanly",
            fields = mapOf("session" to marker),
            forceSync = true,
        )
    }

    private fun clearPlaybackSessionMarker(context: Context) {
        try {
            val file = File(context.filesDir, PLAYBACK_SESSION_FILE_NAME)
            if (file.exists()) {
                file.delete()
            }
        } catch (_: Throwable) {
            // Marker cleanup is best-effort.
        }
    }

    private fun isDiagnosticExitReason(reason: Int): Boolean {
        return reason == ApplicationExitInfo.REASON_CRASH ||
            reason == ApplicationExitInfo.REASON_CRASH_NATIVE ||
            reason == ApplicationExitInfo.REASON_ANR ||
            reason == ApplicationExitInfo.REASON_LOW_MEMORY ||
            reason == ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE
    }

    private fun exitReasonLabel(reason: Int): String {
        return when (reason) {
            ApplicationExitInfo.REASON_CRASH -> "crash"
            ApplicationExitInfo.REASON_CRASH_NATIVE -> "native-crash"
            ApplicationExitInfo.REASON_ANR -> "anr"
            ApplicationExitInfo.REASON_LOW_MEMORY -> "low-memory"
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "excessive-resource"
            else -> "reason-$reason"
        }
    }

    private fun readExitTrace(exit: ApplicationExitInfo): String {
        return try {
            exit.traceInputStream?.bufferedReader()?.use { reader ->
                val trace = StringBuilder()
                val buffer = CharArray(8_192)
                while (trace.length < MAX_EXIT_TRACE_READ_CHARS) {
                    val remaining = MAX_EXIT_TRACE_READ_CHARS - trace.length
                    val count = reader.read(buffer, 0, minOf(buffer.size, remaining))
                    if (count <= 0) {
                        break
                    }
                    trace.append(buffer, 0, count)
                }
                summarizeExitTrace(trace.toString())
            }.orEmpty()
        } catch (_: Throwable) {
            ""
        }
    }

    private fun summarizeExitTrace(rawTrace: String): String {
        if (rawTrace.isBlank()) {
            return ""
        }
        val matches = traceThreadHeaderPattern.findAll(rawTrace).toList()
        if (matches.isEmpty()) {
            return rawTrace.take(MAX_EXIT_TRACE_LOG_CHARS)
        }
        val threads = matches.mapIndexed { index, match ->
            val start = match.range.first
            val end = matches.getOrNull(index + 1)?.range?.first ?: rawTrace.length
            ExitTraceThread(
                name = match.groupValues[1],
                body = rawTrace.substring(start, end).trim(),
                sourceIndex = index,
            )
        }
        val prioritized = threads
            .map { thread -> thread to exitTraceThreadScore(thread) }
            .filter { (_, score) -> score > 0 }
            .sortedWith(
                compareByDescending<Pair<ExitTraceThread, Int>> { (_, score) -> score }
                    .thenBy { (thread, _) -> thread.sourceIndex },
            )
            .take(MAX_EXIT_TRACE_THREADS)
            .map { (thread, _) -> thread }
            .ifEmpty { threads.take(MAX_EXIT_TRACE_THREADS) }
        val header = rawTrace.take(matches.first().range.first).take(2_000).trim()
        return buildString {
            if (header.isNotEmpty()) {
                append("--- trace header ---\n")
                append(header)
            }
            for (thread in prioritized) {
                if (isNotEmpty()) {
                    append("\n\n")
                }
                append("--- thread: ")
                append(thread.name)
                append(" ---\n")
                val limit = if (thread.name == "main") {
                    MAX_MAIN_THREAD_LOG_CHARS
                } else {
                    MAX_SECONDARY_THREAD_LOG_CHARS
                }
                append(thread.body.take(limit))
            }
        }.take(MAX_EXIT_TRACE_LOG_CHARS)
    }

    private fun exitTraceThreadScore(thread: ExitTraceThread): Int {
        val name = thread.name.lowercase(Locale.US)
        return when {
            name == "main" -> 1_000
            name.endsWith(".ui") || name == "ui" -> 980
            name.contains("flutter") -> 960
            name.contains("dart") -> 940
            name.contains("raster") -> 920
            name.endsWith(".io") || name.startsWith("io.") -> 900
            name.contains("platform") -> 880
            name.contains("render") || name.contains("hwui") -> 820
            name.contains("binder") -> 760
            name.contains("pool") || name.contains("worker") -> 720
            thread.body.contains("Runnable") -> 600
            else -> 0
        }
    }

    private fun stackTrace(error: Throwable): String {
        val writer = StringWriter()
        PrintWriter(writer).use { error.printStackTrace(it) }
        return writer.toString()
    }

    private fun sanitize(value: String, maxLength: Int): String {
        var sanitized = value.replace(bearerPattern, "Bearer <redacted>")
        sanitized = sanitized.replace(inlineSecretPattern) { match ->
            "${match.groupValues[1]}<redacted>"
        }
        return if (sanitized.length <= maxLength) {
            sanitized
        } else {
            sanitized.take(maxLength) + "…"
        }
    }

    private data class NativeLogConfig(
        val enabled: Boolean = true,
        val maxBytes: Int = DEFAULT_MAX_BYTES,
        val recordedLevels: Set<String> = setOf("trace", "info", "warning", "error"),
    )

    private data class ExitTraceThread(
        val name: String,
        val body: String,
        val sourceIndex: Int,
    )
}
