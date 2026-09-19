package com.example.starflow

import android.app.Activity
import android.app.AlertDialog
import androidx.media3.common.C
import androidx.media3.ui.PlayerView
import java.util.Locale
import org.json.JSONObject
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_URL
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_HEADERS_JSON
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_MEDIA_MIME_TYPE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_PLAYBACK_TARGET_JSON

internal class NativeFntvController(
    private val host: Host,
    private val invoke: (String, Map<String, Any?>, (Map<String, Any?>) -> Unit) -> Unit =
        MainActivity::invokeNativeFntv,
    private val resolve: (String, String, (Map<String, Any?>) -> Unit) -> Boolean =
        MainActivity::resolveNativePlaybackEpisode,
) {
    interface Host {
        val activity: Activity
        val playerView: PlayerView
        val target: NativePlaybackTarget
        val session: NativePlaybackSession
        val runtime: NativePlaybackRuntimeController
        val episodes: NativePlaybackEpisodeController
        val launch: NativePlaybackLaunchController
        val recovery: NativePlaybackRecoveryController
        val externalSubtitles: NativePlaybackExternalSubtitleController
        val subtitles: NativePlaybackTrackController
        val settings: NativePlaybackSettingsController
        fun showToast(message: String)
    }

    private var busy = false
    private var generation = 0
    private var rollback: (() -> Unit)? = null
    private var restoreTracks: (() -> Unit)? = null
    private var closed = false
    private var loadedSubtitleId = ""
    private var loadedSubtitleUri = ""
    private val progress = NativeFntvProgressQueue { snapshot, done ->
        invoke("reportNativeFntvProgress", snapshot) { result ->
            if (result["ok"] != true) {
                NativeAppLogger.warning("library.fntv", "Native progress writeback failed")
            }
            done()
        }
    }

    val isSwitching: Boolean get() = busy || rollback != null
    private fun target() = host.target.decodePlaybackTargetObject()
    private fun isFntv() = target().optString("sourceKind") == "fntv"
    fun qualities(): List<JSONObject> = rows("playbackQualities")
    fun qualitySettingsLabel(): String? {
        if (!isFntv()) return null
        val qualities = qualities()
        if (qualities.isEmpty()) return "画质 · 未返回可切换画质"
        val selected = qualities.firstOrNull {
            it.optInt("index") == target().optInt("preferredPlaybackQualityIndex", 0)
        } ?: qualities.first()
        val label = selected.optString("resolution").ifBlank { "当前画质" }
        return "画质 · $label" + if (qualities.size == 1) "（仅一档）" else ""
    }
    fun audioSettingsLabel(): String? {
        if (!isFntv()) return null
        val count = rows("audioStreams").size
        return if (count > 0) "音轨 · 飞牛 $count 条" else "音轨 · 飞牛未返回音轨"
    }
    fun subtitleSettingsLabel(): String? {
        if (!isFntv()) return null
        val streams = rows("subtitleStreams")
        val embeddedCount = streams.count { !it.optBoolean("isExternal") }
        val externalCount = streams.size - embeddedCount
        val parts = buildList {
            if (embeddedCount > 0) add("内置 $embeddedCount")
            if (externalCount > 0) add("外挂 $externalCount")
        }
        return "字幕 · " + parts.ifEmpty { listOf("飞牛未返回字幕") }.joinToString(" / ")
    }
    fun externalSubtitles(): List<JSONObject> = rows("subtitleStreams").filter {
        it.optBoolean("isExternal") && it.optString("id").isNotBlank()
    }
    private fun rows(key: String): List<JSONObject> {
        if (!isFntv()) return emptyList()
        val array = target().optJSONArray(key) ?: return emptyList()
        return (0 until array.length()).mapNotNull { array.optJSONObject(it) }
    }
    private fun args(json: String = host.target.playbackTargetJson) = mapOf<String, Any?>(
        "resolverSessionId" to host.target.resolverSessionId,
        "playbackTargetJson" to json,
    )

    fun report(position: Long, duration: Long) {
        if (closed || !isFntv() || duration <= 0 || rollback != null) return
        val snapshot = target()
        // Resolve actual selected tracks, not the defaults from play/info.
        for ((type, field, streamKey) in listOf(
            Triple(C.TRACK_TYPE_AUDIO, "preferredAudioStreamId", "audioStreams"),
            Triple(C.TRACK_TYPE_TEXT, "preferredSubtitleStreamId", "subtitleStreams"),
        )) {
            val player = host.session.player ?: break
            val choices = NativePlaybackTrackChoices.buildNativeTrackChoices(player.currentTracks, type)
            val selected = choices.firstOrNull { it.selected }
            if (type == C.TRACK_TYPE_TEXT &&
                player.trackSelectionParameters.disabledTrackTypes.contains(type)) {
                snapshot.put(field, "")
            } else if (selected != null && !selected.isExternal) {
                val streams = rows(streamKey).filter { !it.optBoolean("isExternal") }
                    .sortedBy { it.optInt("index") }
                val matching = streams.filter {
                    selected.sourceLabel.isNotBlank() && it.optString("title") == selected.sourceLabel &&
                        it.optString("language") == selected.language
                }
                val stream = matching.singleOrNull() ?: streams.getOrNull(choices.indexOf(selected))
                if (stream != null) snapshot.put(field, stream.optString("id"))
            } else if (type == C.TRACK_TYPE_TEXT) {
                snapshot.put(field, if (selected?.isExternal == true &&
                    host.externalSubtitles.externalSubtitleSource?.originalUri?.toString() == loadedSubtitleUri
                ) loadedSubtitleId else "")
            }
        }
        progress.enqueue(snapshot.optString("itemId") + "|" + snapshot.optString("preferredMediaSourceId"),
            args(snapshot.toString()) + mapOf("positionMs" to position, "durationMs" to duration))
    }

    fun close() {
        if (closed) return
        closed = true
        invalidateMedia()
        val session = host.target.resolverSessionId
        progress.finish {
            invoke("closeNativeFntvSession", mapOf("resolverSessionId" to session)) {}
        }
    }

    fun invalidateMedia() {
        generation++
        busy = false
        rollback = null
        restoreTracks = null
        loadedSubtitleId = ""
        loadedSubtitleUri = ""
    }

    fun openQualityPicker() {
        val qualities = qualities()
        if (closed || !isFntv()) return
        if (isSwitching) {
            host.showToast("正在处理播放请求，请稍候")
            return
        }
        if (qualities.size < 2) {
            host.showToast(if (qualities.isEmpty()) {
                "飞牛未返回可切换画质，继续使用当前播放地址"
            } else "飞牛仅返回一个画质，没有其他画质可切换")
            return
        }
        val current = target().optInt("preferredPlaybackQualityIndex", 0)
        val dialog = AlertDialog.Builder(host.activity, R.style.NativePlaybackSettingsDialogTheme).setTitle("画质")
            .setSingleChoiceItems(qualities.map {
                buildList {
                    add(it.optString("resolution").ifBlank { "画质 ${it.optInt("index") + 1}" })
                    val bitrate = it.optLong("bitrate")
                    if (bitrate > 0) add(if (bitrate >= 1_000_000) {
                        String.format(Locale.ROOT, "%.1f Mbps", bitrate / 1_000_000.0)
                    } else "${bitrate / 1000} Kbps")
                    if (it.optBoolean("isM3u8")) add("HLS")
                }.joinToString(" · ")
            }.toTypedArray(), qualities.indexOfFirst { it.optInt("index") == current }) { picker, which ->
                picker.dismiss()
                val index = qualities[which].optInt("index")
                if (index != current) switchQuality(index)
            }.setNegativeButton("取消", null).create()
        host.settings.showTransientDialog(dialog, ControllerFocusTarget.SETTINGS)
    }

    fun switchQuality(index: Int) {
        if (closed || qualities().none { it.optInt("index") == index }) return
        if (isSwitching || host.episodes.isSwitching) return
        val oldPlayer = host.session.player ?: return
        val oldJson = host.target.playbackTargetJson
        val request = JSONObject(oldJson).put("preferredPlaybackQualityIndex", index)
            .put("streamUrl", "").put("headers", JSONObject())
        busy = true
        val token = ++generation
        host.showToast("正在解析画质")
        val timeout = Runnable {
            if (token == generation && busy) {
                generation++
                busy = false
                host.showToast("画质解析超时，已保留当前播放")
            }
        }
        host.playerView.postDelayed(timeout, 45_000)
        val dispatched = resolve(
            host.target.resolverSessionId, request.toString(),
        ) callback@{ result ->
            host.playerView.removeCallbacks(timeout)
            if (token != generation) return@callback
            busy = false
            if (host.activity.isFinishing || host.activity.isDestroyed ||
                host.session.player !== oldPlayer || host.target.playbackTargetJson != oldJson ||
                host.episodes.isSwitching) return@callback
            val json = result["playbackTargetJson"]?.toString().orEmpty()
            val next = runCatching { JSONObject(json) }.getOrNull()
            if (result["ok"] != true || next == null || next.optString("streamUrl").isBlank()) {
                host.showToast("画质解析失败，已保留当前播放")
                return@callback
            }
            val position = oldPlayer.currentPosition.coerceAtLeast(0)
            val playing = oldPlayer.playWhenReady
            val speed = oldPlayer.playbackParameters
            val parameters = oldPlayer.trackSelectionParameters
            val oldAudio = NativePlaybackTrackChoices.buildNativeTrackChoices(
                oldPlayer.currentTracks, C.TRACK_TYPE_AUDIO,
            ).firstOrNull { it.selected }
            val selectedSubtitle = NativePlaybackTrackChoices.buildNativeTrackChoices(
                oldPlayer.currentTracks, C.TRACK_TYPE_TEXT,
            ).firstOrNull { it.selected }
            val preference = host.subtitles.subtitleSessionPreference ?: when {
                parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT) ->
                    NativeSubtitleSessionPreference(NativeSubtitleSessionMode.OFF)
                selectedSubtitle != null -> NativeSubtitleSessionPreference(
                    NativeSubtitleSessionMode.SINGLE, primary = selectedSubtitle.subtitleFingerprint,
                )
                else -> null
            }
            val oldMime = host.activity.intent.getStringExtra(EXTRA_MEDIA_MIME_TYPE).orEmpty()
            host.runtime.persistPlaybackProgress(force = true)
            host.episodes.invalidateResolution()
            fun open(targetJson: String, mime: String) {
                host.session.releasePlayer()
                val value = JSONObject(targetJson)
                host.target.playbackTargetJson = targetJson
                host.activity.intent.putExtra(EXTRA_PLAYBACK_TARGET_JSON, targetJson)
                host.activity.intent.putExtra(EXTRA_URL, value.optString("streamUrl"))
                host.activity.intent.putExtra(EXTRA_HEADERS_JSON, value.optJSONObject("headers")?.toString() ?: "{}")
                host.activity.intent.putExtra(EXTRA_MEDIA_MIME_TYPE, mime)
                host.session.pendingResumePositionOverrideMs = position
                host.session.nextInitializePlayWhenReady = playing
                host.recovery.resetForNewMedia()
                host.launch.resetStartupDeadline()
                restoreTracks = {
                    val player = host.session.player
                    if (player != null) {
                        val choices = NativePlaybackTrackChoices.buildNativeTrackChoices(
                            player.currentTracks, C.TRACK_TYPE_AUDIO,
                        )
                        if (oldAudio == null || choices.isNotEmpty()) {
                            restoreTracks = null
                            val match = oldAudio?.let { old ->
                                NativeSubtitleSessionPreferencePolicy.match(
                                    choices.map(NativeTrackChoice::restoreCandidate), old.subtitleFingerprint,
                                )
                            }
                            val updated = player.trackSelectionParameters.buildUpon()
                                .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
                                .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO,
                                    parameters.disabledTrackTypes.contains(C.TRACK_TYPE_AUDIO))
                            if (match != null) updated.addOverride(match.override)
                            player.trackSelectionParameters = updated.build()
                        }
                    }
                }
                host.session.initializePlayer()
                host.subtitles.subtitleSessionPreference = preference
                host.subtitles.pendingExternalSubtitleSelection = false
                host.subtitles.automaticSubtitleSelectionApplied = false
                host.session.player?.playbackParameters = speed
            }
            rollback = { open(oldJson, oldMime) }
            try {
                open(json, result["mediaMimeType"]?.toString().orEmpty())
            } catch (_: Exception) {
                if (!recoverQualityFailure()) host.launch.handlePlaybackFailure("画质切换失败")
            }
        }
        if (!dispatched) {
            host.playerView.removeCallbacks(timeout)
            busy = false
            host.showToast("播放器解析服务未就绪")
        }
    }

    fun onReady() {
        if (rollback != null) {
            rollback = null
            host.showToast("画质已切换")
        }
    }
    fun onTracksReady() {
        val restore = restoreTracks ?: return
        if (host.session.player?.currentTracks?.groups?.isEmpty() != false) return
        restore()
    }
    fun recoverQualityFailure(): Boolean {
        val restore = rollback ?: return false
        rollback = null
        host.showToast("画质播放失败，正在恢复原画质")
        try {
            restore()
        } catch (_: Exception) {
            host.launch.handlePlaybackFailure("原画质恢复失败，请重试播放")
        }
        return true
    }

    fun loadSubtitle(stream: JSONObject) {
        if (closed || isSwitching || host.episodes.isSwitching) return
        val player = host.session.player ?: return
        val json = host.target.playbackTargetJson
        busy = true
        val token = ++generation
        host.showToast("正在下载飞牛字幕")
        invoke("downloadNativeFntvSubtitle", args(json) +
            mapOf("subtitleId" to stream.optString("id"))) callback@{ result ->
            if (token != generation) return@callback
            busy = false
            if (host.activity.isFinishing || host.activity.isDestroyed ||
                host.session.player !== player || host.target.playbackTargetJson != json ||
                host.episodes.isSwitching) return@callback
            if (result["ok"] != true) {
                host.showToast(result["message"]?.toString() ?: "飞牛字幕下载失败")
                return@callback
            }
            if (!host.externalSubtitles.loadCachedSubtitleFile(
                result["path"]?.toString().orEmpty(), result["displayName"]?.toString().orEmpty())) {
                return@callback
            }
            loadedSubtitleId = stream.optString("id")
            loadedSubtitleUri = host.externalSubtitles.externalSubtitleSource?.originalUri?.toString().orEmpty()
            host.target.playbackTargetJson = JSONObject(json)
                .put("preferredSubtitleStreamId", stream.optString("id")).toString()
            host.activity.intent.putExtra(EXTRA_PLAYBACK_TARGET_JSON, host.target.playbackTargetJson)
            host.runtime.persistPlaybackProgress(force = true)
        }
    }
}
