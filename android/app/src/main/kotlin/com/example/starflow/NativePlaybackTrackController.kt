package com.example.starflow

import android.app.Activity
import android.app.AlertDialog
import androidx.media3.common.C
import androidx.media3.common.Tracks
import androidx.media3.ui.DefaultTrackNameProvider
import androidx.media3.ui.PlayerView
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_DEFAULT_SUBTITLE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_DUAL_SUBTITLE_PRIMARY_LANGUAGE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_DUAL_SUBTITLE_SECONDARY_LANGUAGE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_SUBTITLE_PREFERENCE
import java.util.Locale

internal class NativePlaybackTrackController(private val host: Host) {
    interface Host {
        val controllerView: NativePlaybackControllerView
        val session: NativePlaybackSession
        val subtitleStyle: NativePlaybackSubtitleStyleController
        val memory: NativePlaybackMemoryStore
        val target: NativePlaybackTarget
        val settings: NativePlaybackSettingsController
        val activity: Activity

        fun showToast(message: String)

        val playerView: PlayerView
    }

    var automaticSubtitleSelectionApplied = false

    var subtitleSessionPreference: NativeSubtitleSessionPreference? = null

    val dualSubtitleController = NativeDualSubtitleController()

    fun subtitlePreferenceIsOff(): Boolean =
        host.activity.intent.getStringExtra(EXTRA_SUBTITLE_PREFERENCE)?.trim() == "off"

    private fun defaultSubtitleMode(): NativeDefaultSubtitle {
        return NativeDefaultSubtitle.fromRaw(
            host.activity.intent.getStringExtra(EXTRA_DEFAULT_SUBTITLE).orEmpty()
        )
    }

    private fun dualSubtitlePrimaryLanguage(): NativeSubtitleLanguage {
        return NativeSubtitleLanguage.fromRaw(
            raw =
                host.activity.intent.getStringExtra(EXTRA_DUAL_SUBTITLE_PRIMARY_LANGUAGE).orEmpty(),
            fallback = NativeSubtitleLanguage.SIMPLIFIED_CHINESE,
        )
    }

    private fun dualSubtitleSecondaryLanguage(): NativeSubtitleLanguage {
        return NativeSubtitleLanguage.fromRaw(
            raw =
                host.activity.intent
                    .getStringExtra(EXTRA_DUAL_SUBTITLE_SECONDARY_LANGUAGE)
                    .orEmpty(),
            fallback = NativeSubtitleLanguage.ENGLISH,
        )
    }

    fun applyAutomaticSubtitleSelection(tracks: Tracks) {
        if (automaticSubtitleSelectionApplied) {
            return
        }
        val currentPlayer = host.session.player ?: return
        val choices =
            NativePlaybackTrackChoices.buildNativeTrackChoices(
                tracks = tracks,
                trackType = C.TRACK_TYPE_TEXT,
            )
        if (choices.isEmpty()) {
            return
        }

        automaticSubtitleSelectionApplied = true
        val sessionPreference = subtitleSessionPreference
        val restoredSession =
            when (sessionPreference?.mode) {
                NativeSubtitleSessionMode.OFF -> NativeSubtitleRestoreResult.Disabled
                NativeSubtitleSessionMode.SINGLE -> {
                    val fingerprint = sessionPreference.primary
                    val selected =
                        fingerprint?.let { preferred ->
                            NativeSubtitleSessionPreferencePolicy.match(
                                choices.map(NativeTrackChoice::restoreCandidate),
                                preferred,
                            )
                        }
                    selected?.let(NativeSubtitleRestoreResult::Single)
                }
                NativeSubtitleSessionMode.DUAL ->
                    NativePlaybackTrackChoices.restoreNativeDualSubtitleChoice(
                        choices,
                        sessionPreference,
                    )
                null -> null
            }
        val restored =
            restoredSession
                ?: if (
                    !subtitlePreferenceIsOff() &&
                        defaultSubtitleMode() == NativeDefaultSubtitle.DUAL
                ) {
                    NativePlaybackTrackChoices.buildDefaultNativeDualSubtitleChoice(
                        choices,
                        dualSubtitlePrimaryLanguage(),
                        dualSubtitleSecondaryLanguage(),
                    )
                } else {
                    null
                }
        if (restored is NativeSubtitleRestoreResult.Dual) {
            enableDualSubtitleRouting(restored.primary, restored.secondary)
        } else {
            dualSubtitleController.disable()
            host.subtitleStyle.applySubtitleStyle()
        }

        val selected =
            when (restored) {
                NativeSubtitleRestoreResult.Disabled -> null
                is NativeSubtitleRestoreResult.Single -> restored.choice.override
                is NativeSubtitleRestoreResult.Dual -> restored.primary.override
                null ->
                    if (subtitlePreferenceIsOff()) {
                        null
                    } else {
                        NativeSubtitleTrackSelectionPolicy.selectWithSystemFallback(
                            candidates =
                                choices.map { choice ->
                                    NativeSubtitleTrackCandidate(
                                        value = choice.override,
                                        language = choice.language,
                                        label = choice.sourceLabel,
                                        isForced = choice.isForced,
                                        isDefault = choice.isDefault,
                                    )
                                },
                            preferredLanguages = defaultSubtitleMode().preferredLanguages,
                            systemLanguage = Locale.getDefault().toLanguageTag(),
                        )
                    }
            }
        val parameters =
            currentPlayer.trackSelectionParameters
                .buildUpon()
                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, selected == null)
        if (selected != null) {
            parameters.addOverride(selected)
        }
        currentPlayer.trackSelectionParameters = parameters.build()
    }

    fun openAudioTrackSelectionDialog() {
        openTrackSelectionDialog(
            title = host.activity.getString(R.string.native_audio_track),
            trackType = C.TRACK_TYPE_AUDIO,
            showDisableOption = false,
            emptyMessage = host.activity.getString(R.string.native_no_audio_tracks),
            focusTarget = ControllerFocusTarget.AUDIO,
        )
    }

    fun openSubtitleTrackSelectionDialog() {
        openTrackSelectionDialog(
            title = host.activity.getString(R.string.native_subtitle_track),
            trackType = C.TRACK_TYPE_TEXT,
            showDisableOption = true,
            emptyMessage = host.activity.getString(R.string.native_no_subtitle_tracks),
            focusTarget = ControllerFocusTarget.SUBTITLE,
        )
    }

    private fun openTrackSelectionDialog(
        title: String,
        trackType: Int,
        showDisableOption: Boolean,
        emptyMessage: String,
        focusTarget: ControllerFocusTarget,
    ) {
        val currentPlayer = host.session.player ?: return
        val trackNameProvider = DefaultTrackNameProvider(host.activity.resources)
        val choices =
            NativePlaybackTrackChoices.buildNativeTrackChoices(
                tracks = currentPlayer.currentTracks,
                trackType = trackType,
                trackNameProvider = trackNameProvider,
            )
        if (choices.isEmpty()) {
            host.showToast(emptyMessage)
            host.controllerView.restoreControllerFocusIfNeeded(focusTarget)
            return
        }
        val showDualSubtitleOption = trackType == C.TRACK_TYPE_TEXT
        val showGlobalDefaultOption = trackType == C.TRACK_TYPE_TEXT
        val choiceOffset =
            when {
                showDualSubtitleOption && showGlobalDefaultOption -> 3
                showDisableOption -> 1
                else -> 0
            }
        val labels =
            buildList {
                    if (showDisableOption) {
                        add("关闭")
                    }
                    if (showGlobalDefaultOption) {
                        add("使用全局默认")
                    }
                    if (showDualSubtitleOption) {
                        add(
                            if (dualSubtitleController.isEnabled) {
                                "特殊：双字幕模式（当前）"
                            } else {
                                "特殊：双字幕模式"
                            }
                        )
                    }
                    addAll(choices.map(NativeTrackChoice::label))
                }
                .toTypedArray()
        val selectedChoiceIndex = choices.indexOfFirst(NativeTrackChoice::selected)
        val checkedIndex =
            when {
                showDualSubtitleOption && dualSubtitleController.isEnabled -> 2
                showGlobalDefaultOption && subtitleSessionPreference == null -> 1
                subtitleSessionPreference?.mode == NativeSubtitleSessionMode.OFF -> 0
                selectedChoiceIndex >= 0 -> selectedChoiceIndex + choiceOffset
                showDisableOption -> 0
                else -> -1
            }
        val dialog =
            AlertDialog.Builder(host.activity)
                .setTitle(title)
                .setSingleChoiceItems(labels, checkedIndex) { pickerDialog, which ->
                    val parameters =
                        currentPlayer.trackSelectionParameters
                            .buildUpon()
                            .clearOverridesOfType(trackType)
                    if (showDisableOption && which == 0) {
                        dualSubtitleController.disable()
                        host.subtitleStyle.applySubtitleStyle()
                        parameters.setTrackTypeDisabled(trackType, true)
                        if (trackType == C.TRACK_TYPE_TEXT) {
                            subtitleSessionPreference =
                                NativeSubtitleSessionPreference(
                                    mode = NativeSubtitleSessionMode.OFF
                                )
                            host.memory.saveSeriesSubtitlePreference(
                                host.target.seriesKey,
                                subtitleSessionPreference,
                            )
                        }
                    } else if (showGlobalDefaultOption && which == 1) {
                        pickerDialog.dismiss()
                        subtitleSessionPreference = null
                        host.memory.clearSeriesSubtitlePreference(host.target.seriesKey)
                        dualSubtitleController.disable()
                        host.subtitleStyle.applySubtitleStyle()
                        automaticSubtitleSelectionApplied = false
                        host.playerView.post {
                            applyAutomaticSubtitleSelection(currentPlayer.currentTracks)
                        }
                        return@setSingleChoiceItems
                    } else if (showDualSubtitleOption && which == 2) {
                        pickerDialog.dismiss()
                        host.playerView.post { openDualSubtitlePrimaryPicker(choices) }
                        return@setSingleChoiceItems
                    } else {
                        val choice = choices[which - choiceOffset]
                        if (trackType == C.TRACK_TYPE_TEXT) {
                            dualSubtitleController.disable()
                            host.subtitleStyle.applySubtitleStyle()
                            subtitleSessionPreference =
                                if (choice.isExternal) {
                                    null
                                } else {
                                    NativeSubtitleSessionPreference(
                                        mode = NativeSubtitleSessionMode.SINGLE,
                                        primary = choice.subtitleFingerprint,
                                    )
                                }
                            if (!choice.isExternal) {
                                host.memory.saveSeriesSubtitlePreference(
                                    host.target.seriesKey,
                                    subtitleSessionPreference,
                                )
                            }
                        }
                        parameters
                            .setTrackTypeDisabled(trackType, false)
                            .addOverride(choice.override)
                    }
                    currentPlayer.trackSelectionParameters = parameters.build()
                    pickerDialog.dismiss()
                }
                .setNegativeButton("取消", null)
                .create()
        host.settings.showTransientDialog(dialog, focusTarget)
    }

    private fun openDualSubtitlePrimaryPicker(choices: List<NativeTrackChoice>) {
        val textChoices =
            choices.filter(NativeTrackChoice::canUseInDualSubtitleMode).sortedByDescending { choice
                ->
                NativeDualSubtitleTrackPolicy.isLikelyChinese(choice.language, choice.sourceLabel)
            }
        if (textChoices.size < 2) {
            host.showToast("双字幕模式至少需要两条文本字幕")
            host.controllerView.restoreControllerFocusIfNeeded(ControllerFocusTarget.SUBTITLE)
            return
        }
        val dialog =
            AlertDialog.Builder(host.activity)
                .setTitle("双字幕：选择上方中文")
                .setItems(textChoices.map(NativeTrackChoice::label).toTypedArray()) {
                    pickerDialog,
                    which ->
                    val primaryChoice = textChoices[which]
                    pickerDialog.dismiss()
                    host.playerView.post {
                        openDualSubtitleSecondaryPicker(
                            choices = textChoices,
                            primaryChoice = primaryChoice,
                        )
                    }
                }
                .setNegativeButton("取消", null)
                .create()
        host.settings.showTransientDialog(dialog, ControllerFocusTarget.SUBTITLE)
    }

    private fun openDualSubtitleSecondaryPicker(
        choices: List<NativeTrackChoice>,
        primaryChoice: NativeTrackChoice,
    ) {
        val primaryKey = primaryChoice.formatKey ?: return
        val secondaryChoices =
            choices
                .filter { choice ->
                    val key = choice.formatKey
                    choice.canUseInDualSubtitleMode &&
                        key != null &&
                        key != primaryKey &&
                        primaryKey !in choice.groupFormatKeys
                }
                .sortedByDescending { choice ->
                    NativeDualSubtitleTrackPolicy.isLikelyEnglish(
                        choice.language,
                        choice.sourceLabel,
                    )
                }
        if (secondaryChoices.isEmpty()) {
            host.showToast("当前字幕轨不能组成中英双字幕")
            host.controllerView.restoreControllerFocusIfNeeded(ControllerFocusTarget.SUBTITLE)
            return
        }
        val dialog =
            AlertDialog.Builder(host.activity)
                .setTitle("双字幕：选择下方英文")
                .setItems(secondaryChoices.map(NativeTrackChoice::label).toTypedArray()) {
                    pickerDialog,
                    which ->
                    val secondaryChoice = secondaryChoices[which]
                    pickerDialog.dismiss()
                    enableDualSubtitleMode(primaryChoice, secondaryChoice)
                }
                .setNegativeButton("取消", null)
                .create()
        host.settings.showTransientDialog(dialog, ControllerFocusTarget.SUBTITLE)
    }

    private fun enableDualSubtitleMode(
        primaryChoice: NativeTrackChoice,
        secondaryChoice: NativeTrackChoice,
    ) {
        val currentPlayer = host.session.player ?: return
        if (primaryChoice.formatKey == null || secondaryChoice.formatKey == null) {
            return
        }
        enableDualSubtitleRouting(primaryChoice, secondaryChoice)
        currentPlayer.trackSelectionParameters =
            currentPlayer.trackSelectionParameters
                .buildUpon()
                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                .addOverride(primaryChoice.override)
                .build()
        subtitleSessionPreference =
            NativeSubtitleSessionPreference(
                mode = NativeSubtitleSessionMode.DUAL,
                primary = primaryChoice.subtitleFingerprint,
                secondary = secondaryChoice.subtitleFingerprint,
            )
        host.memory.saveSeriesSubtitlePreference(host.target.seriesKey, subtitleSessionPreference)
        NativePlaybackFormatting.logPlayback(
            "native.subtitle.dual-enabled " +
                "primary=${primaryChoice.label} secondary=${secondaryChoice.label}"
        )
        host.showToast("双字幕已开启：中文在上，英文在下")
        host.controllerView.restoreControllerFocusIfNeeded(ControllerFocusTarget.SUBTITLE)
    }

    private fun enableDualSubtitleRouting(
        primaryChoice: NativeTrackChoice,
        secondaryChoice: NativeTrackChoice,
    ) {
        val primaryKey = primaryChoice.formatKey ?: return
        val secondaryKey = secondaryChoice.formatKey ?: return
        dualSubtitleController.enable(
            primaryKey = primaryKey,
            secondaryKey = secondaryKey,
            secondaryGroupKeys = secondaryChoice.groupFormatKeys,
        )
        host.subtitleStyle.applySubtitleStyle()
    }
}
