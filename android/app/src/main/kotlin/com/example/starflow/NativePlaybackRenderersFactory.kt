package com.example.starflow

import android.content.Context
import android.os.Looper
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.audio.AudioCapabilities
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.text.TextOutput
import java.util.ArrayList

class NativePlaybackRenderersFactory(
    context: Context,
    private val forcePcmAudioOutput: Boolean,
    enableFfmpegAudioDecoder: Boolean,
    private val dualSubtitleController: NativeDualSubtitleController,
) : DefaultRenderersFactory(context) {
    init {
        if (enableFfmpegAudioDecoder) {
            setExtensionRendererMode(EXTENSION_RENDERER_MODE_ON)
        }
    }

    @Suppress("DEPRECATION")
    override fun buildAudioSink(
        context: Context,
        enableFloatOutput: Boolean,
        enableAudioOutputPlaybackParams: Boolean,
    ): AudioSink? {
        if (!forcePcmAudioOutput) {
            return super.buildAudioSink(
                context,
                enableFloatOutput,
                enableAudioOutputPlaybackParams,
            )
        }
        return DefaultAudioSink.Builder()
            .setAudioCapabilities(AudioCapabilities.DEFAULT_AUDIO_CAPABILITIES)
            .setEnableFloatOutput(enableFloatOutput)
            .setEnableAudioOutputPlaybackParameters(enableAudioOutputPlaybackParams)
            .build()
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
