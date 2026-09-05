package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.ui.DefaultTrackNameProvider
import java.util.Locale

internal object NativePlaybackTrackChoices {
    fun buildNativeTrackChoices(
        tracks: Tracks,
        trackType: Int,
        trackNameProvider: DefaultTrackNameProvider? = null,
    ): List<NativeTrackChoice> {
        var subtitleIndex = 0
        return tracks.groups.flatMap { group ->
            if (group.type != trackType) {
                return@flatMap emptyList()
            }
            (0 until group.length).mapNotNull { trackIndex ->
                if (!group.isTrackSupported(trackIndex)) {
                    return@mapNotNull null
                }
                val format = group.getTrackFormat(trackIndex)
                val isDefault = format.selectionFlags and C.SELECTION_FLAG_DEFAULT != 0
                val isForced = format.selectionFlags and C.SELECTION_FLAG_FORCED != 0
                val isExternal = format.id?.startsWith("external:") == true
                val label =
                    if (trackType == C.TRACK_TYPE_TEXT) {
                        subtitleIndex += 1
                        NativeSubtitleTrackLabelPolicy.format(
                            title = format.label.orEmpty(),
                            language = format.language.orEmpty(),
                            isDefault = isDefault,
                            isForced = isForced,
                            isExternal = isExternal,
                            fallbackIndex = subtitleIndex,
                        )
                    } else {
                        trackNameProvider?.getTrackName(format).orEmpty()
                    }
                NativeTrackChoice(
                    label = label,
                    override = TrackSelectionOverride(group.mediaTrackGroup, trackIndex),
                    selected = group.isTrackSelected(trackIndex),
                    formatKey =
                        if (trackType == C.TRACK_TYPE_TEXT) {
                            NativeSubtitleFormatKey.from(format)
                        } else {
                            null
                        },
                    groupFormatKeys =
                        if (trackType == C.TRACK_TYPE_TEXT) {
                            (0 until group.length)
                                .map { index ->
                                    NativeSubtitleFormatKey.from(group.getTrackFormat(index))
                                }
                                .toSet()
                        } else {
                            emptySet()
                        },
                    language = format.language.orEmpty(),
                    sourceLabel = format.label.orEmpty(),
                    sampleMimeType = format.sampleMimeType.orEmpty(),
                    codecs = format.codecs.orEmpty(),
                    isDefault = isDefault,
                    isForced = isForced,
                    isExternal = isExternal,
                )
            }
        }
    }

    fun restoreNativeDualSubtitleChoice(
        choices: List<NativeTrackChoice>,
        preference: NativeSubtitleSessionPreference,
    ): NativeSubtitleRestoreResult.Dual? {
        val primaryFingerprint = preference.primary ?: return null
        val secondaryFingerprint = preference.secondary ?: return null
        val candidates = choices.filter(NativeTrackChoice::canUseInDualSubtitleMode)
        val primary =
            NativeSubtitleSessionPreferencePolicy.match(
                candidates.map(NativeTrackChoice::restoreCandidate),
                primaryFingerprint,
            ) ?: return null
        val primaryKey = primary.formatKey ?: return null
        val secondaryCandidates =
            candidates.filter { choice ->
                val key = choice.formatKey
                key != null && key != primaryKey && primaryKey !in choice.groupFormatKeys
            }
        val secondary =
            NativeSubtitleSessionPreferencePolicy.match(
                secondaryCandidates.map(NativeTrackChoice::restoreCandidate),
                secondaryFingerprint,
                excludedValues = setOf(primary),
            ) ?: return null
        return NativeSubtitleRestoreResult.Dual(primary, secondary)
    }

    fun buildDefaultNativeDualSubtitleChoice(
        choices: List<NativeTrackChoice>,
        primaryLanguage: NativeSubtitleLanguage,
        secondaryLanguage: NativeSubtitleLanguage,
    ): NativeSubtitleRestoreResult.Dual? {
        val candidates = choices.filter(NativeTrackChoice::canUseInDualSubtitleMode)
        val primary =
            NativeSubtitleTrackSelectionPolicy.selectLanguage(
                candidates = candidates.map(NativeTrackChoice::subtitleCandidate),
                preferredLanguages =
                    primaryLanguage.resolveLanguages(Locale.getDefault().toLanguageTag()),
            ) ?: return null
        val primaryKey = primary.formatKey ?: return null
        val secondaryCandidates =
            candidates.filter { choice ->
                val key = choice.formatKey
                key != null && key != primaryKey && primaryKey !in choice.groupFormatKeys
            }
        val secondary =
            NativeSubtitleTrackSelectionPolicy.selectLanguage(
                candidates = secondaryCandidates.map(NativeTrackChoice::subtitleCandidate),
                preferredLanguages =
                    secondaryLanguage.resolveLanguages(Locale.getDefault().toLanguageTag()),
            ) ?: return null
        return NativeSubtitleRestoreResult.Dual(primary, secondary)
    }
}
