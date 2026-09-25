package com.example.starflow

import android.app.Activity
import android.app.AlertDialog
import android.app.Dialog
import androidx.media3.ui.PlayerView

internal class NativePlaybackSettingsController(private val host: Host) {
    interface Host {
        val fntv: NativeFntvController
        val controllerView: NativePlaybackControllerView
        val episodes: NativePlaybackEpisodeController
        val externalSubtitles: NativePlaybackExternalSubtitleController
        val subtitles: NativePlaybackTrackController
        val session: NativePlaybackSession
        val subtitleStyle: NativePlaybackSubtitleStyleController
        val target: NativePlaybackTarget
        val memory: NativePlaybackMemoryStore
        val runtime: NativePlaybackRuntimeController
        val systemSession: NativePlaybackSystemController
        val activity: Activity
        val playerView: PlayerView

        fun showToast(message: String)
    }

    private var playbackSettingsDialog: AlertDialog? = null

    private var trackSelectionDialog: Dialog? = null

    fun dismissSettingsDialog() {
        playbackSettingsDialog?.setOnDismissListener(null)
        playbackSettingsDialog?.dismiss()
        playbackSettingsDialog = null
    }

    fun dismissTrackDialog() {
        trackSelectionDialog?.setOnDismissListener(null)
        trackSelectionDialog?.dismiss()
        trackSelectionDialog = null
    }

    fun isOverlayDialogVisible(): Boolean {
        return playbackSettingsDialog?.isShowing == true ||
            host.episodes.isDialogVisible ||
            trackSelectionDialog?.isShowing == true
    }

    fun openPlaybackSettingsDialog() {
        if (host.externalSubtitles.subtitleSearchActive) {
            return
        }
        if (playbackSettingsDialog?.isShowing == true) {
            return
        }

        val actions = mutableListOf<Pair<String, () -> Unit>>()
        if (host.fntv.supportsPlaybackVersions()) {
            actions += "播放版本" to { host.fntv.openVersionPicker() }
        }
        host.fntv.qualitySettingsLabel()?.let { label ->
            actions += label to { host.fntv.openQualityPicker() }
        }
        actions +=
            "本剧跳过片头片尾 · ${formatSeriesSkipPreferenceSummary()}" to
                {
                    openSeriesSkipPreferenceDialog()
                }
        NativeAppLogger.info(
            "playback.fntv",
            "Playback settings menu source=${host.target.decodePlaybackTargetObject().optString("sourceKind")} " +
                "quality=${host.fntv.qualitySettingsLabel() ?: "-"} " +
                "audio=${host.fntv.audioSettingsLabel() ?: "-"} " +
                "subtitle=${host.fntv.subtitleSettingsLabel() ?: "-"}",
        )
        actions +=
            (host.fntv.audioSettingsLabel()
                ?: host.activity.getString(R.string.native_audio_track)) to
                {
                    host.subtitles.openAudioTrackSelectionDialog()
                }
        actions +=
            (host.fntv.subtitleSettingsLabel()
                ?: host.activity.getString(R.string.native_subtitle_track)) to
                {
                    host.subtitles.openSubtitleTrackSelectionDialog()
                }
        if ((host.episodes.episodeQueue?.entries?.size ?: 0) > 0) {
            actions += "选择剧集" to { host.episodes.openEpisodeSelectionDialog() }
        }
        actions +=
            host.activity.getString(R.string.native_more_actions) to
                {
                    openPlaybackMoreActionsDialog()
                }

        playbackSettingsDialog =
            AlertDialog.Builder(host.activity, R.style.NativePlaybackSettingsDialogTheme)
                .setTitle(host.activity.getString(R.string.native_playback_settings))
                .setItems(NativePlaybackSettingsAppearance.labels(host.activity, actions.map { it.first })) { dialog, which ->
                    dialog.dismiss()
                    host.playerView.post { actions[which].second.invoke() }
                }
                .setNegativeButton("关闭", null)
                .create()
                .apply {
                    setOnDismissListener {
                        playbackSettingsDialog = null
                        host.controllerView.restoreControllerFocusIfNeeded(
                            ControllerFocusTarget.SETTINGS
                        )
                    }
                    show()
                }
    }

    private fun openPlaybackMoreActionsDialog() {
        if (host.externalSubtitles.subtitleSearchActive) {
            return
        }
        val currentPlayer = host.session.player
        val actions = mutableListOf<Pair<String, () -> Unit>>()
        actions +=
            "${host.activity.getString(R.string.native_playback_speed)} · " +
                NativePlaybackFormatting.formatPlaybackSpeedLabel(
                    currentPlayer?.playbackParameters?.speed ?: 1f
                ) to { openPlaybackSpeedPicker() }
        actions +=
            "音频输出 · ${host.session.audioOutputMode.displayLabel}" to { openAudioOutputModePicker() }
        if (host.session.supportsFrameRateMatching) {
            actions += "刷新率匹配" to { openFrameRateMatchingDialog() }
        }
        actions +=
            "${host.activity.getString(R.string.native_subtitle_scale)} · " +
                NativePlaybackFormatting.formatSubtitleScaleLabel(
                    host.subtitleStyle.subtitleScale
                ) to { host.subtitleStyle.openSubtitleScalePicker() }
        actions +=
            "主字幕位置 · ${NativePlaybackFormatting.formatSubtitlePercentLabel(host.subtitleStyle.primarySubtitlePosition)}" to
                {
                    host.subtitleStyle.openPrimarySubtitlePositionPicker()
                }
        actions +=
            "副字幕位置 · ${NativePlaybackFormatting.formatSubtitlePercentLabel(host.subtitleStyle.secondarySubtitlePosition)}" to
                {
                    host.subtitleStyle.openSecondarySubtitlePositionPicker()
                }
        actions +=
            "副字幕大小 · ${NativePlaybackFormatting.formatSubtitlePercentLabel(host.subtitleStyle.secondarySubtitleScale)}" to
                {
                    host.subtitleStyle.openSecondarySubtitleScalePicker()
                }
        actions +=
            host.activity.getString(R.string.native_online_subtitle_search) to
                {
                    host.externalSubtitles.openOnlineSubtitleSearch()
                }
        actions +=
            host.activity.getString(R.string.native_external_subtitle) to
                {
                    host.externalSubtitles.openExternalSubtitlePicker()
                }
        actions +=
            "${host.activity.getString(R.string.native_subtitle_delay)} · ${NativePlaybackFormatting.formatSubtitleDelayLabel(host.externalSubtitles.subtitleDelayMs)}" to
                {
                    host.externalSubtitles.openSubtitleDelayPicker()
                }

        val dialog =
            AlertDialog.Builder(host.activity, R.style.NativePlaybackSettingsDialogTheme)
                .setTitle(host.activity.getString(R.string.native_more_actions))
                .setItems(NativePlaybackSettingsAppearance.labels(host.activity, actions.map { it.first })) { pickerDialog, which ->
                    pickerDialog.dismiss()
                    host.playerView.post { actions[which].second.invoke() }
                }
                .setNegativeButton("关闭", null)
                .create()
        showTransientDialog(dialog, ControllerFocusTarget.SETTINGS)
    }

    private fun openAudioOutputModePicker() {
        val options = NativeAudioOutputMode.entries
        val currentIndex = options.indexOf(host.session.audioOutputMode).coerceAtLeast(0)
        AlertDialog.Builder(host.activity, R.style.NativePlaybackSettingsDialogTheme)
            .setTitle("选择音频输出")
            .setSingleChoiceItems(
                options.map(NativeAudioOutputMode::displayLabel).toTypedArray(),
                currentIndex,
            ) { dialog, which ->
                val selected = options[which]
                dialog.dismiss()
                if (selected == host.session.audioOutputMode) {
                    host.controllerView.restoreControllerFocusIfNeeded(
                        ControllerFocusTarget.SETTINGS
                    )
                    return@setSingleChoiceItems
                }
                host.playerView.post { host.session.restartPlayerWithAudioOutputMode(selected) }
            }
            .setNegativeButton("取消", null)
            .show()
    }

    private fun openFrameRateMatchingDialog() {
        val dialog = AlertDialog.Builder(host.activity, R.style.NativePlaybackSettingsDialogTheme)
            .setTitle("刷新率匹配")
            .setMultiChoiceItems(
                arrayOf("匹配视频帧率（本次播放）"),
                booleanArrayOf(host.session.frameRateMatchingEnabled),
            ) { _, _, enabled -> host.session.setFrameRateMatching(enabled) }
            .setPositiveButton("完成", null)
            .create()
        showTransientDialog(dialog, ControllerFocusTarget.SETTINGS)
    }

    private fun openSeriesSkipPreferenceDialog() {
        if (host.target.seriesKey.isBlank()) {
            host.showToast("当前内容没有可绑定的剧集信息")
            host.controllerView.restoreControllerFocusIfNeeded(ControllerFocusTarget.SETTINGS)
            return
        }
        val currentPlayer = host.session.player
        val durationMs = currentPlayer?.duration?.takeIf { it > 0L } ?: 0L
        val positionMs = currentPlayer?.currentPosition?.coerceAtLeast(0L) ?: 0L
        val preference = host.memory.loadSeriesSkipPreference(host.target.seriesKey)
        val enabled = preference?.optBoolean("enabled", false) == true
        val introDurationMs = preference?.optLong("introDurationMs", 0L)?.coerceAtLeast(0L) ?: 0L
        val outroDurationMs = preference?.optLong("outroDurationMs", 0L)?.coerceAtLeast(0L) ?: 0L
        val canCaptureOutro = durationMs > 0L && positionMs > 0L && positionMs < durationMs
        val actions = mutableListOf<Pair<String, () -> Unit>>()

        actions +=
            "自动跳过 · ${if (enabled) "已开启" else "已关闭"}" to
                {
                    saveSeriesSkipPreference(
                        enabled = !enabled,
                        introDurationMs = introDurationMs,
                        outroDurationMs = outroDurationMs,
                    )
                    host.showToast(if (!enabled) "已开启自动跳过" else "已关闭自动跳过")
                }
        actions +=
            "片头结束位置 · ${
                if (introDurationMs > 0L) {
                    NativePlaybackFormatting.formatClockDuration(introDurationMs)
                } else {
                    "未设置"
                }
            } · 用当前位置 ${NativePlaybackFormatting.formatClockDuration(positionMs)}" to
                {
                    saveSeriesSkipPreference(
                        enabled = true,
                        introDurationMs = positionMs,
                        outroDurationMs = outroDurationMs,
                    )
                    host.showToast("已设置片头结束位置")
                }
        actions +=
            "片尾提前跳过 · ${
                if (outroDurationMs > 0L) {
                    "距结尾 ${NativePlaybackFormatting.formatClockDuration(outroDurationMs)}"
                } else {
                    "未设置"
                }
            } · 用当前位置 ${NativePlaybackFormatting.formatClockDuration(positionMs)}" to
                {
                    if (!canCaptureOutro) {
                        host.showToast("播放一小段后再设置片尾位置")
                    } else {
                        saveSeriesSkipPreference(
                            enabled = true,
                            introDurationMs = introDurationMs,
                            outroDurationMs = durationMs - positionMs,
                        )
                        host.showToast("已设置片尾跳过位置")
                    }
                }
        actions +=
            "清空本剧跳过规则" to
                {
                    saveSeriesSkipPreference(
                        enabled = false,
                        introDurationMs = 0L,
                        outroDurationMs = 0L,
                    )
                    host.showToast("已清空本剧跳过规则")
                }

        val dialog =
            AlertDialog.Builder(host.activity, R.style.NativePlaybackSettingsDialogTheme)
                .setTitle("本剧跳过片头片尾")
                .setItems(NativePlaybackSettingsAppearance.labels(host.activity, actions.map { it.first })) { pickerDialog, which ->
                    pickerDialog.dismiss()
                    host.playerView.post {
                        actions[which].second.invoke()
                        host.controllerView.restoreControllerFocusIfNeeded(
                            ControllerFocusTarget.SETTINGS
                        )
                    }
                }
                .setNegativeButton("关闭", null)
                .create()
        showTransientDialog(dialog, ControllerFocusTarget.SETTINGS)
    }

    private fun formatSeriesSkipPreferenceSummary(): String {
        val preference = host.memory.loadSeriesSkipPreference(host.target.seriesKey) ?: return "未设置"
        val enabled = preference.optBoolean("enabled", false)
        val introDurationMs = preference.optLong("introDurationMs", 0L)
        val outroDurationMs = preference.optLong("outroDurationMs", 0L)
        val parts = mutableListOf(if (enabled) "已开启" else "已关闭")
        if (introDurationMs > 0L) {
            parts += "片头 ${NativePlaybackFormatting.formatClockDuration(introDurationMs)}"
        }
        if (outroDurationMs > 0L) {
            parts += "片尾 ${NativePlaybackFormatting.formatClockDuration(outroDurationMs)}"
        }
        if (parts.size == 1 && !enabled) {
            return "未设置"
        }
        return parts.joinToString(" / ")
    }

    private fun saveSeriesSkipPreference(
        enabled: Boolean,
        introDurationMs: Long,
        outroDurationMs: Long,
    ) {
        val normalizedSeriesKey = host.target.seriesKey.trim()
        if (normalizedSeriesKey.isEmpty()) {
            return
        }
        host.memory.saveSeriesSkipPreference(
            seriesKey = normalizedSeriesKey,
            seriesTitle = host.target.buildSeriesSkipPreferenceTitle(),
            enabled = enabled,
            introDurationMs = introDurationMs,
            outroDurationMs = outroDurationMs,
        )
        host.controllerView.updateProgressMarkers()
        host.runtime.onSkipPreferenceChanged()
    }

    private fun openPlaybackSpeedPicker() {
        val currentPlayer = host.session.player ?: return
        val dialog = NativePlaybackNumberPicker.createStepped(
            activity = host.activity,
            title = host.activity.getString(R.string.native_playback_speed),
            current = currentPlayer.playbackParameters.speed.toDouble(),
            min = 0.75,
            max = 2.0,
            step = 0.05,
            format = { value ->
                NativePlaybackFormatting.formatPlaybackSpeedLabel(value.toFloat())
            },
        ) { value ->
            host.session.setPlaybackParameters(
                currentPlayer.playbackParameters.withSpeed(value.toFloat()),
            )
            host.systemSession.syncPlaybackSystemSession()
        }
        showTransientDialog(dialog, ControllerFocusTarget.SETTINGS)
    }

    fun showTransientDialog(dialog: Dialog, focusTarget: ControllerFocusTarget) {
        trackSelectionDialog?.dismiss()
        trackSelectionDialog = dialog
        dialog.setOnDismissListener {
            if (trackSelectionDialog === dialog) {
                trackSelectionDialog = null
            }
            host.controllerView.restoreControllerFocusIfNeeded(focusTarget)
        }
        dialog.show()
    }
}
