package com.example.starflow

import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.Toast
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import org.json.JSONObject
import java.io.File
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class NativePlaybackActivity : Activity() {
    private lateinit var sharedPreferences: SharedPreferences
    private var player: ExoPlayer? = null
    private lateinit var playerView: PlayerView
    private var baseMediaItem: MediaItem? = null
    private var playbackTargetJson = "{}"
    private var playbackItemKey = ""
    private var seriesKey = ""
    private var restoredResumePositionMs: Long = 0L
    private var subtitleDelayMs: Long = 0L
    private var externalSubtitleSource: ExternalSubtitleSource? = null
    private var lastSavedPositionMs: Long = -1L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        sharedPreferences = getSharedPreferences(SHARED_PREFERENCES_NAME, MODE_PRIVATE)
        playbackTargetJson = intent.getStringExtra(EXTRA_PLAYBACK_TARGET_JSON)?.trim().orEmpty()
            .ifEmpty { "{}" }
        playbackItemKey = intent.getStringExtra(EXTRA_PLAYBACK_ITEM_KEY)?.trim().orEmpty()
        seriesKey = intent.getStringExtra(EXTRA_SERIES_KEY)?.trim().orEmpty()

        setContentView(R.layout.native_player_view)
        playerView = findViewById<PlayerView>(R.id.native_player_view).apply {
            useController = true
            setShutterBackgroundColor(Color.BLACK)
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            setBackgroundColor(Color.BLACK)
            keepScreenOn = true
            setShowSubtitleButton(true)
            setShowFastForwardButton(true)
            setShowRewindButton(true)
            setShowPreviousButton(false)
            setShowNextButton(false)
            setControllerAutoShow(true)
            setControllerHideOnTouch(true)
            setControllerShowTimeoutMs(4_000)
        }
        findViewById<View>(R.id.native_external_subtitle)?.setOnClickListener {
            openExternalSubtitlePicker()
            playerView.showController()
        }
        findViewById<View>(R.id.native_subtitle_delay)?.setOnClickListener {
            openSubtitleDelayPicker()
            playerView.showController()
        }
        findViewById<View>(R.id.native_online_subtitle_search)?.setOnClickListener {
            openOnlineSubtitleSearch()
            playerView.showController()
        }
        enterImmersiveMode()
    }

    override fun onStart() {
        super.onStart()
        initializePlayer()
    }

    override fun onResume() {
        super.onResume()
        enterImmersiveMode()
        playerView.onResume()
        player?.playWhenReady = true
    }

    override fun onPause() {
        persistPlaybackProgress()
        playerView.onPause()
        super.onPause()
    }

    override fun onStop() {
        persistPlaybackProgress(force = true)
        releasePlayer()
        super.onStop()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            enterImmersiveMode()
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN) {
            return super.dispatchKeyEvent(event)
        }

        when (event.keyCode) {
            KeyEvent.KEYCODE_MENU,
            KeyEvent.KEYCODE_SETTINGS -> {
                openExternalSubtitlePicker()
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CODE_EXTERNAL_SUBTITLE || resultCode != RESULT_OK) {
            return
        }
        val subtitleUri = data?.data ?: return
        loadExternalSubtitle(subtitleUri, data.flags)
    }

    private fun initializePlayer() {
        if (player != null) {
            return
        }

        val url = intent.getStringExtra(EXTRA_URL)?.trim().orEmpty()
        if (url.isEmpty()) {
            finish()
            return
        }
        val title = intent.getStringExtra(EXTRA_TITLE)?.trim().orEmpty()
        val headersJson = intent.getStringExtra(EXTRA_HEADERS_JSON)?.trim().orEmpty()
        val decodeMode = PlaybackDecodeMode.fromRaw(
            intent.getStringExtra(EXTRA_DECODE_MODE)?.trim().orEmpty(),
        )

        restoredResumePositionMs = loadResumePositionMs()

        val dataSourceFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setUserAgent("Starflow")

        if (headersJson.isNotEmpty()) {
            try {
                val json = JSONObject(headersJson)
                val headers = mutableMapOf<String, String>()
                val keys = json.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    headers[key] = json.optString(key)
                }
                dataSourceFactory.setDefaultRequestProperties(headers)
            } catch (_: Throwable) {
            }
        }

        val renderersFactory = DefaultRenderersFactory(this).apply {
            setEnableDecoderFallback(true)
            when (decodeMode) {
                PlaybackDecodeMode.AUTO -> Unit
                PlaybackDecodeMode.HARDWARE_PREFERRED -> {
                    setMediaCodecSelector(buildMediaCodecSelector(preferSoftware = false))
                }

                PlaybackDecodeMode.SOFTWARE_PREFERRED -> {
                    setMediaCodecSelector(buildMediaCodecSelector(preferSoftware = true))
                }
            }
        }

        val exoPlayer = ExoPlayer.Builder(this)
            .setRenderersFactory(renderersFactory)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory))
            .build()
        val initialMediaItem = MediaItem.Builder()
            .setUri(url)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(title.ifEmpty { null })
                    .build(),
            )
            .build()
        baseMediaItem = initialMediaItem

        exoPlayer.apply {
            playWhenReady = true
            repeatMode = Player.REPEAT_MODE_OFF
            setMediaItem(initialMediaItem)
            if (restoredResumePositionMs > 5_000L) {
                seekTo(restoredResumePositionMs)
            }
            prepare()
        }

        player = exoPlayer
        playerView.player = exoPlayer
        playerView.showController()
        if (restoredResumePositionMs > 5_000L) {
            showToast("已从 ${formatClockDuration(restoredResumePositionMs)} 继续播放")
        }
    }

    private fun buildMediaCodecSelector(preferSoftware: Boolean): MediaCodecSelector {
        return MediaCodecSelector { mimeType, requiresSecureDecoder, requiresTunnelingDecoder ->
            val allInfos = MediaCodecUtil.getDecoderInfos(
                mimeType,
                requiresSecureDecoder,
                requiresTunnelingDecoder,
            )
            val preferredInfos = allInfos.filter { info -> info.softwareOnly == preferSoftware }
            if (preferredInfos.isNotEmpty()) {
                preferredInfos
            } else {
                allInfos
            }
        }
    }

    private fun releasePlayer() {
        playerView.player = null
        player?.release()
        player = null
    }

    private fun openExternalSubtitlePicker() {
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf(
                        "application/x-subrip",
                        "text/plain",
                        "text/vtt",
                        "text/x-ssa",
                        "application/ssa",
                        "application/ass",
                    ),
                )
            }
            startActivityForResult(intent, REQUEST_CODE_EXTERNAL_SUBTITLE)
        } catch (_: Throwable) {
            showToast("无法打开字幕文件选择器")
        }
    }

    private fun openSubtitleDelayPicker() {
        if (externalSubtitleSource == null) {
            showToast("当前仅支持外挂字幕偏移")
            return
        }
        val labels = SUBTITLE_DELAY_OPTIONS_MS.map { formatSubtitleDelayLabel(it) }.toTypedArray()
        val currentIndex = SUBTITLE_DELAY_OPTIONS_MS.indexOf(subtitleDelayMs).coerceAtLeast(0)
        AlertDialog.Builder(this)
            .setTitle("字幕偏移")
            .setSingleChoiceItems(labels, currentIndex) { dialog, which ->
                subtitleDelayMs = SUBTITLE_DELAY_OPTIONS_MS[which]
                dialog.dismiss()
                applyExternalSubtitleConfiguration()
            }
            .setNegativeButton("取消", null)
            .show()
    }

    private fun openOnlineSubtitleSearch() {
        val query = buildSubtitleSearchQuery()
        if (query.isBlank()) {
            showToast("缺少片名信息，暂时无法搜索字幕")
            return
        }

        if (isTelevision()) {
            AlertDialog.Builder(this)
                .setTitle("在线查找字幕")
                .setMessage(
                    "电视模式暂不直接拉起外部浏览器，避免系统兼容性问题。\n\n" +
                        "请在其他设备上搜索：\n$query 字幕",
                )
                .setPositiveButton("知道了", null)
                .show()
            return
        }

        val labels = arrayOf("SubHD", "Bing", "百度")
        val uris = listOf(
            Uri.parse("https://subhd.tv/search/${Uri.encode(query)}"),
            Uri.parse("https://www.bing.com/search?q=${Uri.encode("$query 字幕")}"),
            Uri.parse("https://www.baidu.com/s?wd=${Uri.encode("$query 字幕")}"),
        )
        AlertDialog.Builder(this)
            .setTitle("在线查找字幕")
            .setItems(labels) { _, which ->
                launchExternalSubtitleSearch(uris.getOrNull(which))
            }
            .setNegativeButton("取消", null)
            .show()
    }

    private fun launchExternalSubtitleSearch(uri: Uri?) {
        if (uri == null) {
            showToast("打开字幕搜索失败")
            return
        }
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(Intent.createChooser(intent, "在线查找字幕"))
        } catch (_: ActivityNotFoundException) {
            showToast("打开字幕搜索失败")
        } catch (_: Throwable) {
            showToast("打开字幕搜索失败")
        }
    }

    private fun buildSubtitleSearchQuery(): String {
        val targetObject = try {
            JSONObject(playbackTargetJson)
        } catch (_: Throwable) {
            JSONObject()
        }
        val seriesTitle = targetObject.optString("seriesTitle").trim()
        val title = targetObject.optString("title").trim()
        val itemType = targetObject.optString("itemType").trim().lowercase()
        val seasonNumber = targetObject.optInt("seasonNumber", 0)
        val episodeNumber = targetObject.optInt("episodeNumber", 0)
        val year = targetObject.optInt("year", 0)

        val parts = mutableListOf<String>()
        val baseTitle = if (seriesTitle.isNotEmpty()) seriesTitle else title
        if (baseTitle.isNotEmpty()) {
            parts += baseTitle
        }
        if (seasonNumber > 0 && episodeNumber > 0) {
            parts += "S${seasonNumber.toString().padStart(2, '0')}E${episodeNumber.toString().padStart(2, '0')}"
        }
        if (itemType != "episode" && year > 0) {
            parts += year.toString()
        }
        return parts.joinToString(" ").trim()
    }

    private fun isTelevision(): Boolean {
        val currentMode = resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK
        return currentMode == Configuration.UI_MODE_TYPE_TELEVISION
    }

    private fun loadExternalSubtitle(uri: Uri, intentFlags: Int) {
        val mimeType = resolveSubtitleMimeType(uri)
        if (mimeType == null) {
            showToast("暂不支持该字幕格式")
            return
        }

        val takeFlags = intentFlags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        if (takeFlags != 0) {
            try {
                contentResolver.takePersistableUriPermission(uri, takeFlags)
            } catch (_: SecurityException) {
            } catch (_: Throwable) {
            }
        }

        externalSubtitleSource = ExternalSubtitleSource(
            originalUri = uri,
            mimeType = mimeType,
            displayName = resolveDisplayName(uri),
        )
        applyExternalSubtitleConfiguration()
    }

    private fun applyExternalSubtitleConfiguration() {
        val currentPlayer = player ?: return
        val source = externalSubtitleSource ?: return
        val sourceMediaItem = baseMediaItem ?: currentPlayer.currentMediaItem ?: return
        val currentPosition = currentPlayer.currentPosition
        val shouldResumePlayback = currentPlayer.playWhenReady
        val configuration = try {
            buildSubtitleConfiguration(source)
        } catch (_: Throwable) {
            showToast("字幕处理失败，已保留当前播放")
            return
        }

        val updatedMediaItem = sourceMediaItem.buildUpon()
            .setSubtitleConfigurations(listOf(configuration))
            .build()
        currentPlayer.setMediaItem(updatedMediaItem, currentPosition)
        currentPlayer.prepare()
        currentPlayer.playWhenReady = shouldResumePlayback
        showToast(
            if (subtitleDelayMs == 0L) {
                "外挂字幕已加载"
            } else {
                "外挂字幕已加载，偏移 ${formatSubtitleDelayLabel(subtitleDelayMs)}"
            },
        )
        playerView.showController()
    }

    private fun buildSubtitleConfiguration(source: ExternalSubtitleSource): MediaItem.SubtitleConfiguration {
        val effectiveUri = if (subtitleDelayMs == 0L) {
            source.originalUri
        } else {
            buildShiftedSubtitleFile(source, subtitleDelayMs)
        }
        return MediaItem.SubtitleConfiguration.Builder(effectiveUri)
            .setMimeType(source.mimeType)
            .setLanguage(C.LANGUAGE_UNDETERMINED)
            .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
            .setLabel(
                if (subtitleDelayMs == 0L) {
                    source.displayName
                } else {
                    "${source.displayName} (${formatSubtitleDelayLabel(subtitleDelayMs)})"
                },
            )
            .setId("external:${source.originalUri}:$subtitleDelayMs")
            .build()
    }

    private fun buildShiftedSubtitleFile(source: ExternalSubtitleSource, delayMs: Long): Uri {
        val subtitleDirectory = File(cacheDir, "native_subtitles").apply { mkdirs() }
        val extension = resolveSubtitleExtension(source)
        val outputFile = File(
            subtitleDirectory,
            "shifted_${source.displayName.hashCode()}_${delayMs}.$extension",
        )
        val originalContent = contentResolver.openInputStream(source.originalUri)
            ?.bufferedReader(StandardCharsets.UTF_8)
            ?.use { it.readText() }
            ?: throw IllegalStateException("字幕文件读取失败")
        val shiftedContent = shiftSubtitleContent(
            content = originalContent,
            mimeType = source.mimeType,
            delayMs = delayMs,
        )
        outputFile.writeText(shiftedContent, StandardCharsets.UTF_8)
        return Uri.fromFile(outputFile)
    }

    private fun shiftSubtitleContent(content: String, mimeType: String, delayMs: Long): String {
        return when (mimeType) {
            MimeTypes.APPLICATION_SUBRIP -> shiftSubRip(content, delayMs)
            MimeTypes.TEXT_VTT -> shiftWebVtt(content, delayMs)
            MimeTypes.TEXT_SSA -> shiftAssSsa(content, delayMs)
            else -> content
        }
    }

    private fun shiftSubRip(content: String, delayMs: Long): String {
        val regex =
            Regex("(\\d{2}:\\d{2}:\\d{2},\\d{3})\\s-->\\s(\\d{2}:\\d{2}:\\d{2},\\d{3})")
        return regex.replace(content) { match ->
            val startMs = parseSubRipTimestamp(match.groupValues[1])
            val endMs = parseSubRipTimestamp(match.groupValues[2])
            val shiftedStart = shiftTimestamp(startMs, delayMs)
            val shiftedEnd = shiftTimestamp(endMs, delayMs, minimum = shiftedStart)
            "${formatSubRipTimestamp(shiftedStart)} --> ${formatSubRipTimestamp(shiftedEnd)}"
        }
    }

    private fun shiftWebVtt(content: String, delayMs: Long): String {
        val regex =
            Regex(
                "((?:\\d{2}:)?\\d{2}:\\d{2}\\.\\d{3})\\s-->\\s((?:\\d{2}:)?\\d{2}:\\d{2}\\.\\d{3})(.*)",
            )
        return regex.replace(content) { match ->
            val startMs = parseWebVttTimestamp(match.groupValues[1])
            val endMs = parseWebVttTimestamp(match.groupValues[2])
            val shiftedStart = shiftTimestamp(startMs, delayMs)
            val shiftedEnd = shiftTimestamp(endMs, delayMs, minimum = shiftedStart)
            "${formatWebVttTimestamp(shiftedStart)} --> ${formatWebVttTimestamp(shiftedEnd)}${match.groupValues[3]}"
        }
    }

    private fun shiftAssSsa(content: String, delayMs: Long): String {
        val regex = Regex("^(Dialogue:\\s*[^,]*,)([^,]+),([^,]+)(,.*)$", RegexOption.MULTILINE)
        return regex.replace(content) { match ->
            val startMs = parseAssTimestamp(match.groupValues[2])
            val endMs = parseAssTimestamp(match.groupValues[3])
            val shiftedStart = shiftTimestamp(startMs, delayMs)
            val shiftedEnd = shiftTimestamp(endMs, delayMs, minimum = shiftedStart)
            "${match.groupValues[1]}${formatAssTimestamp(shiftedStart)},${formatAssTimestamp(shiftedEnd)}${match.groupValues[4]}"
        }
    }

    private fun shiftTimestamp(originalMs: Long, delayMs: Long, minimum: Long = 0L): Long {
        return (originalMs + delayMs).coerceAtLeast(minimum.coerceAtLeast(0L))
    }

    private fun resolveSubtitleMimeType(uri: Uri): String? {
        val fromResolver = contentResolver.getType(uri)?.let { candidate ->
            when (candidate.lowercase()) {
                "application/x-subrip" -> MimeTypes.APPLICATION_SUBRIP
                "text/vtt" -> MimeTypes.TEXT_VTT
                "text/x-ssa",
                "application/ssa",
                "application/ass",
                "text/x-ass" -> MimeTypes.TEXT_SSA
                else -> null
            }
        }
        if (fromResolver != null) {
            return fromResolver
        }

        val name = resolveDisplayName(uri).lowercase()
        return when {
            name.endsWith(".srt") -> MimeTypes.APPLICATION_SUBRIP
            name.endsWith(".vtt") -> MimeTypes.TEXT_VTT
            name.endsWith(".ass") || name.endsWith(".ssa") -> MimeTypes.TEXT_SSA
            else -> null
        }
    }

    private fun resolveSubtitleExtension(source: ExternalSubtitleSource): String {
        return when (source.mimeType) {
            MimeTypes.APPLICATION_SUBRIP -> "srt"
            MimeTypes.TEXT_VTT -> "vtt"
            MimeTypes.TEXT_SSA -> "ass"
            else -> "srt"
        }
    }

    private fun resolveDisplayName(uri: Uri): String {
        var result = uri.lastPathSegment ?: "外挂字幕"
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0 && cursor.moveToFirst()) {
                        result = cursor.getString(index) ?: result
                    }
                }
        } catch (_: Throwable) {
        }
        return result
    }

    private fun loadResumePositionMs(): Long {
        val entry = loadPlaybackEntry(playbackItemKey) ?: return 0L
        val positionMs = entry.optLong("positionMs", 0L)
        val durationMs = entry.optLong("durationMs", 0L)
        val progress = entry.optDouble("progress", 0.0)
        val completed = entry.optBoolean("completed", false)
        if (completed || positionMs < 5_000L) {
            return 0L
        }
        if (durationMs > 0L && durationMs - positionMs <= 12_000L) {
            return 0L
        }
        if (progress >= 0.985) {
            return 0L
        }
        return positionMs
    }

    private fun persistPlaybackProgress(force: Boolean = false) {
        val currentPlayer = player ?: return
        val resolvedDuration = currentPlayer.duration.takeIf { it > 0L } ?: 0L
        val resolvedPosition = currentPlayer.currentPosition.coerceAtLeast(0L)
        if (!force && kotlin.math.abs(resolvedPosition - lastSavedPositionMs) < 4_000L) {
            return
        }
        lastSavedPositionMs = resolvedPosition
        savePlaybackEntry(
            targetJson = playbackTargetJson,
            itemKey = playbackItemKey,
            seriesKey = seriesKey,
            positionMs = resolvedPosition,
            durationMs = resolvedDuration,
        )
    }

    private fun loadPlaybackEntry(itemKey: String): JSONObject? {
        if (itemKey.isBlank()) {
            return null
        }
        val snapshot = loadPlaybackSnapshot()
        val items = snapshot.optJSONObject("items") ?: return null
        return items.optJSONObject(itemKey)
    }

    private fun loadPlaybackSnapshot(): JSONObject {
        val raw = sharedPreferences.getString(PLAYBACK_MEMORY_STORAGE_KEY, null)
        if (raw.isNullOrBlank()) {
            return JSONObject()
        }
        return try {
            JSONObject(raw)
        } catch (_: Throwable) {
            JSONObject()
        }
    }

    private fun savePlaybackEntry(
        targetJson: String,
        itemKey: String,
        seriesKey: String,
        positionMs: Long,
        durationMs: Long,
    ) {
        if (itemKey.isBlank()) {
            return
        }

        val clampedDuration = durationMs.coerceAtLeast(0L)
        val safePosition = if (clampedDuration > 0L) {
            positionMs.coerceIn(0L, clampedDuration)
        } else {
            positionMs.coerceAtLeast(0L)
        }
        val progress = if (clampedDuration <= 0L) {
            0.0
        } else {
            (safePosition.toDouble() / clampedDuration.toDouble()).coerceIn(0.0, 1.0)
        }
        val completed = isCompleted(
            positionMs = safePosition,
            durationMs = clampedDuration,
            progress = progress,
        )

        val snapshot = loadPlaybackSnapshot()
        val items = snapshot.optJSONObject("items") ?: JSONObject()
        val series = snapshot.optJSONObject("series") ?: JSONObject()
        val skipPreferences = snapshot.optJSONObject("skipPreferences") ?: JSONObject()
        val targetObject = try {
            JSONObject(targetJson)
        } catch (_: Throwable) {
            JSONObject()
        }
        val seriesTitle = targetObject.optString("seriesTitle").ifBlank {
            if (targetObject.optString("itemType").trim().lowercase() == "series") {
                targetObject.optString("title")
            } else {
                ""
            }
        }

        val entry = JSONObject().apply {
            put("key", itemKey)
            put("target", targetObject)
            put("updatedAt", isoNow())
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

        val nextSnapshot = JSONObject().apply {
            put("items", items)
            put("series", series)
            put("skipPreferences", skipPreferences)
        }
        sharedPreferences.edit()
            .putString(PLAYBACK_MEMORY_STORAGE_KEY, nextSnapshot.toString())
            .apply()
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
        keyedEntries.sortByDescending { (_, value) -> value.optString("updatedAt") }
        keyedEntries.drop(RECENT_ENTRY_LIMIT).forEach { (key, _) ->
            items.remove(key)
        }
    }

    private fun isCompleted(positionMs: Long, durationMs: Long, progress: Double): Boolean {
        if (durationMs <= 0L) {
            return progress >= 0.995
        }
        val remaining = durationMs - positionMs
        return progress >= 0.985 || remaining <= 8_000L
    }

    private fun parseSubRipTimestamp(value: String): Long {
        val parts = value.split(":", ",")
        if (parts.size != 4) {
            return 0L
        }
        val hours = parts[0].toLongOrNull() ?: 0L
        val minutes = parts[1].toLongOrNull() ?: 0L
        val seconds = parts[2].toLongOrNull() ?: 0L
        val millis = parts[3].toLongOrNull() ?: 0L
        return (((hours * 60 + minutes) * 60) + seconds) * 1_000L + millis
    }

    private fun formatSubRipTimestamp(valueMs: Long): String {
        val totalSeconds = valueMs / 1_000L
        val millis = valueMs % 1_000L
        val seconds = totalSeconds % 60L
        val minutes = (totalSeconds / 60L) % 60L
        val hours = totalSeconds / 3_600L
        return String.format(Locale.US, "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }

    private fun parseWebVttTimestamp(value: String): Long {
        val parts = value.split(":", ".")
        return when (parts.size) {
            4 -> {
                val hours = parts[0].toLongOrNull() ?: 0L
                val minutes = parts[1].toLongOrNull() ?: 0L
                val seconds = parts[2].toLongOrNull() ?: 0L
                val millis = parts[3].toLongOrNull() ?: 0L
                (((hours * 60 + minutes) * 60) + seconds) * 1_000L + millis
            }

            3 -> {
                val minutes = parts[0].toLongOrNull() ?: 0L
                val seconds = parts[1].toLongOrNull() ?: 0L
                val millis = parts[2].toLongOrNull() ?: 0L
                ((minutes * 60) + seconds) * 1_000L + millis
            }

            else -> 0L
        }
    }

    private fun formatWebVttTimestamp(valueMs: Long): String {
        val totalSeconds = valueMs / 1_000L
        val millis = valueMs % 1_000L
        val seconds = totalSeconds % 60L
        val minutes = (totalSeconds / 60L) % 60L
        val hours = totalSeconds / 3_600L
        return if (hours > 0L) {
            String.format(Locale.US, "%02d:%02d:%02d.%03d", hours, minutes, seconds, millis)
        } else {
            String.format(Locale.US, "%02d:%02d.%03d", minutes, seconds, millis)
        }
    }

    private fun parseAssTimestamp(value: String): Long {
        val parts = value.trim().split(":", ".")
        if (parts.size != 4) {
            return 0L
        }
        val hours = parts[0].toLongOrNull() ?: 0L
        val minutes = parts[1].toLongOrNull() ?: 0L
        val seconds = parts[2].toLongOrNull() ?: 0L
        val centiseconds = parts[3].toLongOrNull() ?: 0L
        return (((hours * 60 + minutes) * 60) + seconds) * 1_000L + centiseconds * 10L
    }

    private fun formatAssTimestamp(valueMs: Long): String {
        val totalSeconds = valueMs / 1_000L
        val centiseconds = (valueMs % 1_000L) / 10L
        val seconds = totalSeconds % 60L
        val minutes = (totalSeconds / 60L) % 60L
        val hours = totalSeconds / 3_600L
        return String.format(Locale.US, "%d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
    }

    private fun isoNow(): String {
        val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        formatter.timeZone = TimeZone.getTimeZone("UTC")
        return formatter.format(Date())
    }

    private fun formatClockDuration(valueMs: Long): String {
        val totalSeconds = valueMs / 1_000L
        val hours = totalSeconds / 3_600L
        val minutes = (totalSeconds % 3_600L) / 60L
        val seconds = totalSeconds % 60L
        return if (hours > 0L) {
            String.format(Locale.US, "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format(Locale.US, "%d:%02d", minutes, seconds)
        }
    }

    private fun formatSubtitleDelayLabel(valueMs: Long): String {
        if (valueMs == 0L) {
            return "0s"
        }
        val seconds = valueMs / 1_000.0
        val formatted = if (seconds == seconds.toLong().toDouble()) {
            seconds.toLong().toString()
        } else {
            String.format(Locale.US, "%.1f", seconds).trimEnd('0').trimEnd('.')
        }
        return if (valueMs > 0L) "+${formatted}s" else "${formatted}s"
    }

    private fun showToast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    }

    private fun enterImmersiveMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.hide(
                android.view.WindowInsets.Type.statusBars() or
                    android.view.WindowInsets.Type.navigationBars(),
            )
            window.insetsController?.systemBarsBehavior =
                android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            return
        }

        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
    }

    companion object {
        private const val REQUEST_CODE_EXTERNAL_SUBTITLE = 1001
        private const val SHARED_PREFERENCES_NAME = "FlutterSharedPreferences"
        private const val PLAYBACK_MEMORY_STORAGE_KEY = "flutter.starflow.playback.memory.v1"
        private const val RECENT_ENTRY_LIMIT = 20
        private val SUBTITLE_DELAY_OPTIONS_MS =
            listOf(-5_000L, -2_000L, -1_000L, -500L, 0L, 500L, 1_000L, 2_000L, 5_000L)

        const val EXTRA_URL = "url"
        const val EXTRA_TITLE = "title"
        const val EXTRA_HEADERS_JSON = "headersJson"
        const val EXTRA_DECODE_MODE = "decodeMode"
        const val EXTRA_PLAYBACK_TARGET_JSON = "playbackTargetJson"
        const val EXTRA_PLAYBACK_ITEM_KEY = "playbackItemKey"
        const val EXTRA_SERIES_KEY = "seriesKey"
    }
}

private data class ExternalSubtitleSource(
    val originalUri: Uri,
    val mimeType: String,
    val displayName: String,
)

private enum class PlaybackDecodeMode {
    AUTO,
    HARDWARE_PREFERRED,
    SOFTWARE_PREFERRED;

    companion object {
        fun fromRaw(raw: String): PlaybackDecodeMode {
            return when (raw) {
                "hardwarePreferred" -> HARDWARE_PREFERRED
                "softwarePreferred" -> SOFTWARE_PREFERRED
                else -> AUTO
            }
        }
    }
}
