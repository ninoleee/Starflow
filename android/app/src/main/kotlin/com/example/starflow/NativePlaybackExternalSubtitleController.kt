package com.example.starflow

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.ExecutorService
import androidx.media3.common.MediaItem
import org.json.JSONObject

internal class NativePlaybackExternalSubtitleController(
    private val host: Host,
    private val handler: Handler = Handler(Looper.getMainLooper()),
    private val worker: ExecutorService = Executors.newSingleThreadExecutor(),
) {
    private var generation = 0
    private var closed = false
    private var applyPending: Runnable? = null
    private var mountedUri: Uri? = null

    fun close() {
        if (closed) return
        closed = true
        generation++
        applyPending?.let(handler::removeCallbacks)
        worker.execute { host.subtitleFiles.close() }
        worker.shutdown()
    }
    interface Host {
        val controllerView: NativePlaybackControllerView
        val target: NativePlaybackTarget
        val session: NativePlaybackSession
        val subtitleFiles: NativePlaybackSubtitleFiles
        val subtitles: NativePlaybackTrackController
        val subtitleStyle: NativePlaybackSubtitleStyleController
        val settings: NativePlaybackSettingsController
        val activity: Activity

        fun showToast(message: String)
    }

    var subtitleDelayMs: Long = 0L

    var externalSubtitleSource: ExternalSubtitleSource? = null
        set(value) {
            generation++
            applyPending?.let(handler::removeCallbacks)
            applyPending = null
            field = value
        }

    var subtitleSearchActive = false

    var resumePlaybackAfterSubtitleSearch = false

    fun openExternalSubtitlePicker() {
        try {
            val intent =
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
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
            host.activity.startActivityForResult(intent, REQUEST_CODE_EXTERNAL_SUBTITLE)
        } catch (_: Throwable) {
            host.showToast("无法打开字幕文件选择器")
        }
    }

    fun openSubtitleDelayPicker() {
        if (externalSubtitleSource == null) {
            host.showToast("当前仅支持外挂字幕偏移")
            return
        }
        val dialog = NativePlaybackNumberPicker.createStepped(
            activity = host.activity,
            title = "字幕偏移",
            current = subtitleDelayMs.toDouble(),
            min = -30_000.0,
            max = 30_000.0,
            step = 100.0,
            format = { value ->
                NativePlaybackFormatting.formatSubtitleDelayLabel(value.toLong())
            },
        ) { value ->
            subtitleDelayMs = value.toLong()
            generation++
            applyPending?.let(handler::removeCallbacks)
            val apply = Runnable {
                applyPending = null
                applyExternalSubtitleConfiguration()
            }
            applyPending = apply
            handler.postDelayed(apply, 250L)
        }
        host.settings.showTransientDialog(dialog, ControllerFocusTarget.SETTINGS)
    }

    fun openOnlineSubtitleSearch() {
        val query = host.target.buildSubtitleSearchQuery()
        if (query.isBlank()) {
            host.showToast("缺少片名信息，暂时无法搜索字幕")
            return
        }

        val currentPlayer = host.session.player
        resumePlaybackAfterSubtitleSearch = currentPlayer?.playWhenReady == true
        host.session.nextInitializePlayWhenReady = currentPlayer?.playWhenReady
        subtitleSearchActive = true
        currentPlayer?.playWhenReady = false
        host.controllerView.hideVideoSurfaceForOverlay()

        try {
            host.activity.startActivityForResult(
                FlutterActivity.NewEngineIntentBuilder(SubtitleSearchActivity::class.java)
                    .initialRoute(host.target.buildSubtitleSearchRoute(query))
                    .backgroundMode(FlutterActivityLaunchConfigs.BackgroundMode.opaque)
                    .build(host.activity),
                REQUEST_CODE_SUBTITLE_SEARCH,
            )
        } catch (_: Throwable) {
            subtitleSearchActive = false
            host.controllerView.restoreVideoSurfaceIfNeeded()
            if (resumePlaybackAfterSubtitleSearch) {
                host.session.setPlayWhenReady(true)
                resumePlaybackAfterSubtitleSearch = false
            }
            host.session.nextInitializePlayWhenReady = null
            host.showToast("打开字幕搜索失败")
        }
    }

    fun handleSubtitleSearchResult(resultCode: Int, data: Intent?) {
        subtitleSearchActive = false
        host.controllerView.restoreVideoSurfaceIfNeeded()
        val shouldResumePlayback = resumePlaybackAfterSubtitleSearch
        resumePlaybackAfterSubtitleSearch = false
        if (resultCode != Activity.RESULT_OK || data == null) {
            if (shouldResumePlayback) {
                host.session.setPlayWhenReady(true)
            }
            return
        }

        val subtitleFilePath =
            data.getStringExtra(SubtitleSearchActivity.RESULT_SUBTITLE_FILE_PATH)?.trim().orEmpty()
        val displayName =
            data.getStringExtra(SubtitleSearchActivity.RESULT_DISPLAY_NAME)?.trim().orEmpty()
        if (subtitleFilePath.isNotEmpty()) {
            loadCachedSubtitleFile(subtitleFilePath, displayName)
            if (shouldResumePlayback) {
                host.session.setPlayWhenReady(true)
            }
            return
        }

        val cachedPath =
            data.getStringExtra(SubtitleSearchActivity.RESULT_CACHED_PATH)?.trim().orEmpty()
        if (cachedPath.isNotEmpty()) {
            host.showToast("字幕已下载到缓存，但当前结果暂不能直接挂载")
        }
        if (shouldResumePlayback) {
            host.session.setPlayWhenReady(true)
        }
    }

    fun loadExternalSubtitle(uri: Uri, intentFlags: Int) {
        val mimeType = host.subtitleFiles.resolveSubtitleMimeType(uri)
        if (mimeType == null) {
            host.showToast("暂不支持该字幕格式")
            return
        }

        val takeFlags =
            intentFlags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        if (takeFlags != 0) {
            try {
                host.activity.contentResolver.takePersistableUriPermission(uri, takeFlags)
            } catch (_: SecurityException) {} catch (_: Throwable) {}
        }

        val previous = externalSubtitleSource
        externalSubtitleSource =
            ExternalSubtitleSource(
                originalUri = uri,
                mimeType = mimeType,
                displayName = host.subtitleFiles.resolveDisplayName(uri),
            )
        applyExternalSubtitleConfiguration(onFailure = { externalSubtitleSource = previous })
    }

    fun restoreExternalSubtitleSourceFromTarget() {
        val targetObject =
            try {
                JSONObject(host.target.playbackTargetJson)
            } catch (_: Throwable) {
                JSONObject()
            }
        val subtitleFilePath = targetObject.optString("externalSubtitleFilePath").trim()
        if (subtitleFilePath.isEmpty()) {
            return
        }
        val displayName = targetObject.optString("externalSubtitleDisplayName").trim()
        prepareCachedSubtitleFile(subtitleFilePath, displayName)
    }

    fun loadCachedSubtitleFile(filePath: String, displayName: String,
        onApplied: (() -> Unit)? = null): Boolean {
        val previous = externalSubtitleSource
        if (!prepareCachedSubtitleFile(filePath, displayName)) {
            host.showToast("缓存字幕文件不存在")
            return false
        }
        val applied = applyExternalSubtitleConfiguration(onApplied = onApplied,
            onFailure = { externalSubtitleSource = previous })
        if (!applied) externalSubtitleSource = previous
        return applied
    }

    private fun prepareCachedSubtitleFile(filePath: String, displayName: String): Boolean {
        val file = File(filePath)
        if (!file.exists() || !file.isFile) {
            return false
        }

        val uri = Uri.fromFile(file)
        val mimeType = host.subtitleFiles.resolveSubtitleMimeType(uri)
        if (mimeType == null) {
            return false
        }

        externalSubtitleSource =
            ExternalSubtitleSource(
                originalUri = uri,
                mimeType = mimeType,
                displayName = displayName.ifBlank { file.name },
            )
        return true
    }

    // The return value means queued; only onApplied signals successful mounting.
    fun applyExternalSubtitleConfiguration(showFeedback: Boolean = true,
        onApplied: (() -> Unit)? = null, onFailure: (() -> Unit)? = null): Boolean {
        if (closed) return false
        val currentPlayer = host.session.player ?: return false
        val source = externalSubtitleSource ?: return false
        val sourceMediaItem = host.session.baseMediaItem ?: currentPlayer.currentMediaItem ?: return false
        val token = ++generation
        val targetJson = host.target.playbackTargetJson
        val delay = subtitleDelayMs
        worker.execute {
            val result = runCatching { host.subtitleFiles.buildSubtitleConfiguration(source, delay) }
            handler.post {
                if (closed || token != generation || host.session.player !== currentPlayer ||
                    host.target.playbackTargetJson != targetJson || host.activity.isFinishing ||
                    host.activity.isDestroyed) {
                    result.getOrNull()?.let { configuration ->
                        if (!worker.isShutdown) worker.execute { host.subtitleFiles.deletePrepared(configuration.uri) }
                    }
                    return@post
                }
                val configuration = result.getOrElse {
                    onFailure?.invoke()
                    host.showToast("字幕处理失败，已保留当前播放")
                    return@post
                }
                mountConfiguration(configuration, sourceMediaItem, showFeedback)
                val previousUri = mountedUri
                mountedUri = configuration.uri
                worker.execute { host.subtitleFiles.deletePrepared(previousUri) }
                onApplied?.invoke()
            }
        }
        return true
    }

    private fun mountConfiguration(configuration: MediaItem.SubtitleConfiguration,
        sourceMediaItem: MediaItem, showFeedback: Boolean) {
        val currentPlayer = host.session.player ?: return
        val currentPosition = currentPlayer.currentPosition
        val shouldResumePlayback = currentPlayer.playWhenReady
        val updatedMediaItem =
            sourceMediaItem.buildUpon().setSubtitleConfigurations(listOf(configuration)).build()
        host.subtitles.subtitleSessionPreference = null
        host.subtitles.dualSubtitleController.disable()
        host.subtitleStyle.applySubtitleStyle()
        host.subtitles.pendingExternalSubtitleSelection = true
        currentPlayer.setMediaItem(updatedMediaItem, currentPosition)
        currentPlayer.prepare()
        if (shouldResumePlayback) {
            host.session.setPlayWhenReady(true)
        } else {
            currentPlayer.playWhenReady = false
        }
        if (showFeedback) {
            host.showToast(
                if (subtitleDelayMs == 0L) {
                    "外挂字幕已加载"
                } else {
                    "外挂字幕已加载，偏移 ${NativePlaybackFormatting.formatSubtitleDelayLabel(subtitleDelayMs)}"
                }
            )
        }
        host.controllerView.showControllerForRemoteFocus(ControllerFocusTarget.SETTINGS)
    }
}
