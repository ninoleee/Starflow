package com.example.starflow

import android.content.Context
import android.os.Looper
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.Renderer
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.exoplayer.audio.AudioOffloadSupport
import androidx.media3.exoplayer.audio.ForwardingAudioSink
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.text.TextOutput
import java.util.ArrayList

class NativePlaybackRenderersFactory(
    context: Context,
    private val requiresDecodedOutput: (String?) -> Boolean,
    private val dualSubtitleController: NativeDualSubtitleController,
) : DefaultRenderersFactory(context) {
    init {
        setExtensionRendererMode(EXTENSION_RENDERER_MODE_ON)
    }

    override fun buildAudioSink(
        context: Context,
        enableFloatOutput: Boolean,
        enableAudioOutputPlaybackParams: Boolean,
    ): AudioSink? {
        val sink = DefaultAudioSink.Builder(context)
            .setEnableFloatOutput(enableFloatOutput)
            .setEnableAudioOutputPlaybackParameters(enableAudioOutputPlaybackParams)
            .build()
        return NativePlaybackAudioSink(sink, requiresDecodedOutput)
    }

    override fun buildTextRenderers(
        context: Context,
        output: TextOutput,
        outputLooper: Looper,
        extensionRendererMode: Int,
        out: ArrayList<Renderer>,
    ) {
        dualSubtitleController.buildTextRenderers(
            output = output,
            outputLooper = outputLooper,
            out = out,
        )
    }
}

internal class NativePlaybackAudioSink(
    sink: AudioSink,
    private val requiresDecodedOutput: (String?) -> Boolean,
) : ForwardingAudioSink(sink) {
    private fun blocks(format: Format): Boolean =
        format.sampleMimeType != MimeTypes.AUDIO_RAW && requiresDecodedOutput(format.sampleMimeType)

    override fun supportsFormat(format: Format): Boolean =
        getFormatSupport(format) != AudioSink.SINK_FORMAT_UNSUPPORTED

    override fun getFormatSupport(format: Format): Int =
        if (blocks(format)) AudioSink.SINK_FORMAT_UNSUPPORTED else super.getFormatSupport(format)

    override fun getFormatOffloadSupport(format: Format): AudioOffloadSupport =
        if (blocks(format)) AudioOffloadSupport.DEFAULT_UNSUPPORTED else super.getFormatOffloadSupport(format)
}
