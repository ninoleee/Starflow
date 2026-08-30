package com.example.starflow

import android.os.Looper
import android.text.Layout
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.RelativeSizeSpan
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.text.Cue
import androidx.media3.common.text.CueGroup
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.exoplayer.ForwardingRenderer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.RendererCapabilities
import androidx.media3.exoplayer.text.TextOutput
import androidx.media3.exoplayer.text.TextRenderer

data class NativeSubtitleFormatKey(
    val id: String,
    val label: String,
    val language: String,
    val sampleMimeType: String,
    val codecs: String,
    val accessibilityChannel: Int,
) {
    companion object {
        fun from(format: Format): NativeSubtitleFormatKey = NativeSubtitleFormatKey(
            id = format.id.orEmpty(),
            label = format.label.orEmpty(),
            language = format.language.orEmpty(),
            sampleMimeType = format.sampleMimeType.orEmpty(),
            codecs = format.codecs.orEmpty(),
            accessibilityChannel = format.accessibilityChannel,
        )
    }
}

object NativeDualSubtitleTrackPolicy {
    fun isCompatibleTextSubtitle(
        sampleMimeType: String,
        codecs: String = "",
    ): Boolean {
        return listOf(sampleMimeType, codecs).none { rawType ->
            when (rawType.trim().lowercase()) {
                "application/pgs",
                "application/vobsub",
                "application/dvbsubs" -> true
                else -> false
            }
        }
    }

    fun isLikelyChinese(language: String, label: String): Boolean {
        val normalized = "${language.trim()} ${label.trim()}".lowercase()
        return listOf(
            "zh",
            "chi",
            "zho",
            "chs",
            "cht",
            "chinese",
            "中文",
            "简体",
            "簡體",
            "繁体",
            "繁體",
            "简中",
            "繁中",
        ).any(normalized::contains)
    }

    fun isLikelyEnglish(language: String, label: String): Boolean {
        val normalized = " ${language.trim()} ${label.trim()} ".lowercase()
        return listOf(" en ", " eng ", "english", "英语", "英語", "英文")
            .any(normalized::contains)
    }

    fun routesToPrimary(
        key: NativeSubtitleFormatKey,
        secondaryGroupKeys: Set<NativeSubtitleFormatKey>,
    ): Boolean = key !in secondaryGroupKeys

    fun routesToSecondary(
        key: NativeSubtitleFormatKey,
        secondaryKey: NativeSubtitleFormatKey,
    ): Boolean = key == secondaryKey
}

object NativeDualSubtitleLayoutPolicy {
    const val SECONDARY_TEXT_SCALE = 0.75f
}

class NativeDualSubtitleController {
    private val router = NativeSubtitleTrackRouter()
    private val rendererInvalidators = mutableListOf<() -> Unit>()
    private var downstreamOutput: TextOutput? = null
    private var primaryCueGroup = CueGroup.EMPTY_TIME_ZERO
    private var secondaryCueGroup = CueGroup.EMPTY_TIME_ZERO
    private var primaryPosition = 0.80f
    private var secondaryPosition = 0.90f
    private var secondaryTextScale = NativeDualSubtitleLayoutPolicy.SECONDARY_TEXT_SCALE

    var isEnabled: Boolean = false
        private set

    fun buildTextRenderers(
        output: TextOutput,
        outputLooper: Looper,
        out: ArrayList<Renderer>,
    ) {
        downstreamOutput = output
        rendererInvalidators.clear()
        val primaryRenderer = NativeRoutedTextRenderer(
            output = NativeRoleTextOutput(isPrimary = true),
            outputLooper = outputLooper,
            role = NativeSubtitleRendererRole.PRIMARY,
            router = router,
        )
        val secondaryRenderer = NativeRoutedTextRenderer(
            output = NativeRoleTextOutput(isPrimary = false),
            outputLooper = outputLooper,
            role = NativeSubtitleRendererRole.SECONDARY,
            router = router,
        )
        rendererInvalidators += primaryRenderer::invalidateCapabilities
        rendererInvalidators += secondaryRenderer::invalidateCapabilities
        out += primaryRenderer
        out += secondaryRenderer
    }

    fun enable(
        primaryKey: NativeSubtitleFormatKey,
        secondaryKey: NativeSubtitleFormatKey,
        secondaryGroupKeys: Set<NativeSubtitleFormatKey>,
    ) {
        isEnabled = true
        primaryCueGroup = CueGroup.EMPTY_TIME_ZERO
        secondaryCueGroup = CueGroup.EMPTY_TIME_ZERO
        router.enable(
            primaryKey = primaryKey,
            secondaryKey = secondaryKey,
            secondaryGroupKeys = secondaryGroupKeys,
        )
        invalidateRenderers()
        emitMergedCues()
    }

    fun configureLayout(
        primaryPositionPercent: Double,
        secondaryPositionPercent: Double,
        secondaryScalePercent: Double,
    ) {
        primaryPosition = (primaryPositionPercent / 100).toFloat().coerceIn(0.5f, 0.95f)
        secondaryPosition = (secondaryPositionPercent / 100).toFloat().coerceIn(0.5f, 0.95f)
        secondaryTextScale = (secondaryScalePercent / 100).toFloat().coerceIn(0.5f, 1.2f)
        if (isEnabled) {
            emitMergedCues()
        }
    }

    fun disable() {
        val wasEnabled = isEnabled
        isEnabled = false
        primaryCueGroup = CueGroup.EMPTY_TIME_ZERO
        secondaryCueGroup = CueGroup.EMPTY_TIME_ZERO
        router.disable()
        if (wasEnabled) {
            invalidateRenderers()
            emitCueGroup(CueGroup.EMPTY_TIME_ZERO)
        }
    }

    private fun invalidateRenderers() {
        rendererInvalidators.forEach { invalidate -> invalidate() }
    }

    private fun onPrimaryCues(cueGroup: CueGroup) {
        primaryCueGroup = cueGroup
        if (isEnabled) {
            emitMergedCues()
        } else {
            emitCueGroup(cueGroup)
        }
    }

    private fun onSecondaryCues(cueGroup: CueGroup) {
        secondaryCueGroup = cueGroup
        if (isEnabled) {
            emitMergedCues()
        }
    }

    private fun emitMergedCues() {
        if (!isEnabled) {
            emitCueGroup(primaryCueGroup)
            return
        }
        val primaryText = extractCueText(primaryCueGroup)
        val secondaryText = extractCueText(secondaryCueGroup)
        if (primaryText.isEmpty() && secondaryText.isEmpty()) {
            emitCueGroup(
                CueGroup(
                    emptyList(),
                    maxOf(
                        primaryCueGroup.presentationTimeUs,
                        secondaryCueGroup.presentationTimeUs,
                    ),
                ),
            )
            return
        }

        val cues = mutableListOf<Cue>()
        if (primaryText.isNotEmpty()) {
            cues += Cue.Builder()
                .setText(primaryText)
                .setTextAlignment(Layout.Alignment.ALIGN_CENTER)
                .setLine(primaryPosition, Cue.LINE_TYPE_FRACTION)
                .setLineAnchor(Cue.ANCHOR_TYPE_MIDDLE)
                .build()
        }
        if (secondaryText.isNotEmpty()) {
            val text = SpannableStringBuilder(secondaryText)
            text.setSpan(
                RelativeSizeSpan(secondaryTextScale),
                0,
                text.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
            cues += Cue.Builder()
                .setText(text)
                .setTextAlignment(Layout.Alignment.ALIGN_CENTER)
                .setLine(secondaryPosition, Cue.LINE_TYPE_FRACTION)
                .setLineAnchor(Cue.ANCHOR_TYPE_MIDDLE)
                .build()
        }
        emitCueGroup(
            CueGroup(
                cues,
                maxOf(
                    primaryCueGroup.presentationTimeUs,
                    secondaryCueGroup.presentationTimeUs,
                ),
            ),
        )
    }

    private fun extractCueText(cueGroup: CueGroup): String {
        return cueGroup.cues
            .asSequence()
            .mapNotNull { cue -> cue.text?.toString()?.trim()?.takeIf(String::isNotEmpty) }
            .distinct()
            .joinToString("\n")
    }

    private fun emitCueGroup(cueGroup: CueGroup) {
        downstreamOutput?.onCues(cueGroup)
    }

    private inner class NativeRoleTextOutput(
        private val isPrimary: Boolean,
    ) : TextOutput {
        override fun onCues(cueGroup: CueGroup) {
            if (isPrimary) {
                onPrimaryCues(cueGroup)
            } else {
                onSecondaryCues(cueGroup)
            }
        }
    }

}

private enum class NativeSubtitleRendererRole {
    PRIMARY,
    SECONDARY,
}

private class NativeSubtitleTrackRouter {
    @Volatile
    private var secondaryKey: NativeSubtitleFormatKey? = null

    @Volatile
    private var secondaryGroupKeys: Set<NativeSubtitleFormatKey> = emptySet()

    fun enable(
        primaryKey: NativeSubtitleFormatKey,
        secondaryKey: NativeSubtitleFormatKey,
        secondaryGroupKeys: Set<NativeSubtitleFormatKey>,
    ) {
        require(primaryKey != secondaryKey)
        this.secondaryKey = secondaryKey
        this.secondaryGroupKeys = secondaryGroupKeys
    }

    fun disable() {
        secondaryKey = null
        secondaryGroupKeys = emptySet()
    }

    fun accepts(role: NativeSubtitleRendererRole, format: Format): Boolean {
        val resolvedSecondaryKey = secondaryKey
        if (resolvedSecondaryKey == null) {
            return role == NativeSubtitleRendererRole.PRIMARY
        }
        val key = NativeSubtitleFormatKey.from(format)
        return when (role) {
            NativeSubtitleRendererRole.PRIMARY ->
                NativeDualSubtitleTrackPolicy.routesToPrimary(key, secondaryGroupKeys)
            NativeSubtitleRendererRole.SECONDARY ->
                NativeDualSubtitleTrackPolicy.routesToSecondary(key, resolvedSecondaryKey)
        }
    }
}

private class NativeRoutedTextRenderer private constructor(
    delegate: TextRenderer,
    private val role: NativeSubtitleRendererRole,
    router: NativeSubtitleTrackRouter,
) : ForwardingRenderer(delegate) {
    private val routedCapabilities = NativeRoutedTextCapabilities(
        delegate = delegate.capabilities,
        role = role,
        router = router,
    )

    constructor(
        output: TextOutput,
        outputLooper: Looper,
        role: NativeSubtitleRendererRole,
        router: NativeSubtitleTrackRouter,
    ) : this(
        delegate = TextRenderer(output, outputLooper),
        role = role,
        router = router,
    )

    override fun getName(): String = when (role) {
        NativeSubtitleRendererRole.PRIMARY -> "StarflowPrimaryTextRenderer"
        NativeSubtitleRendererRole.SECONDARY -> "StarflowSecondaryTextRenderer"
    }

    override fun getTrackType(): Int = when (role) {
        NativeSubtitleRendererRole.PRIMARY -> C.TRACK_TYPE_TEXT
        NativeSubtitleRendererRole.SECONDARY -> C.TRACK_TYPE_CUSTOM_BASE
    }

    override fun getCapabilities(): RendererCapabilities = routedCapabilities

    fun invalidateCapabilities() {
        routedCapabilities.invalidate(this)
    }
}

private class NativeRoutedTextCapabilities(
    private val delegate: RendererCapabilities,
    private val role: NativeSubtitleRendererRole,
    private val router: NativeSubtitleTrackRouter,
) : RendererCapabilities {
    @Volatile
    private var listener: RendererCapabilities.Listener? = null

    override fun getName(): String = when (role) {
        NativeSubtitleRendererRole.PRIMARY -> "StarflowPrimaryTextCapabilities"
        NativeSubtitleRendererRole.SECONDARY -> "StarflowSecondaryTextCapabilities"
    }

    override fun getTrackType(): Int = when (role) {
        NativeSubtitleRendererRole.PRIMARY -> C.TRACK_TYPE_TEXT
        NativeSubtitleRendererRole.SECONDARY -> C.TRACK_TYPE_CUSTOM_BASE
    }

    @Throws(ExoPlaybackException::class)
    override fun supportsFormat(format: Format): Int {
        return if (router.accepts(role, format)) {
            delegate.supportsFormat(format)
        } else {
            RendererCapabilities.create(C.FORMAT_UNSUPPORTED_TYPE)
        }
    }

    @Throws(ExoPlaybackException::class)
    override fun supportsMixedMimeTypeAdaptation(): Int {
        return delegate.supportsMixedMimeTypeAdaptation()
    }

    override fun setListener(listener: RendererCapabilities.Listener) {
        this.listener = listener
    }

    override fun clearListener() {
        listener = null
    }

    fun invalidate(renderer: Renderer) {
        listener?.onRendererCapabilitiesChanged(renderer)
    }
}
