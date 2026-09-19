package com.example.starflow

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.view.ViewGroup
import android.view.accessibility.CaptioningManager
import android.widget.FrameLayout
import androidx.media3.common.text.CueGroup
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

    private var videoSubtitleParent: ViewGroup? = null
    private var usesBitmapCoordinates = false

    fun onCues(cueGroup: CueGroup) {
        // Empty groups clear the view without changing its coordinate space between lines.
        if (cueGroup.cues.isEmpty()) return
        usesBitmapCoordinates = cueGroup.cues.any { it.bitmap != null }
        updateSubtitleContainer()
    }

    private fun updateSubtitleContainer() {
        val subtitleView = host.playerView.subtitleView ?: return
        val overlay = host.playerView.overlayFrameLayout ?: return
        val currentParent = subtitleView.parent as? ViewGroup ?: return
        if (videoSubtitleParent == null && currentParent !== overlay) {
            videoSubtitleParent = currentParent
        }
        // Bitmap coordinates describe the video plane, not the full window/letterbox bars.
        val targetParent = if (usesBitmapCoordinates) videoSubtitleParent ?: return else overlay
        if (currentParent === targetParent) return
        currentParent.removeView(subtitleView)
        val params = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        if (targetParent === overlay) {
            overlay.addView(subtitleView, 0, params)
        } else {
            // Above the video/shutter, while PlayerView controls remain outside this frame.
            targetParent.addView(subtitleView, params)
        }
    }

    fun openSubtitleScalePicker() {
        openSubtitleNumberPicker(
            title = host.activity.getString(R.string.native_subtitle_scale),
            range = 20..78,
            current = subtitleScale,
            format = NativePlaybackFormatting::formatSubtitleScaleLabel,
        ) { selected ->
            subtitleScale = selected
            applySubtitleStyle()
        }
    }

    fun openPrimarySubtitlePositionPicker() {
        openSubtitleNumberPicker(
            title = "主字幕位置",
            range = 50..100,
            current = primarySubtitlePosition,
        ) { selected ->
            primarySubtitlePosition = selected
            applyDualSubtitleLayoutSettings()
        }
    }

    fun openSecondarySubtitlePositionPicker() {
        openSubtitleNumberPicker(
            title = "副字幕位置",
            range = 50..100,
            current = secondarySubtitlePosition,
        ) { selected ->
            secondarySubtitlePosition = selected
            applyDualSubtitleLayoutSettings()
        }
    }

    fun openSecondarySubtitleScalePicker() {
        openSubtitleNumberPicker(
            title = "副字幕大小",
            range = 50..120,
            current = secondarySubtitleScale,
        ) { selected ->
            secondarySubtitleScale = selected
            applyDualSubtitleLayoutSettings()
        }
    }

    private fun openSubtitleNumberPicker(
        title: String,
        range: IntRange,
        current: Double,
        format: (Double) -> String = NativePlaybackFormatting::formatSubtitlePercentLabel,
        onSelected: (Double) -> Unit,
    ) {
        val dialog = NativePlaybackNumberPicker.create(
            activity = host.activity,
            title = title,
            current = current,
            range = range,
            format = format,
        ) { selected ->
            onSelected(selected)
            persistGlobalSubtitleStyle()
        }
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
        updateSubtitleContainer()
        val style =
            NativeSubtitleStylePolicy.resolve(
                rawScale = subtitleScale,
                isTelevision = host.isTelevisionDevice,
            )
        subtitleView.setViewType(SubtitleView.VIEW_TYPE_CANVAS)
        subtitleView.setBottomPaddingFraction(
            NativeSubtitlePositionPolicy.bottomPaddingFraction(primarySubtitlePosition)
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
