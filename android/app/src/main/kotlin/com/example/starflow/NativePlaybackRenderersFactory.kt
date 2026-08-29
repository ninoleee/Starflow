package com.example.starflow

import android.content.Context
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.audio.AudioCapabilities
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink

class NativePlaybackRenderersFactory(
    context: Context,
    private val forcePcmAudioOutput: Boolean,
    enableFfmpegAudioDecoder: Boolean,
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
}
