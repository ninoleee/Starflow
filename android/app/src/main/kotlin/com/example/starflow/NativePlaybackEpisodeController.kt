package com.example.starflow

import android.app.Activity
import android.app.AlertDialog
import android.os.SystemClock
import androidx.media3.ui.PlayerView
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_EPISODE_QUEUE_JSON
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_HEADERS_JSON
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_MEDIA_MIME_TYPE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_PLAYBACK_ITEM_KEY
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_PLAYBACK_TARGET_JSON
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_SERIES_KEY
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_TITLE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_URL

internal class NativePlaybackEpisodeController(private val host: Host) {
    interface Host {
        val controllerView: NativePlaybackControllerView
        val target: NativePlaybackTarget
        val runtime: NativePlaybackRuntimeController
        val diagnostics: NativePlaybackDiagnostics
        val session: NativePlaybackSession
        val recovery: NativePlaybackRecoveryController
        val externalSubtitles: NativePlaybackExternalSubtitleController
        val subtitles: NativePlaybackTrackController
        val systemSession: NativePlaybackSystemController

        fun showToast(message: String)

        val activity: Activity
        val playerView: PlayerView
    }

    var episodeQueue: NativeEpisodeQueue? = null

    private var episodeResolutionInProgress = false

    private var episodeResolutionRequestId = 0L

    fun advanceToAdjacentEpisode(forward: Boolean, reason: String): Boolean {
        val queue = episodeQueue ?: return false
        val nextIndex = if (forward) queue.currentIndex + 1 else queue.currentIndex - 1
        return switchToEpisodeQueueIndex(index = nextIndex, reason = reason)
    }

    private fun switchToEpisodeQueueIndex(index: Int, reason: String): Boolean {
        val queue = episodeQueue ?: return false
        if (index !in queue.entries.indices || index == queue.currentIndex) {
            return false
        }
        val nextQueue = queue.copy(currentIndex = index)
        val nextEntry = nextQueue.currentEntry() ?: return false
        if (episodeResolutionInProgress) {
            host.showToast("正在解析剧集，请稍候")
            host.controllerView.restoreControllerFocusIfNeeded(ControllerFocusTarget.SETTINGS)
            return true
        }
        if (nextEntry.needsResolution()) {
            return resolveAndSwitchEpisodeQueueIndex(queue = queue, index = index, reason = reason)
        }
        return switchToResolvedEpisodeQueueIndex(
            nextQueue = nextQueue,
            nextEntry = nextEntry,
            reason = reason,
            mediaMimeType = nextEntry.mediaMimeType,
        )
    }

    private fun resolveAndSwitchEpisodeQueueIndex(
        queue: NativeEpisodeQueue,
        index: Int,
        reason: String,
    ): Boolean {
        val targetEntry = queue.entries.getOrNull(index) ?: return false
        if (host.target.resolverSessionId.isBlank()) {
            handleEpisodeResolutionFailure(
                message = "当前播放器无法解析该剧集，请重新打开播放页。",
                reason = reason,
                index = index,
            )
            return true
        }

        episodeResolutionInProgress = true
        val request =
            NativeEpisodeResolutionRequest(
                requestId = ++episodeResolutionRequestId,
                sourceQueueIndex = queue.currentIndex,
                sourcePlaybackTargetJson = host.target.playbackTargetJson,
                requestedIndex = index,
                requestedTargetJson = targetEntry.playbackTargetJson,
            )
        val startedAtMs = SystemClock.elapsedRealtime()
        host.showToast(
            "正在解析 ${NativePlaybackFormatting.formatEpisodeSelectionLabel(index, targetEntry)}"
        )
        host.controllerView.restoreControllerFocusIfNeeded(ControllerFocusTarget.SETTINGS)
        NativePlaybackFormatting.logPlayback(
            "native.queue.resolve.begin " +
                "reason=$reason index=$index currentIndex=${request.sourceQueueIndex}"
        )

        val dispatched =
            MainActivity.resolveNativePlaybackEpisode(
                resolverSessionId = host.target.resolverSessionId,
                playbackTargetJson = request.requestedTargetJson,
            ) { result ->
                host.activity.runOnUiThread {
                    if (request.requestId != episodeResolutionRequestId) {
                        return@runOnUiThread
                    }
                    episodeResolutionInProgress = false
                    if (host.activity.isFinishing || host.activity.isDestroyed) {
                        return@runOnUiThread
                    }
                    val currentQueue = episodeQueue
                    if (
                        currentQueue == null ||
                            !request.matchesPlayback(currentQueue, host.target.playbackTargetJson)
                    ) {
                        NativePlaybackFormatting.logPlayback(
                            "native.queue.resolve.ignored " + "reason=playback-changed index=$index"
                        )
                        host.controllerView.restoreControllerFocusIfNeeded(
                            ControllerFocusTarget.SETTINGS
                        )
                        return@runOnUiThread
                    }

                    val resolvedEntry =
                        NativeEpisodeQueueEntry(
                            playbackTargetJson =
                                result["playbackTargetJson"]?.toString()?.trim().orEmpty(),
                            playbackItemKey =
                                result["playbackItemKey"]?.toString()?.trim().orEmpty().ifEmpty {
                                    targetEntry.playbackItemKey
                                },
                            seriesKey =
                                result["seriesKey"]?.toString()?.trim().orEmpty().ifEmpty {
                                    targetEntry.seriesKey
                                },
                            mediaMimeType = result["mediaMimeType"]?.toString()?.trim().orEmpty(),
                        )
                    if (
                        result["ok"] != true ||
                            resolvedEntry.url().isBlank() ||
                            resolvedEntry.needsResolution()
                    ) {
                        val message =
                            result["message"]?.toString()?.trim().orEmpty().ifEmpty { "没有取得可播放地址。" }
                        handleEpisodeResolutionFailure(
                            message = message,
                            reason = reason,
                            index = index,
                            durationMs = SystemClock.elapsedRealtime() - startedAtMs,
                        )
                        return@runOnUiThread
                    }

                    val resolvedQueue =
                        currentQueue.replaceEntry(index, resolvedEntry).copy(currentIndex = index)
                    NativePlaybackFormatting.logPlayback(
                        "native.queue.resolve.success " +
                            "reason=$reason index=$index " +
                            "durationMs=${SystemClock.elapsedRealtime() - startedAtMs}"
                    )
                    switchToResolvedEpisodeQueueIndex(
                        nextQueue = resolvedQueue,
                        nextEntry = resolvedEntry,
                        reason = reason,
                        mediaMimeType = resolvedEntry.mediaMimeType,
                    )
                }
            }
        if (!dispatched) {
            episodeResolutionInProgress = false
            handleEpisodeResolutionFailure(
                message = "播放器解析服务未就绪，请重新打开播放页。",
                reason = reason,
                index = index,
            )
        }
        return true
    }

    private fun handleEpisodeResolutionFailure(
        message: String,
        reason: String,
        index: Int,
        durationMs: Long = 0L,
    ) {
        val displayMessage = message.trim().ifEmpty { "解析剧集失败，请重试。" }
        NativePlaybackFormatting.logPlayback(
            "native.queue.resolve.failed " +
                "reason=$reason index=$index durationMs=$durationMs " +
                "message=$displayMessage"
        )
        host.showToast(displayMessage)
        host.controllerView.restoreControllerFocusIfNeeded(ControllerFocusTarget.SETTINGS)
    }

    private fun switchToResolvedEpisodeQueueIndex(
        nextQueue: NativeEpisodeQueue,
        nextEntry: NativeEpisodeQueueEntry,
        reason: String,
        mediaMimeType: String,
    ): Boolean {
        if (nextEntry.url().isBlank()) {
            return false
        }

        host.runtime.persistPlaybackProgress(force = true)
        host.diagnostics.finishPlaybackPerformanceSession("episode-switch")
        host.session.releasePlayer()
        NativePlaybackFormatting.logPlayback(
            "native.queue.old-player-released " +
                "reason=$reason playerCleared=${host.session.player == null} " +
                "bandwidthCleared=${host.session.playbackBandwidthMeter == null}"
        )

        episodeQueue = nextQueue
        episodeResolutionInProgress = false
        host.recovery.resetForNewMedia()
        host.target.playbackTargetJson = nextEntry.playbackTargetJson
        host.session.internalEpisodeSwitchPlayback = true
        host.diagnostics.beginPlaybackPerformanceSession()
        host.target.playbackItemKey = nextEntry.playbackItemKey
        host.target.seriesKey = nextEntry.seriesKey
        host.externalSubtitles.externalSubtitleSource = null
        host.subtitles.dualSubtitleController.disable()
        host.externalSubtitles.subtitleDelayMs = 0L
        host.session.restoredResumePositionMs = 0L
        host.runtime.lastSavedPositionMs = -1L
        host.session.pendingResumePositionOverrideMs = null
        host.session.nextInitializePlayWhenReady = true
        host.runtime.introSkipApplied = false
        host.runtime.outroSkipApplied = false

        host.activity.intent.putExtra(EXTRA_URL, nextEntry.url())
        host.activity.intent.putExtra(EXTRA_TITLE, nextEntry.title())
        host.activity.intent.putExtra(EXTRA_HEADERS_JSON, nextEntry.headersJson())
        host.activity.intent.putExtra(EXTRA_PLAYBACK_TARGET_JSON, host.target.playbackTargetJson)
        host.activity.intent.putExtra(EXTRA_PLAYBACK_ITEM_KEY, host.target.playbackItemKey)
        host.activity.intent.putExtra(EXTRA_SERIES_KEY, host.target.seriesKey)
        host.activity.intent.putExtra(EXTRA_EPISODE_QUEUE_JSON, nextQueue.toJsonString())
        if (mediaMimeType.isBlank()) {
            host.activity.intent.removeExtra(EXTRA_MEDIA_MIME_TYPE)
        } else {
            host.activity.intent.putExtra(EXTRA_MEDIA_MIME_TYPE, mediaMimeType.trim())
        }

        host.controllerView.bindControllerChrome()
        host.controllerView.updateProgressMarkers()
        host.session.initializePlayer()
        host.systemSession.syncPlaybackSystemSession()
        NativePlaybackFormatting.logPlayback(
            "native.queue.switch " + "reason=$reason index=${nextQueue.currentIndex}"
        )
        return true
    }

    fun openEpisodeSelectionDialog(): Boolean {
        if (host.externalSubtitles.subtitleSearchActive) {
            return false
        }
        val queue = episodeQueue ?: return false
        if (queue.entries.size <= 1) {
            return false
        }
        if (episodeSelectionDialog?.isShowing == true) {
            return true
        }

        val labels =
            queue.entries
                .mapIndexed { index, entry ->
                    NativePlaybackFormatting.formatEpisodeSelectionLabel(index, entry)
                }
                .toTypedArray()
        var switchedEpisode = false
        episodeSelectionDialog =
            AlertDialog.Builder(host.activity)
                .setTitle("选择剧集")
                .setSingleChoiceItems(labels, queue.currentIndex) { dialog, which ->
                    if (which == queue.currentIndex) {
                        dialog.dismiss()
                        return@setSingleChoiceItems
                    }
                    switchedEpisode = true
                    dialog.dismiss()
                    host.playerView.post {
                        switchToEpisodeQueueIndex(index = which, reason = "episode-picker")
                    }
                }
                .setNegativeButton("关闭", null)
                .create()
                .apply {
                    setOnDismissListener {
                        if (episodeSelectionDialog === this) {
                            episodeSelectionDialog = null
                        }
                        if (!switchedEpisode) {
                            host.controllerView.restoreControllerFocusIfNeeded(
                                ControllerFocusTarget.SETTINGS
                            )
                        }
                    }
                    show()
                }
        return true
    }

    private var episodeSelectionDialog: AlertDialog? = null

    val isDialogVisible: Boolean
        get() = episodeSelectionDialog?.isShowing == true

    fun invalidateResolution() {
        episodeResolutionRequestId += 1L
        episodeResolutionInProgress = false
    }

    fun dismissDialog() {
        episodeSelectionDialog?.setOnDismissListener(null)
        episodeSelectionDialog?.dismiss()
        episodeSelectionDialog = null
    }
}
