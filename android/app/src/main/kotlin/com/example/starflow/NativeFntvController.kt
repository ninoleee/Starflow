package com.example.starflow

import android.app.Activity
import android.app.AlertDialog
import androidx.media3.common.C
import androidx.media3.ui.PlayerView
import org.json.JSONObject
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_URL
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_HEADERS_JSON
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_MEDIA_MIME_TYPE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_PLAYBACK_TARGET_JSON
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_PLAYBACK_ITEM_KEY
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_SERIES_KEY
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_EPISODE_QUEUE_JSON
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_TITLE

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
    private var initialAudioAppliedTo: androidx.media3.exoplayer.ExoPlayer? = null
    private var rollbackJson: String? = null
    private var rollbackTransportUrl: String? = null
    private var pendingTransportUrl: String? = null
    private var pendingPlaybackJson: String? = null
    private var closed = false
    private var loadedSubtitleId = ""
    private var loadedSubtitleUri = ""
    private var pendingSubtitleRevision: Long? = null
    private var automaticSubtitleLoadingAllowed = true
    private var versionPickerLoading = false
    private var resolutionTimeout: Runnable? = null

    fun cancelSubtitleLoad() {
        pendingSubtitleRevision = null
        automaticSubtitleLoadingAllowed = false
    }
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
    fun isTranscoding() = isFntv() && target().optString("fntvSessionLink").isNotBlank()
    fun qualities(): List<JSONObject> = rows("playbackQualities")
    fun qualitySettingsLabel(): String? {
        if (!isFntv()) return null
        val qualities = qualities()
        if (qualities.isEmpty()) return "画质 · 未返回可切换画质"
        val selected = qualities.firstOrNull {
            it.optInt("index") == target().optInt("preferredPlaybackQualityIndex", 0)
        } ?: qualities.first()
        val label = NativeFntvQualityMenu.title(selected)
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
        val snapshot = currentSelectionSnapshot()
        progress.enqueue(snapshot.optString("itemId") + "|" + snapshot.optString("preferredMediaSourceId"),
            args(snapshot.toString()) + mapOf("positionMs" to position, "durationMs" to duration))
    }

    private fun currentSelectionSnapshot(): JSONObject {
        val snapshot = target()
        // Resolve actual selected tracks, not the defaults from play/info.
        for ((type, field, streamKey) in if (isTranscoding()) emptyList() else listOf(
            Triple(C.TRACK_TYPE_AUDIO, "preferredAudioStreamId", "audioStreams"),
            Triple(C.TRACK_TYPE_TEXT, "preferredSubtitleStreamId", "subtitleStreams"),
        )) {
            val player = host.session.player ?: break
            if (type == C.TRACK_TYPE_AUDIO) {
                val tracks = NativePlaybackAudioTracks.list(player.currentTracks)
                val selected = tracks.firstOrNull { it.selected }
                val stream = selected?.let { NativePlaybackAudioTracks.serverStream(tracks, it, snapshot) }
                // Unknown identity must not overwrite the NAS preference with a guessed GUID.
                if (stream != null) snapshot.put(field, stream.optString("id"))
                continue
            }
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
                val allFormats = player.currentTracks.groups.filter { it.type == type }
                    .flatMap { group -> (0 until group.length).map { group.getTrackFormat(it) } }
                    .filter { it.id?.startsWith("external:") != true }
                val selectedFormat = selected.override.mediaTrackGroup.getFormat(selected.override.trackIndices.first())
                val stream = matching.singleOrNull() ?: if (allFormats.size == streams.size) {
                    streams.getOrNull(allFormats.indexOf(selectedFormat))
                } else null
                if (stream != null) snapshot.put(field, stream.optString("id"))
            } else if (type == C.TRACK_TYPE_TEXT && choices.isNotEmpty()) {
                snapshot.put(field, if (selected?.isExternal == true &&
                    host.externalSubtitles.externalSubtitleSource?.originalUri?.toString() == loadedSubtitleUri
                ) loadedSubtitleId else "")
            }
        }
        return snapshot
    }

    fun close() {
        if (closed) return
        closed = true
        invalidateMedia(release = false)
        val session = host.target.resolverSessionId
        invoke("closeNativePlaybackTransports", mapOf("resolverSessionId" to session)) {}
        progress.finish {
            invoke("closeNativeFntvSession", mapOf("resolverSessionId" to session)) {}
        }
    }

    fun invalidateMedia(release: Boolean = true) {
        resolutionTimeout?.let { host.playerView.removeCallbacks(it) }
        resolutionTimeout = null
        if (release) {
            releasePlayback(host.target.playbackTargetJson)
            rollbackJson?.let { releasePlayback(it) }
        }
        releaseTransport(rollbackTransportUrl)
        releaseTransport(pendingTransportUrl)
        rollbackTransportUrl = null
        pendingTransportUrl = null
        pendingPlaybackJson = null
        rollbackJson = null
        generation++
        busy = false
        rollback = null
        restoreTracks = null
        initialAudioAppliedTo = null
        loadedSubtitleId = ""
        loadedSubtitleUri = ""
        pendingSubtitleRevision = null
        automaticSubtitleLoadingAllowed = true
    }

    private fun releasePlayback(json: String, sessionId: String = host.target.resolverSessionId) {
        val value = runCatching { JSONObject(json) }.getOrNull() ?: return
        if (value.optString("fntvSessionLink").isBlank()) return
        invoke("releaseNativeFntvPlayback", mapOf(
            "resolverSessionId" to sessionId, "playbackTargetJson" to json,
        )) {}
    }

    private fun releaseTransport(url: String?, sessionId: String = host.target.resolverSessionId) {
        val transportUrl = url?.trim().orEmpty()
        if (!transportUrl.contains("/playback-relay/")) return
        invoke(
            "releaseNativePlaybackTransport",
            mapOf(
                "resolverSessionId" to sessionId,
                "transportUrl" to transportUrl,
            ),
        ) {}
    }

    private fun releaseResolvedTransport(result: Map<String, Any?>, sessionId: String) {
        releaseTransport(result["transportUrl"]?.toString(), sessionId)
    }

    fun unavailableAudioStreams(): List<JSONObject> {
        if (!isFntv() || isTranscoding()) return emptyList()
        val tracks = host.session.player?.let { NativePlaybackAudioTracks.list(it.currentTracks) }.orEmpty()
        return rows("audioStreams").filter { stream ->
            NativePlaybackAudioTracks.serverDefault(tracks,
                target().put("preferredAudioStreamId", stream.optString("id"))) == null
        }
    }

    fun requestServerAudio(stream: JSONObject) {
        if (closed || isSwitching || host.episodes.isSwitching || !isFntv()) return
        if (rows("audioStreams").none { it.optString("id") == stream.optString("id") }) return
        val profiles = qualities().filter { it.optBoolean("serverTranscode") }
        if (profiles.isEmpty()) {
            host.showToast("当前播放流无法使用此音轨，飞牛未提供可用转码档位")
            return
        }
        val snapshot = currentSelectionSnapshot()
        val requestGeneration = generation
        val presets = NativeFntvQualityMenu.presets(profiles, snapshot.optInt("preferredPlaybackQualityIndex", 0))
        val dialog = AlertDialog.Builder(host.activity, R.style.NativePlaybackSettingsDialogTheme)
            .setTitle("使用服务端音轨 · 选择转码画质")
            .setItems(presets.map(NativeFntvQualityMenu::title).toTypedArray()) { picker, which ->
                picker.dismiss()
                if (!closed && generation == requestGeneration && !isSwitching && !host.episodes.isSwitching &&
                    snapshot.optString("itemId") == target().optString("itemId") &&
                    snapshot.optString("preferredMediaSourceId") == target().optString("preferredMediaSourceId")) {
                    switchServerAudio(stream.optString("id"), presets[which].optInt("index"))
                }
            }.setNegativeButton("取消", null).create()
        host.settings.showTransientDialog(dialog, ControllerFocusTarget.AUDIO)
    }

    fun switchServerAudio(id: String, qualityIndex: Int) {
        if (closed || !isFntv() || rows("audioStreams").none { it.optString("id") == id } ||
            qualities().none { it.optInt("index") == qualityIndex && it.optBoolean("serverTranscode") }) return
        switchPlayback(currentSelectionSnapshot().put("preferredAudioStreamId", id)
            .put("preferredPlaybackQualityIndex", qualityIndex))
    }

    fun openServerTrackPicker(subtitle: Boolean): Boolean {
        if (!isTranscoding()) return false
        if (closed || isSwitching || host.episodes.isSwitching) return true
        val streams = rows(if (subtitle) "subtitleStreams" else "audioStreams")
        val field = if (subtitle) "preferredSubtitleStreamId" else "preferredAudioStreamId"
        val ids = (if (subtitle) listOf("") else emptyList()) + streams.map { it.optString("id") }
        val labels = (if (subtitle) listOf("关闭") else emptyList()) + streams.map {
            listOf(it.optString("title"), it.optString("language"), it.optString("codec"))
                .filter(String::isNotBlank).joinToString(" · ").ifBlank { "轨道 ${it.optInt("index") + 1}" }
        }
        val dialog = AlertDialog.Builder(host.activity, R.style.NativePlaybackSettingsDialogTheme)
            .setTitle(if (subtitle) "字幕选择" else "音轨选择")
            .setSingleChoiceItems(labels.toTypedArray(), ids.indexOf(target().optString(field))) { picker, which ->
                picker.dismiss()
                val stream = streams.firstOrNull { it.optString("id") == ids[which] }
                if (subtitle && stream?.optBoolean("isExternal") == true &&
                    target().optString("preferredSubtitleStreamId").isBlank()) {
                    loadSubtitle(stream)
                } else {
                    if (subtitle) host.subtitles.beginSubtitleSelection()
                    switchPlayback(target().put(field, ids[which]))
                }
            }.setNegativeButton("取消", null).create()
        host.settings.showTransientDialog(dialog, ControllerFocusTarget.SETTINGS)
        return true
    }

    fun openQualityPicker(custom: Boolean = false) {
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
        val presets = NativeFntvQualityMenu.presets(qualities, current)
        val options = if (custom) qualities else presets
        val labels = options.map { if (custom) NativeFntvQualityMenu.detail(it) else NativeFntvQualityMenu.title(it) } +
            if (!custom && presets.size < qualities.size) listOf("自定义") else emptyList()
        val dialog = AlertDialog.Builder(host.activity, R.style.NativePlaybackSettingsDialogTheme)
            .setTitle(if (custom) "自定义画质" else "画质")
            .setSingleChoiceItems(labels.toTypedArray(), options.indexOfFirst { it.optInt("index") == current }) { picker, which ->
                picker.dismiss()
                if (which == options.size) openQualityPicker(custom = true)
                else {
                    val index = options[which].optInt("index")
                    if (index != current) switchQuality(index)
                }
            }.setNegativeButton("取消", null).create()
        host.settings.showTransientDialog(dialog, ControllerFocusTarget.SETTINGS)
    }

    fun switchQuality(index: Int) {
        if (closed || qualities().none { it.optInt("index") == index }) return
        switchPlayback(currentSelectionSnapshot().put("preferredPlaybackQualityIndex", index))
    }

    fun supportsPlaybackVersions(): Boolean {
        val value = target()
        return value.optString("sourceId").isNotBlank() && value.optString("itemId").isNotBlank() &&
            value.optString("itemType").lowercase() in listOf("movie", "episode") &&
            value.optString("sourceKind") in listOf("nas", "quark", "emby", "fntv")
    }

    fun openVersionPicker() {
        if (closed || isSwitching || host.episodes.isSwitching || versionPickerLoading) return
        versionPickerLoading = true
        val original = host.target.playbackTargetJson
        val token = generation
        host.showToast("正在读取播放版本")
        invoke("browseNativePlaybackVersions", args()) callback@{ result ->
            versionPickerLoading = false
            if (closed || token != generation || host.target.playbackTargetJson != original ||
                host.activity.isFinishing || host.activity.isDestroyed ||
                host.episodes.isSwitching || isSwitching) return@callback
            val choices = (result["versions"] as? List<*>)?.mapNotNull { it as? Map<*, *> }.orEmpty()
            if (result["ok"] != true || choices.isEmpty()) {
                host.showToast("版本加载失败，请重试")
                return@callback
            }
            val selected = choices.indexOfFirst { it["selected"] == true }
            val labels = choices.map { it["label"]?.toString().orEmpty() }
            val dialog = AlertDialog.Builder(host.activity, R.style.NativePlaybackSettingsDialogTheme)
                .setTitle(if (choices.size == 1) "播放版本（仅一个）" else "播放版本")
                .setSingleChoiceItems(NativePlaybackSettingsAppearance.labels(host.activity, labels), selected) { picker, which ->
                    picker.dismiss()
                    if (which != selected && !closed && token == generation &&
                        host.target.playbackTargetJson == original) {
                        val request = runCatching { JSONObject(choices[which]["playbackTargetJson"].toString()) }.getOrNull()
                        if (request != null) switchVersion(request)
                    }
                }.setNegativeButton("取消", null).create()
            host.settings.showTransientDialog(dialog, ControllerFocusTarget.SETTINGS)
        }
    }

    // Version changes share the existing transactional reopen/rollback path.
    fun switchVersion(request: JSONObject) {
        if (!supportsPlaybackVersions() || request.optString("sourceId") != target().optString("sourceId")) return
        switchPlayback(request, switchingVersion = true)
    }

    private fun switchPlayback(request: JSONObject, switchingVersion: Boolean = false) {
        if (closed) return
        if (isSwitching || host.episodes.isSwitching) return
        val oldPlayer = host.session.player ?: return
        val oldJson = host.target.playbackTargetJson
        val resolverSessionId = host.target.resolverSessionId
        val subtitleRevision = host.subtitles.subtitleSelectionRevision
        if (!switchingVersion) request.put("streamUrl", "").put("headers", JSONObject())
            .put("fntvSessionLink", "")
            .put("fntvTrackSelectionExplicit", true)
            .put("fntvStartPositionMs", oldPlayer.currentPosition.coerceAtLeast(0))
        busy = true
        val token = ++generation
        host.showToast("正在解析播放设置")
        val timeout = Runnable {
            if (token == generation && busy) {
                resolutionTimeout = null
                generation++
                busy = false
                host.showToast("播放设置解析超时，已保留当前播放")
            }
        }
        resolutionTimeout = timeout
        host.playerView.postDelayed(timeout, 45_000)
        val dispatched = resolve(
            resolverSessionId, request.toString(),
        ) callback@{ result ->
            host.playerView.removeCallbacks(timeout)
            if (resolutionTimeout === timeout) resolutionTimeout = null
            if (token != generation) {
                releasePlayback(result["playbackTargetJson"]?.toString().orEmpty(), resolverSessionId)
                releaseResolvedTransport(result, resolverSessionId)
                return@callback
            }
            busy = false
            if (host.activity.isFinishing || host.activity.isDestroyed ||
                host.session.player !== oldPlayer || host.target.playbackTargetJson != oldJson ||
                subtitleRevision != host.subtitles.subtitleSelectionRevision ||
                host.episodes.isSwitching) {
                releasePlayback(result["playbackTargetJson"]?.toString().orEmpty(), resolverSessionId)
                releaseResolvedTransport(result, resolverSessionId)
                return@callback
            }
            val json = result["playbackTargetJson"]?.toString().orEmpty()
            val next = runCatching { JSONObject(json) }.getOrNull()
            if (result["ok"] != true || next == null || next.optString("streamUrl").isBlank()) {
                releasePlayback(json, resolverSessionId)
                releaseResolvedTransport(result, resolverSessionId)
                host.showToast("播放设置解析失败，已保留当前播放")
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
            val oldTransportUrl = host.activity.intent.getStringExtra(EXTRA_URL).orEmpty()
            val oldTransportHeaders = host.activity.intent.getStringExtra(EXTRA_HEADERS_JSON).orEmpty()
            val oldKey = host.target.playbackItemKey
            val oldSeriesKey = host.target.seriesKey
            val oldQueue = host.episodes.episodeQueue
            val oldExternal = host.externalSubtitles.externalSubtitleSource
            host.runtime.persistPlaybackProgress(force = true)
            host.episodes.invalidateResolution()
            fun open(targetJson: String, mime: String, restoring: Boolean = false) {
                host.session.releasePlayer()
                loadedSubtitleId = ""
                loadedSubtitleUri = ""
                pendingSubtitleRevision = null
                automaticSubtitleLoadingAllowed = true
                val value = JSONObject(targetJson)
                if (switchingVersion) {
                    val itemKey = if (restoring) oldKey else result["playbackItemKey"]?.toString() ?: oldKey
                    val seriesKey = if (restoring) oldSeriesKey else result["seriesKey"]?.toString() ?: oldSeriesKey
                    host.target.playbackItemKey = itemKey
                    host.target.seriesKey = seriesKey
                    val queue = if (restoring) oldQueue else oldQueue?.replaceEntry(
                        oldQueue.currentIndex, NativeEpisodeQueueEntry(targetJson, itemKey, seriesKey, mime),
                    )
                    host.episodes.episodeQueue = queue
                    host.activity.intent.putExtra(EXTRA_PLAYBACK_ITEM_KEY, itemKey)
                    host.activity.intent.putExtra(EXTRA_SERIES_KEY, seriesKey)
                    host.activity.intent.putExtra(EXTRA_EPISODE_QUEUE_JSON, queue?.toJsonString().orEmpty())
                    host.activity.intent.putExtra(EXTRA_TITLE, value.optString("title"))
                    host.runtime.resetForNewMedia()
                }
                host.externalSubtitles.externalSubtitleSource = if (restoring) oldExternal else null
                host.target.playbackTargetJson = targetJson
                host.activity.intent.putExtra(EXTRA_PLAYBACK_TARGET_JSON, targetJson)
                val transportUrl = if (restoring) oldTransportUrl else result["transportUrl"]?.toString().orEmpty()
                val transportHeaders = if (restoring) oldTransportHeaders else
                    (result["transportHeaders"] as? Map<*, *>)?.let { JSONObject(it).toString() }.orEmpty()
                host.activity.intent.putExtra(EXTRA_URL, transportUrl.ifBlank { value.optString("streamUrl") })
                host.activity.intent.putExtra(EXTRA_HEADERS_JSON, transportHeaders.ifBlank { value.optJSONObject("headers")?.toString() ?: "{}" })
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
                            val audioTracks = NativePlaybackAudioTracks.list(player.currentTracks)
                            val serverChoice = if (value.optString("fntvSessionLink").isNotBlank()) {
                                audioTracks.firstOrNull { it.supported }
                            } else NativePlaybackAudioTracks.serverDefault(audioTracks, value)
                            val updated = player.trackSelectionParameters.buildUpon()
                                .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
                                .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO,
                                    parameters.disabledTrackTypes.contains(C.TRACK_TYPE_AUDIO))
                            if (serverChoice != null) updated.addOverride(serverChoice.override)
                            else if (match != null) updated.addOverride(match.override)
                            player.trackSelectionParameters = updated.build()
                        }
                    }
                }
                if (switchingVersion && !restoring) restoreTracks = null
                host.session.stagePlaybackParameters(speed)
                pendingTransportUrl = if (restoring) null else transportUrl
                host.session.initializePlayer()
                host.subtitles.subtitleSessionPreference = when {
                    switchingVersion && !restoring -> null
                    value.optBoolean("fntvTrackSelectionExplicit") &&
                        value.optString("preferredSubtitleStreamId").isBlank() ->
                        NativeSubtitleSessionPreference(NativeSubtitleSessionMode.OFF)
                    value.optString("fntvSessionLink").isNotBlank() -> null
                    else -> preference
                }
                host.subtitles.pendingExternalSubtitleSelection = false
                host.subtitles.automaticSubtitleSelectionApplied = false
            }
            rollback = { open(oldJson, oldMime, restoring = true) }
            rollbackJson = oldJson
            rollbackTransportUrl = oldTransportUrl
            pendingTransportUrl = result["transportUrl"]?.toString()
            pendingPlaybackJson = json
            try {
                open(json, result["mediaMimeType"]?.toString().orEmpty())
            } catch (_: Exception) {
                if (!recoverQualityFailure()) host.launch.handlePlaybackFailure("画质切换失败")
            }
        }
        if (!dispatched) {
            host.playerView.removeCallbacks(timeout)
            if (resolutionTimeout === timeout) resolutionTimeout = null
            busy = false
            host.showToast("播放器解析服务未就绪")
        }
    }

    fun onReady() {
        if (rollback != null) {
            rollback = null
            rollbackJson?.let { releasePlayback(it) }
            rollbackJson = null
            if (rollbackTransportUrl != pendingTransportUrl) releaseTransport(rollbackTransportUrl)
            rollbackTransportUrl = null
            pendingTransportUrl = null
            pendingPlaybackJson = null
            host.showToast("播放设置已切换")
        }
        if (isTranscoding() && !busy && automaticSubtitleLoadingAllowed && pendingSubtitleRevision == null) {
            externalSubtitles().firstOrNull {
                it.optString("id") == target().optString("preferredSubtitleStreamId") &&
                    it.optString("id") != loadedSubtitleId
            }?.let(::loadSubtitle)
        }
    }
    fun onTracksReady() {
        val player = host.session.player ?: return
        if (player.currentTracks.groups.isEmpty()) return
        val restore = restoreTracks
        if (restore != null) {
            initialAudioAppliedTo = player
            restore()
            return
        }
        if (!isFntv() || isTranscoding() || initialAudioAppliedTo === player) return
        val choices = NativePlaybackAudioTracks.list(player.currentTracks)
        if (choices.isEmpty()) return
        initialAudioAppliedTo = player
        if (player.trackSelectionParameters.overrides.values.any { it.type == C.TRACK_TYPE_AUDIO }) return
        val preferred = NativePlaybackAudioTracks.serverDefault(choices, target()) ?: return
        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_AUDIO).setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
            .addOverride(preferred.override).build()
    }
    fun recoverQualityFailure(): Boolean {
        val restore = rollback ?: return false
        rollback = null
        pendingPlaybackJson?.let { releasePlayback(it) }
        pendingPlaybackJson = null
        if (pendingTransportUrl != rollbackTransportUrl) releaseTransport(pendingTransportUrl)
        pendingTransportUrl = null
        rollbackJson = null
        rollbackTransportUrl = null
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
        val revision = host.subtitles.beginSubtitleSelection(keepExternalSource = true)
        pendingSubtitleRevision = revision
        val token = generation
        host.showToast("正在下载飞牛字幕")
        invoke("downloadNativeFntvSubtitle", args(json) +
            mapOf("subtitleId" to stream.optString("id"))) callback@{ result ->
            if (token != generation || revision != pendingSubtitleRevision ||
                revision != host.subtitles.subtitleSelectionRevision) {
                host.externalSubtitles.discardFntvDownload(result["path"]?.toString().orEmpty())
                return@callback
            }
            pendingSubtitleRevision = null
            if (closed || host.activity.isFinishing || host.activity.isDestroyed ||
                host.session.player !== player || host.target.playbackTargetJson != json ||
                host.episodes.isSwitching) {
                host.externalSubtitles.discardFntvDownload(result["path"]?.toString().orEmpty())
                return@callback
            }
            if (result["ok"] != true) {
                host.showToast(result["message"]?.toString() ?: "飞牛字幕下载失败")
                return@callback
            }
            host.externalSubtitles.loadCachedSubtitleFile(
                result["path"]?.toString().orEmpty(), result["displayName"]?.toString().orEmpty(),
                onApplied = {
                    if (token == generation && revision == host.subtitles.subtitleSelectionRevision &&
                        host.target.playbackTargetJson == json) {
                        loadedSubtitleId = stream.optString("id")
                        loadedSubtitleUri = host.externalSubtitles.externalSubtitleSource?.originalUri?.toString().orEmpty()
                        host.target.playbackTargetJson = JSONObject(json)
                            .put("preferredSubtitleStreamId", stream.optString("id")).toString()
                        host.activity.intent.putExtra(EXTRA_PLAYBACK_TARGET_JSON, host.target.playbackTargetJson)
                        host.runtime.persistPlaybackProgress(force = true)
                    }
                }, selectionRevision = revision)
        }
    }
}
