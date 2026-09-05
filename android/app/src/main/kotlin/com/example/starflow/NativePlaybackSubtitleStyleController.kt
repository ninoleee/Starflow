package com.example.starflow

import android.app.Activity
import android.app.AlertDialog
import android.graphics.Color
import android.graphics.Typeface
import android.view.accessibility.CaptioningManager
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import androidx.media3.ui.SubtitleView

internal class NativePlaybackSubtitleStyleController(private val host: Host) {
    interface Host {
        val settings: NativePlaybackSettingsController
        val subtitles: NativePlaybackTrackController
        val activity: Activity

        fun showToast(message: String)

        val playerView: PlayerView
        val isTelevisionDevice: Boolean
    }

    var subtitleScale: Double = NativeSubtitleStylePolicy.DEFAULT_SCALE

    var primarySubtitlePosition = 80.0

    var secondarySubtitlePosition = 90.0

    var secondarySubtitleScale = NativeDualSubtitleLayoutPolicy.SECONDARY_TEXT_SCALE_PERCENT

    fun openSubtitleScalePicker() {
        val options = SUBTITLE_SCALE_OPTIONS
        val currentIndex =
            options
                .withIndex()
                .minByOrNull { (_, value) -> kotlin.math.abs(value - subtitleScale) }
                ?.index ?: 0
        val labels =
            options
                .mapIndexed { index, value ->
                    val label = NativePlaybackFormatting.formatSubtitleScaleLabel(value)
                    if (index == currentIndex) "$label  当前" else label
                }
                .toTypedArray()
        val dialog =
            AlertDialog.Builder(host.activity)
                .setTitle(host.activity.getString(R.string.native_subtitle_scale))
                .setSingleChoiceItems(labels, currentIndex) { pickerDialog, which ->
                    val selected = options[which]
                    pickerDialog.dismiss()
                    if (kotlin.math.abs(selected - subtitleScale) >= 0.5) {
                        subtitleScale = selected
                        applySubtitleStyle()
                        persistGlobalSubtitleStyle()
                        host.showToast(
                            "主字幕大小已设为${NativePlaybackFormatting.formatSubtitleScaleLabel(selected)}"
                        )
                    }
                }
                .setNegativeButton("取消", null)
                .create()
        host.settings.showTransientDialog(dialog, ControllerFocusTarget.SETTINGS)
    }

    fun openPrimarySubtitlePositionPicker() {
        openSubtitlePercentPicker(
            title = "主字幕位置",
            options = SUBTITLE_POSITION_OPTIONS,
            current = primarySubtitlePosition,
        ) { selected ->
            primarySubtitlePosition = selected
            applyDualSubtitleLayoutSettings()
        }
    }

    fun openSecondarySubtitlePositionPicker() {
        openSubtitlePercentPicker(
            title = "副字幕位置",
            options = SUBTITLE_POSITION_OPTIONS,
            current = secondarySubtitlePosition,
        ) { selected ->
            secondarySubtitlePosition = selected
            applyDualSubtitleLayoutSettings()
        }
    }

    fun openSecondarySubtitleScalePicker() {
        openSubtitlePercentPicker(
            title = "副字幕大小",
            options = SECONDARY_SUBTITLE_SCALE_OPTIONS,
            current = secondarySubtitleScale,
        ) { selected ->
            secondarySubtitleScale = selected
            applyDualSubtitleLayoutSettings()
        }
    }

    private fun openSubtitlePercentPicker(
        title: String,
        options: List<Double>,
        current: Double,
        onSelected: (Double) -> Unit,
    ) {
        val currentIndex =
            options
                .withIndex()
                .minByOrNull { (_, value) -> kotlin.math.abs(value - current) }
                ?.index ?: 0
        val labels =
            options.map(NativePlaybackFormatting::formatSubtitlePercentLabel).toTypedArray()
        val dialog =
            AlertDialog.Builder(host.activity)
                .setTitle(title)
                .setSingleChoiceItems(labels, currentIndex) { pickerDialog, which ->
                    val selected = options[which]
                    pickerDialog.dismiss()
                    onSelected(selected)
                    persistGlobalSubtitleStyle()
                    host.showToast(
                        "$title 已设为${NativePlaybackFormatting.formatSubtitlePercentLabel(selected)}"
                    )
                }
                .setNegativeButton("取消", null)
                .create()
        host.settings.showTransientDialog(dialog, ControllerFocusTarget.SETTINGS)
    }

    private fun applyDualSubtitleLayoutSettings() {
        host.subtitles.dualSubtitleController.configureLayout(
            primaryPositionPercent = primarySubtitlePosition,
            secondaryPositionPercent = secondarySubtitlePosition,
            secondaryScalePercent = secondarySubtitleScale,
        )
        applySubtitleStyle()
    }

    private fun persistGlobalSubtitleStyle() {
        val dispatched =
            MainActivity.saveNativePlaybackSubtitleStyle(
                subtitleScale = subtitleScale,
                primarySubtitlePosition = primarySubtitlePosition,
                secondarySubtitlePosition = secondarySubtitlePosition,
                secondarySubtitleScale = secondarySubtitleScale,
            )
        if (!dispatched) {
            NativePlaybackFormatting.logPlayback("native.subtitle-style.persist-dispatch-failed")
        }
    }

    fun applySubtitleStyle() {
        val subtitleView = host.playerView.subtitleView ?: return
        val style =
            NativeSubtitleStylePolicy.resolve(
                rawScale = subtitleScale,
                isTelevision = host.isTelevisionDevice,
            )
        subtitleView.setViewType(SubtitleView.VIEW_TYPE_CANVAS)
        subtitleView.setBottomPaddingFraction(
            (1.0 - (primarySubtitlePosition / 100.0)).toFloat().coerceIn(0.05f, 0.5f)
        )

        val captioningManager =
            host.activity.getSystemService(Activity.CAPTIONING_SERVICE) as? CaptioningManager
        if (captioningManager?.isEnabled == true) {
            subtitleView.setApplyEmbeddedStyles(host.subtitles.dualSubtitleController.isEnabled)
            subtitleView.setApplyEmbeddedFontSizes(host.subtitles.dualSubtitleController.isEnabled)
            subtitleView.setUserDefaultStyle()
            subtitleView.setUserDefaultTextSize()
            return
        }

        subtitleView.setApplyEmbeddedStyles(true)
        subtitleView.setApplyEmbeddedFontSizes(host.subtitles.dualSubtitleController.isEnabled)
        subtitleView.setStyle(
            CaptionStyleCompat(
                Color.WHITE,
                Color.TRANSPARENT,
                Color.TRANSPARENT,
                CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                Color.BLACK,
                Typeface.create("sans-serif-medium", Typeface.NORMAL),
            )
        )
        subtitleView.setFractionalTextSize(style.textSizeFraction)
    }
}
