package com.example.starflow

import android.app.Activity
import android.app.AlertDialog
import android.os.SystemClock
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.ui.PlayerView
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_EPISODE_QUEUE_JSON
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_HEADERS_JSON
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_MEDIA_MIME_TYPE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_PLAYBACK_ITEM_KEY
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_PLAYBACK_TARGET_JSON
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_SERIES_KEY
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_TITLE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_URL

internal class NativePlaybackEpisodeController(
    private val host: Host,
    private val now: () -> Long = SystemClock::elapsedRealtime,
    private val resolveEpisode: (String, String, (Map<String, Any?>) -> Unit) -> Boolean =
        MainActivity::resolveNativePlaybackEpisode,
) {
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
        val launch: NativePlaybackLaunchController
        val memory: NativePlaybackMemoryStore

        fun showToast(message: String)

        val activity: Activity
        val playerView: PlayerView
    }

    var episodeQueue: NativeEpisodeQueue? = null
    private val transition = NativeEpisodeTransition(now)
    private var preparedRetryEntry: NativeEpisodeQueueEntry? = null
    private var retryPositionMs = 0L
    private var transitionStartedAtMs = 0L
    private var episodeSelectionDialog: AlertDialog? = null
    val isDialogVisible: Boolean
        get() = episodeSelectionDialog?.isShowing == true

    val isSwitching: Boolean
        get() = transition.isSwitching

    private fun preparationKey(index: Int): NativeEpisodePreparationKey? {
        val queue = episodeQueue ?: return null
        if (index !in queue.entries.indices) return null
        return NativeEpisodePreparationKey(
            queue,
            index,
            host.target.playbackTargetJson,
            host.target.resolverSessionId,
            host.activity.intent.getStringExtra(EXTRA_URL).orEmpty(),
            host.activity.intent.getStringExtra(EXTRA_HEADERS_JSON).orEmpty(),
            host.activity.intent.getStringExtra(EXTRA_MEDIA_MIME_TYPE).orEmpty(),
        )
    }

    fun advanceToAdjacentEpisode(forward: Boolean, reason: String): Boolean {
        if (transition.isSwitching) return true
        if (
            NativeEpisodeTransition.isAutomatic(reason) &&
                host.session.player?.playWhenReady != true
        )
            return false
        val queue = episodeQueue ?: return false
        return switchToEpisodeQueueIndex(queue.currentIndex + if (forward) 1 else -1, reason)
    }

    private fun switchToEpisodeQueueIndex(index: Int, reason: String): Boolean {
        val key = preparationKey(index) ?: return false
        if (index == key.queue.currentIndex) return false
        val alreadyRequested = transition.reason != null
        val decision = transition.begin(key, reason)
        if (!alreadyRequested && transition.reason != null) transitionStartedAtMs = now()
        when (decision) {
            is NativeEpisodeTransition.Decision.Ready ->
                switchToResolvedEpisode(key, decision.destination)
            is NativeEpisodeTransition.Decision.Resolve -> {
                val entry = key.queue.entries[index]
                if (entry.needsResolution()) resolve(decision.request, entry)
                else
                    transition.resolve(decision.request, entry)?.let {
                        switchToResolvedEpisode(key, it)
                    }
            }
            NativeEpisodeTransition.Decision.Wait -> {
                if (!alreadyRequested && transition.reason != null) host.showToast("正在准备下一集")
            }
        }
        return true
    }

    // Runs on the existing runtime loop, including while paused or at natural end.
    fun tick() {
        transition.expiredRequest()?.let { failResolution(it, "解析剧集超时，请手动重试。") }
        val request = transition.pending
        if (request != null && preparationKey(request.key.index) != request.key) transition.reset()
        val player = host.session.player ?: return
        if (!player.playWhenReady || host.externalSubtitles.subtitleSearchActive) {
            transition.cancelAutomaticAdvance()
            return
        }
        if (player.playbackState != Player.STATE_READY || transition.isSwitching) return
        val queue = episodeQueue ?: return
        if (!queue.hasNext()) return
        val durationMs = player.duration.takeIf { it > 0L } ?: return
        val preference = host.memory.loadSeriesSkipPreference(host.target.seriesKey)
        val boundaryMs =
            NativePlaybackSkipPolicy.endBoundaryMs(
                durationMs,
                preference?.optBoolean("enabled", false) == true,
                preference?.optLong("outroDurationMs", 0L) ?: 0L,
            )
        if (!NativePlaybackSkipPolicy.shouldPrepareNext(player.currentPosition, boundaryMs)) return
        val key = preparationKey(queue.currentIndex + 1) ?: return
        val entry = key.queue.entries[key.index]
        if (!entry.needsResolution() || key.resolverSessionId.isBlank()) return
        transition.prefetch(key)?.let { resolve(it, entry) }
    }

    fun cancelAutomaticAdvance() = transition.cancelAutomaticAdvance()

    fun onUserSeek() {
        if (transition.isSwitching) return
        val player = host.session.player ?: return
        val preference = host.memory.loadSeriesSkipPreference(host.target.seriesKey)
        val boundaryMs =
            NativePlaybackSkipPolicy.endBoundaryMs(
                player.duration,
                preference?.optBoolean("enabled", false) == true,
                preference?.optLong("outroDurationMs", 0L) ?: 0L,
            )
        if (boundaryMs <= 0L || player.currentPosition < boundaryMs)
            transition.cancelAutomaticAdvance()
    }

    private fun resolve(request: NativeEpisodeTransition.Request, entry: NativeEpisodeQueueEntry) {
        if (request.key.resolverSessionId.isBlank()) {
            failResolution(request, "当前播放器无法解析该剧集，请重新打开播放页。")
            return
        }
        if (!request.background) {
            host.showToast(
                "正在解析 ${NativePlaybackFormatting.formatEpisodeSelectionLabel(request.key.index, entry)}"
            )
            host.controllerView.restoreControllerFocusIfNeeded(ControllerFocusTarget.SETTINGS)
        }
        NativePlaybackFormatting.logPlayback(
            "native.queue.resolve.begin index=${request.key.index} background=${request.background}"
        )
        val dispatched =
            resolveEpisode(request.key.resolverSessionId, entry.playbackTargetJson) { result ->
                host.activity.runOnUiThread {
                    if (transition.pending != request) return@runOnUiThread
                    if (
                        now() - request.startedAtMs >= NativeEpisodeTransition.RESOLUTION_TIMEOUT_MS
                    ) {
                        failResolution(request, "解析剧集超时，请手动重试。")
                        return@runOnUiThread
                    }
                    if (
                        host.activity.isFinishing ||
                            host.activity.isDestroyed ||
                            preparationKey(request.key.index) != request.key
                    ) {
                        transition.reset()
                        return@runOnUiThread
                    }
                    if (
                        transition.reason?.let(NativeEpisodeTransition::isAutomatic) == true &&
                            (host.session.player?.playWhenReady != true ||
                                host.externalSubtitles.subtitleSearchActive)
                    ) {
                        transition.cancelAutomaticAdvance()
                    }
                    val resolvedEntry =
                        NativeEpisodeQueueEntry(
                            playbackTargetJson =
                                result["playbackTargetJson"]?.toString()?.trim().orEmpty(),
                            playbackItemKey =
                                result["playbackItemKey"]?.toString()?.trim().orEmpty().ifEmpty {
                                    entry.playbackItemKey
                                },
                            seriesKey =
                                result["seriesKey"]?.toString()?.trim().orEmpty().ifEmpty {
                                    entry.seriesKey
                                },
                            mediaMimeType = result["mediaMimeType"]?.toString()?.trim().orEmpty(),
                        )
                    if (
                        result["ok"] != true ||
                            resolvedEntry.url().isBlank() ||
                            resolvedEntry.needsResolution()
                    ) {
                        failResolution(
                            request,
                            result["message"]?.toString()?.trim().orEmpty().ifEmpty { "没有取得可播放地址。" },
                        )
                        return@runOnUiThread
                    }
                    NativePlaybackFormatting.logPlayback(
                        "native.queue.resolve.success index=${request.key.index} background=${request.background} durationMs=${now() - request.startedAtMs}"
                    )
                    transition.resolve(request, resolvedEntry)?.let {
                        switchToResolvedEpisode(request.key, it)
                    }
                }
            }
        if (!dispatched) failResolution(request, "播放器解析服务未就绪，请重新打开播放页。")
    }

    private fun failResolution(request: NativeEpisodeTransition.Request, message: String) {
        if (transition.pending != request) return
        val reason = transition.fail(request)
        NativePlaybackFormatting.logPlayback(
            "native.queue.resolve.failed index=${request.key.index} background=${reason == null}"
        )
        if (reason == "prepared-address-retry") host.launch.handlePlaybackFailure(message)
        else if (reason != null && !host.activity.isFinishing && !host.activity.isDestroyed) {
            host.showToast(message)
            host.controllerView.restoreControllerFocusIfNeeded(ControllerFocusTarget.SETTINGS)
        }
    }

    private fun switchToResolvedEpisode(
        key: NativeEpisodePreparationKey,
        destination: NativeEpisodeTransition.Destination,
    ) {
        if (
            preparationKey(key.index) != key ||
                host.activity.isFinishing ||
                host.activity.isDestroyed
        ) {
            transition.reset()
            return
        }
        val reason = destination.reason
        val nextEntry = destination.entry
        val isAddressRetry = reason == "prepared-address-retry"
        if (reason == "outro") host.runtime.markAutoSkipCompleted()
        else host.runtime.persistPlaybackProgress(force = true)
        host.diagnostics.finishPlaybackPerformanceSession("episode-switch")
        host.session.releasePlayer()
        NativePlaybackFormatting.logPlayback(
            "native.queue.old-player-released reason=$reason playerCleared=${host.session.player == null} bandwidthCleared=${host.session.playbackBandwidthMeter == null}"
        )

        val nextQueue = key.queue.replaceEntry(key.index, nextEntry).copy(currentIndex = key.index)
        episodeQueue = nextQueue
        preparedRetryEntry = if (destination.prepared) key.queue.entries[key.index] else null
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
        host.session.pendingResumePositionOverrideMs = if (isAddressRetry) retryPositionMs else null
        host.session.nextEpisodeIsAutomatic = NativeEpisodeTransition.isAutomatic(reason)
        host.session.nextInitializePlayWhenReady = true
        host.runtime.resetForNewMedia()

        host.activity.intent.putExtra(EXTRA_URL, nextEntry.url())
        host.activity.intent.putExtra(EXTRA_TITLE, nextEntry.title())
        host.activity.intent.putExtra(EXTRA_HEADERS_JSON, nextEntry.headersJson())
        host.activity.intent.putExtra(EXTRA_PLAYBACK_TARGET_JSON, nextEntry.playbackTargetJson)
        host.activity.intent.putExtra(EXTRA_PLAYBACK_ITEM_KEY, nextEntry.playbackItemKey)
        host.activity.intent.putExtra(EXTRA_SERIES_KEY, nextEntry.seriesKey)
        host.activity.intent.putExtra(EXTRA_EPISODE_QUEUE_JSON, nextQueue.toJsonString())
        if (nextEntry.mediaMimeType.isBlank())
            host.activity.intent.removeExtra(EXTRA_MEDIA_MIME_TYPE)
        else host.activity.intent.putExtra(EXTRA_MEDIA_MIME_TYPE, nextEntry.mediaMimeType)
        host.controllerView.bindControllerChrome()
        host.controllerView.updateProgressMarkers()
        transition.awaitFirstFrame()
        host.session.initializePlayer()
        host.systemSession.syncPlaybackSystemSession()
        NativePlaybackFormatting.logPlayback(
            "native.queue.switch reason=$reason index=${nextQueue.currentIndex} prepared=${destination.prepared}"
        )
    }

    fun onPlaybackReady() {
        if (transition.state == NativeEpisodeTransition.State.WAITING_FOR_FIRST_FRAME) {
            NativeAppLogger.info(
                "playback.performance",
                "Episode transition completed engine=exo durationMs=${now() - transitionStartedAtMs}",
            )
            transition.onFirstFrame()
            preparedRetryEntry = null
        }
    }

    fun onPlaybackFailed() {
        transition.onPlaybackFailed()
        preparedRetryEntry = null
    }

    fun retryPreparedAddressIfNeeded(error: PlaybackException): Boolean {
        val original = preparedRetryEntry ?: return false
        val responseCode = NativePlaybackErrorPolicy.httpResponseCode(error)
        if (!NativePlaybackErrorPolicy.isPreparedAddressRefreshable(responseCode)) return false
        preparedRetryEntry = null
        retryPositionMs = host.session.restoredResumePositionMs
        host.session.pendingResumePositionOverrideMs = retryPositionMs
        host.launch.cancelPlaybackLaunchTimeout()
        transition.reset()
        transitionStartedAtMs = now()
        val key = preparationKey(episodeQueue?.currentIndex ?: return false) ?: return false
        val decision =
            transition.begin(key, "prepared-address-retry")
                as NativeEpisodeTransition.Decision.Resolve
        resolve(decision.request, original)
        return true
    }

    fun openEpisodeSelectionDialog(): Boolean {
        if (host.externalSubtitles.subtitleSearchActive) return false
        val queue = episodeQueue ?: return false
        if (queue.entries.size <= 1) return false
        if (episodeSelectionDialog?.isShowing == true) return true
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
                    host.playerView.post { switchToEpisodeQueueIndex(which, "episode-picker") }
                }
                .setNegativeButton("关闭", null)
                .create()
                .apply {
                    setOnDismissListener {
                        if (episodeSelectionDialog === this) episodeSelectionDialog = null
                        if (!switchedEpisode)
                            host.controllerView.restoreControllerFocusIfNeeded(
                                ControllerFocusTarget.SETTINGS
                            )
                    }
                    show()
                }
        return true
    }

    fun invalidateResolution() {
        transition.reset()
        preparedRetryEntry = null
    }

    fun dismissDialog() {
        episodeSelectionDialog?.setOnDismissListener(null)
        episodeSelectionDialog?.dismiss()
        episodeSelectionDialog = null
    }
}
