package com.example.starflow

import android.content.SharedPreferences
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

internal class NativePlaybackMemoryStore(
    private val readSnapshot: () -> String?,
    private val writeSnapshot: (String, Boolean) -> Boolean,
    private val now: () -> String = NativePlaybackFormatting::isoNow,
    private val log: (String) -> Unit = { NativePlaybackFormatting.logPlayback(it) },
    private val decodeSnapshot: (String) -> JSONObject = ::JSONObject,
    private val backgroundPreferences: Boolean = false,
    private val onPersisted: () -> Unit = {},
) {
    private var cachedRaw: String? = null
    private var cachedSnapshot: JSONObject? = null
    private var maximumTimestamp = 0L
    private val pendingLock = Any()
    private val pendingProgress = mutableMapOf<String, () -> Unit>()
    private val pendingTokens = mutableMapOf<String, Any>()
    @Volatile private var publishedSkips: Map<String, String>? = null
    @Volatile private var publishedRaw: String? = null
    private val refreshPending = AtomicBoolean(false)

    private fun publishReadView(snapshot: JSONObject, raw: String?) {
        val skips = snapshot.optJSONObject("skipPreferences") ?: JSONObject()
        publishedSkips = skips.keys().asSequence().associateWith {
            skips.optJSONObject(it)?.toString() ?: "{}"
        }
        publishedRaw = raw
    }

    fun peekSeriesSkipPreference(seriesKey: String): JSONObject? {
        val current = publishedSkips ?: return loadSeriesSkipPreference(seriesKey)
        if (readSnapshot() != publishedRaw && refreshPending.compareAndSet(false, true)) {
            writer.execute {
                try { loadPlaybackSnapshot() } finally { refreshPending.set(false) }
            }
        }
        return current[seriesKey]?.let(::JSONObject)
    }

    companion object {
        private val isWriter = ThreadLocal<Boolean>()
        private val writer = Executors.newSingleThreadExecutor { runnable ->
            Thread({ isWriter.set(true); runnable.run() }, "starflow-playback-memory").apply { isDaemon = true }
        }

        fun readShared(preferences: SharedPreferences, completion: (String?) -> Unit) {
            writer.execute { completion(preferences.getString(PLAYBACK_MEMORY_STORAGE_KEY, null)) }
        }

        fun compareAndSetShared(preferences: SharedPreferences, expected: String?, value: String?,
            completion: (Boolean?, Throwable?) -> Unit) {
            writer.execute {
                try {
                    if (preferences.getString(PLAYBACK_MEMORY_STORAGE_KEY, null) != expected) {
                        completion(false, null)
                    } else {
                        val editor = preferences.edit()
                        if (value == null) editor.remove(PLAYBACK_MEMORY_STORAGE_KEY)
                        else editor.putString(PLAYBACK_MEMORY_STORAGE_KEY, value)
                        check(editor.commit()) { "Playback memory persistence failed" }
                        completion(true, null)
                    }
                } catch (error: Throwable) { completion(null, error) }
            }
        }
    }

    private fun <T> readOrdered(operation: () -> T): T =
        if (isWriter.get() == true) operation() else writer.submit<T> { operation() }.get()

    private fun writePreference(operation: () -> Unit) {
        if (backgroundPreferences && isWriter.get() != true) writer.execute(operation)
        else readOrdered(operation)
    }

    fun enqueuePlaybackEntry(
        targetJson: String, itemKey: String, seriesKey: String,
        positionMs: Long, durationMs: Long, synchronous: Boolean,
        completedByAutoSkip: Boolean = false,
    ) {
        val operation = {
            savePlaybackEntry(targetJson, itemKey, seriesKey, positionMs, durationMs,
                synchronous, completedByAutoSkip)
        }
        synchronized(pendingLock) {
            if (synchronous) {
                pendingProgress.remove(itemKey)
                pendingTokens.remove(itemKey)
                writer.execute(operation)
            } else {
                val queued = pendingProgress.containsKey(itemKey)
                pendingProgress[itemKey] = operation
                if (!queued) {
                    val token = Any()
                    pendingTokens[itemKey] = token
                    writer.execute {
                        val next = synchronized(pendingLock) {
                            if (pendingTokens[itemKey] !== token) null else {
                                pendingTokens.remove(itemKey)
                                pendingProgress.remove(itemKey)
                            }
                        }
                        next?.invoke()
                    }
                }
            }
        }
    }

    fun awaitPendingWrites() { writer.submit {}.get() }

    constructor(
        preferences: SharedPreferences,
        onPersisted: () -> Unit = {},
    ) : this(
        readSnapshot = { preferences.getString(PLAYBACK_MEMORY_STORAGE_KEY, null) },
        writeSnapshot = { value, synchronous ->
            val editor = preferences.edit().putString(PLAYBACK_MEMORY_STORAGE_KEY, value)
            if (synchronous) editor.commit()
            else {
                editor.apply()
                true
            }
        },
        backgroundPreferences = true,
        onPersisted = onPersisted,
    )

    fun loadResumePositionMs(itemKey: String): Long = readOrdered { loadResumePositionNow(itemKey) }
    private fun loadResumePositionNow(itemKey: String): Long {
        val entry = loadPlaybackEntry(itemKey) ?: return 0L
        val positionMs = entry.optLong("positionMs", 0L)
        val durationMs = entry.optLong("durationMs", 0L)
        val progress = entry.optDouble("progress", 0.0)
        val completed = entry.optBoolean("completed", false)
        return PlaybackMemoryPolicy.resume(positionMs, durationMs, progress, completed)
    }

    fun loadPlaybackEntry(itemKey: String): JSONObject? = readOrdered { loadPlaybackEntryNow(itemKey) }
    private fun loadPlaybackEntryNow(itemKey: String): JSONObject? {
        if (itemKey.isBlank()) {
            return null
        }
        val snapshot = loadPlaybackSnapshot()
        val items = snapshot.optJSONObject("items") ?: return null
        return items.optJSONObject(itemKey)?.let { JSONObject(it.toString()) }
    }

    private fun loadPlaybackSnapshot(): JSONObject {
        val raw = readSnapshot()
        cachedSnapshot?.let { if (cachedRaw == raw) return it }
        val snapshot = try {
            if (raw.isNullOrBlank()) JSONObject() else decodeSnapshot(raw)
        } catch (_: Throwable) {
            JSONObject()
        }
        cachedRaw = raw
        cachedSnapshot = snapshot
        publishReadView(snapshot, raw)
        maximumTimestamp = listOf("items", "series").flatMap { name ->
            val group = snapshot.optJSONObject(name) ?: JSONObject()
            group.keys().asSequence().map {
                PlaybackMemoryPolicy.timestamp(group.optJSONObject(it)?.optString("updatedAt") ?: "")
            }.toList()
        }.maxOrNull() ?: 0L
        return snapshot
    }

    private fun persistSnapshot(snapshot: JSONObject, synchronous: Boolean): Boolean {
        // Writers mutate the cached object. Do not retain it if persistence fails.
        cachedSnapshot = null
        val raw = snapshot.toString()
        publishReadView(snapshot, raw)
        val written = writeSnapshot(raw, synchronous)
        if (written) {
            cachedRaw = raw
            cachedSnapshot = snapshot
            onPersisted()
        } else {
            publishedSkips = null
        }
        return written
    }

    fun loadSeriesSubtitlePreference(seriesKey: String): NativeSubtitleSessionPreference? =
        readOrdered { loadSeriesSubtitlePreferenceNow(seriesKey) }
    private fun loadSeriesSubtitlePreferenceNow(seriesKey: String): NativeSubtitleSessionPreference? {
        val normalizedSeriesKey = seriesKey.trim()
        if (normalizedSeriesKey.isEmpty()) {
            return null
        }
        val raw =
            loadPlaybackSnapshot()
                .optJSONObject("subtitlePreferences")
                ?.optJSONObject(normalizedSeriesKey) ?: return null
        val mode =
            when (raw.optString("mode")) {
                "off" -> NativeSubtitleSessionMode.OFF
                "dual" -> NativeSubtitleSessionMode.DUAL
                else -> NativeSubtitleSessionMode.SINGLE
            }
        return NativeSubtitleSessionPreference(
            mode = mode,
            primary = raw.optJSONObject("primary")?.toSubtitleFingerprint(),
            secondary = raw.optJSONObject("secondary")?.toSubtitleFingerprint(),
        )
    }

    fun saveSeriesSubtitlePreference(seriesKey: String, preference: NativeSubtitleSessionPreference?) =
        writePreference { saveSeriesSubtitlePreferenceNow(seriesKey, preference) }
    private fun saveSeriesSubtitlePreferenceNow(
        seriesKey: String,
        preference: NativeSubtitleSessionPreference?,
    ) {
        val normalizedSeriesKey = seriesKey.trim()
        if (normalizedSeriesKey.isEmpty() || preference == null) {
            return
        }
        val snapshot = loadPlaybackSnapshot()
        val subtitlePreferences = snapshot.optJSONObject("subtitlePreferences") ?: JSONObject()
        subtitlePreferences.put(
            normalizedSeriesKey,
            preference.toJson(seriesKey = normalizedSeriesKey, updatedAt = now()),
        )
        snapshot.put("subtitlePreferences", subtitlePreferences)
        persistSnapshot(snapshot, false)
    }

    fun clearSeriesSubtitlePreference(seriesKey: String) = writePreference { clearSeriesSubtitlePreferenceNow(seriesKey) }
    private fun clearSeriesSubtitlePreferenceNow(seriesKey: String) {
        val normalizedSeriesKey = seriesKey.trim()
        if (normalizedSeriesKey.isEmpty()) {
            return
        }
        val snapshot = loadPlaybackSnapshot()
        val subtitlePreferences = snapshot.optJSONObject("subtitlePreferences") ?: return
        subtitlePreferences.remove(normalizedSeriesKey)
        snapshot.put("subtitlePreferences", subtitlePreferences)
        persistSnapshot(snapshot, false)
    }

    fun savePlaybackEntry(
        targetJson: String, itemKey: String, seriesKey: String,
        positionMs: Long, durationMs: Long, synchronous: Boolean,
        completedByAutoSkip: Boolean = false,
    ) = readOrdered { savePlaybackEntryNow(targetJson, itemKey, seriesKey, positionMs,
        durationMs, synchronous, completedByAutoSkip) }

    private fun savePlaybackEntryNow(
        targetJson: String,
        itemKey: String,
        seriesKey: String,
        positionMs: Long,
        durationMs: Long,
        synchronous: Boolean,
        completedByAutoSkip: Boolean = false,
    ) {
        if (itemKey.isBlank()) {
            if (synchronous) {
                log("native.playback.progress.skipped reason=empty-item-key")
            }
            return
        }

        val clampedDuration = durationMs.coerceAtLeast(0L)
        val safePosition =
            if (clampedDuration > 0L) {
                positionMs.coerceIn(0L, clampedDuration)
            } else {
                positionMs.coerceAtLeast(0L)
            }
        val progress =
            if (clampedDuration <= 0L) {
                0.0
            } else {
                (safePosition.toDouble() / clampedDuration.toDouble()).coerceIn(0.0, 1.0)
            }
        val completed =
            completedByAutoSkip ||
                PlaybackMemoryPolicy.completed(
                    positionMs = safePosition,
                    durationMs = clampedDuration,
                    progress = progress,
                )

        val snapshot = loadPlaybackSnapshot()
        val items = snapshot.optJSONObject("items") ?: JSONObject()
        val series = snapshot.optJSONObject("series") ?: JSONObject()
        val skipPreferences = snapshot.optJSONObject("skipPreferences") ?: JSONObject()
        val subtitlePreferences = snapshot.optJSONObject("subtitlePreferences") ?: JSONObject()
        val targetObject =
            try {
                JSONObject(targetJson)
            } catch (_: Throwable) {
                JSONObject()
            }
        val seriesTitle =
            targetObject.optString("seriesTitle").ifBlank {
                if (targetObject.optString("itemType").trim().lowercase() == "series") {
                    targetObject.optString("title")
                } else {
                    ""
                }
            }

        if (targetObject.optString("sourceKind") == "fntv") {
            if (targetObject.optString("fntvSessionLink").isNotBlank()) {
                targetObject.put("preferredPlaybackQualityIndex", 0)
                targetObject.put("streamUrl", "")
                targetObject.put("headers", JSONObject())
            }
            targetObject.put("fntvSessionLink", "")
            targetObject.put("fntvStartPositionMs", 0)
        }

        val timestamp = PlaybackMemoryPolicy.nextTimestamp(now(), listOf(
            PlaybackMemoryPolicy.formatTimestamp(maximumTimestamp)))
        maximumTimestamp = PlaybackMemoryPolicy.timestamp(timestamp)
        val entry =
            JSONObject().apply {
                put("key", itemKey)
                put("target", targetObject)
                put("updatedAt", timestamp)
                put("seriesKey", seriesKey)
                put("seriesTitle", seriesTitle)
                put("positionMs", safePosition)
                put("durationMs", clampedDuration)
                put("progress", progress)
                put("completed", completed)
            }

        items.put(itemKey, entry)
        pruneRecentItems(items)
        if (seriesKey.isNotBlank()) {
            series.put(seriesKey, entry)
        }

        val nextSnapshot =
            JSONObject().apply {
                put("items", items)
                put("series", series)
                put("skipPreferences", skipPreferences)
                put("subtitlePreferences", subtitlePreferences)
            }
        val committed = persistSnapshot(nextSnapshot, synchronous)
        if (synchronous) {
            log(
                "native.playback.progress.saved " +
                    "positionMs=$safePosition durationMs=$clampedDuration " +
                    "committed=$committed"
            )
        }
    }

    private fun pruneRecentItems(items: JSONObject) {
        val keyedEntries = mutableListOf<Pair<String, JSONObject>>()
        val keys = items.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = items.optJSONObject(key) ?: continue
            keyedEntries.add(key to value)
        }
        if (keyedEntries.size <= RECENT_ENTRY_LIMIT) {
            return
        }
        keyedEntries.sortWith(compareByDescending<Pair<String, JSONObject>> {
            PlaybackMemoryPolicy.timestamp(it.second.optString("updatedAt"))
        }.thenByDescending { it.first })
        keyedEntries.drop(RECENT_ENTRY_LIMIT).forEach { (key, _) -> items.remove(key) }
    }

    fun loadSeriesSkipPreference(seriesKey: String): JSONObject? = readOrdered { loadSeriesSkipPreferenceNow(seriesKey) }
    private fun loadSeriesSkipPreferenceNow(seriesKey: String): JSONObject? {
        if (seriesKey.isBlank()) {
            return null
        }
        return loadPlaybackSnapshot().optJSONObject("skipPreferences")?.optJSONObject(seriesKey)
            ?.let { JSONObject(it.toString()) }
    }

    fun saveSeriesSkipPreference(seriesKey: String, seriesTitle: String, enabled: Boolean,
        introDurationMs: Long, outroDurationMs: Long) = writePreference {
        saveSeriesSkipPreferenceNow(seriesKey, seriesTitle, enabled, introDurationMs, outroDurationMs)
    }
    private fun saveSeriesSkipPreferenceNow(
        seriesKey: String,
        seriesTitle: String,
        enabled: Boolean,
        introDurationMs: Long,
        outroDurationMs: Long,
    ) {
        val normalizedSeriesKey = seriesKey.trim()
        if (normalizedSeriesKey.isEmpty()) return
        val snapshot = loadPlaybackSnapshot()
        val skipPreferences = snapshot.optJSONObject("skipPreferences") ?: JSONObject()
        skipPreferences.put(
            normalizedSeriesKey,
            JSONObject().apply {
                put("seriesKey", normalizedSeriesKey)
                put("updatedAt", now())
                put("seriesTitle", seriesTitle)
                put("enabled", enabled)
                put("introDurationMs", introDurationMs.coerceAtLeast(0L))
                put("outroDurationMs", outroDurationMs.coerceAtLeast(0L))
            },
        )
        val nextSnapshot =
            JSONObject().apply {
                put("items", snapshot.optJSONObject("items") ?: JSONObject())
                put("series", snapshot.optJSONObject("series") ?: JSONObject())
                put("skipPreferences", skipPreferences)
                put(
                    "subtitlePreferences",
                    snapshot.optJSONObject("subtitlePreferences") ?: JSONObject(),
                )
            }
        persistSnapshot(nextSnapshot, false)
    }
}
