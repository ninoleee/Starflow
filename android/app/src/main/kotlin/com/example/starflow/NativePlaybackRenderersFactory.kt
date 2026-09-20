package com.example.starflow

import android.content.Context
import android.media.AudioTrack
import android.os.Looper
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.Renderer
import androidx.media3.common.Format
import androidx.media3.common.C
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.Util
import androidx.media3.exoplayer.audio.AudioOffloadSupport
import androidx.media3.exoplayer.audio.AudioCapabilities
import androidx.media3.exoplayer.audio.AudioOutputProvider
import androidx.media3.exoplayer.audio.AudioTrackAudioOutputProvider
import androidx.media3.exoplayer.audio.ForwardingAudioSink
import androidx.media3.exoplayer.audio.ForwardingAudioOutputProvider
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.text.TextOutput
import java.util.ArrayList

class NativePlaybackRenderersFactory(
    context: Context,
    private val requiresDecodedOutput: (String?) -> Boolean,
    private val dualSubtitleController: NativeDualSubtitleController,
    private val onAudioSinkConfigured: (Format) -> Unit = {},
) : DefaultRenderersFactory(context) {
    init {
        setExtensionRendererMode(EXTENSION_RENDERER_MODE_ON)
    }

    override fun buildAudioSink(
        context: Context,
        enableFloatOutput: Boolean,
        enableAudioOutputPlaybackParams: Boolean,
    ): AudioSink? {
        val outputProvider = AudioTrackAudioOutputProvider.Builder(context).build()
        val sink = DefaultAudioSink.Builder(context)
            .setEnableFloatOutput(enableFloatOutput)
            .setEnableAudioOutputPlaybackParameters(enableAudioOutputPlaybackParams)
            .setAudioOutputProvider(NativePlaybackAudioOutputProvider(outputProvider))
            .build()
        return NativePlaybackAudioSink(
            sink, requiresDecodedOutput, onAudioSinkConfigured,
            audioCapabilities = { outputProvider.audioCapabilities },
        )
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

internal class NativePlaybackAudioOutputProvider(
    provider: AudioOutputProvider,
    private val getMinBufferSize: (Int, Int, Int) -> Int = AudioTrack::getMinBufferSize,
) : ForwardingAudioOutputProvider(provider) {
    override fun getOutputConfig(formatConfig: AudioOutputProvider.FormatConfig): AudioOutputProvider.OutputConfig {
        val format = formatConfig.format
        if (format.sampleMimeType != MimeTypes.AUDIO_RAW ||
            !Util.isEncodingHighResolutionPcm(format.pcmEncoding) ||
            formatConfig.preferredBufferSize != C.LENGTH_UNSET) {
            return super.getOutputConfig(formatConfig)
        }

        // Media3 1.10.1 asserts on ERROR_BAD_VALUE before its buffer-size provider runs.
        // Obtain the real output configuration without automatic sizing, then use the
        // same default sizing policy with a typed rejection (no stack/message matching).
        val output = super.getOutputConfig(formatConfig.buildUpon().setPreferredBufferSize(1).build())
        val minimum = getMinBufferSize(output.sampleRate, output.channelMask, output.encoding)
        if (minimum == AudioTrack.ERROR_BAD_VALUE) {
            throw AudioOutputProvider.ConfigurationException(
                "AudioTrack.getMinBufferSize returned ERROR_BAD_VALUE: " +
                    "sampleRate=${output.sampleRate}, channelMask=${output.channelMask}, encoding=${output.encoding}",
            )
        }
        val bufferSize = DefaultAudioSink.AudioTrackBufferSizeProvider.DEFAULT.getBufferSizeInBytes(
            minimum,
            output.encoding,
            DefaultAudioSink.OUTPUT_MODE_PCM,
            Util.getPcmFrameSize(output.encoding, format.channelCount),
            output.sampleRate,
            format.bitrate,
            if (output.usePlaybackParameters) DefaultAudioSink.MAX_PLAYBACK_SPEED.toDouble()
            else DefaultAudioSink.DEFAULT_PLAYBACK_SPEED.toDouble(),
        )
        return output.buildUpon().setBufferSize(bufferSize).build()
    }
}

internal class NativePlaybackAudioSink(
    sink: AudioSink,
    private val requiresDecodedOutput: (String?) -> Boolean,
    private val onConfigured: (Format) -> Unit = {},
    private val audioCapabilities: (() -> AudioCapabilities?)? = null,
) : ForwardingAudioSink(sink) {
    // DefaultAudioSink only exposes capabilities for an unwrapped AudioTrack provider.
    override fun getAudioCapabilities(): AudioCapabilities? =
        audioCapabilities?.invoke() ?: super.getAudioCapabilities()

    override fun configure(inputFormat: Format, specifiedBufferSize: Int, outputChannels: IntArray?) {
        // Capture even failed configurations; initialization callbacks do not exist on failure.
        onConfigured(inputFormat)
        super.configure(inputFormat, specifiedBufferSize, outputChannels)
    }

    private fun blocks(format: Format): Boolean =
        format.sampleMimeType != MimeTypes.AUDIO_RAW && requiresDecodedOutput(format.sampleMimeType)

    override fun supportsFormat(format: Format): Boolean =
        getFormatSupport(format) != AudioSink.SINK_FORMAT_UNSUPPORTED

    override fun getFormatSupport(format: Format): Int =
        if (blocks(format)) AudioSink.SINK_FORMAT_UNSUPPORTED else super.getFormatSupport(format)

    override fun getFormatOffloadSupport(format: Format): AudioOffloadSupport =
        if (blocks(format)) AudioOffloadSupport.DEFAULT_UNSUPPORTED else super.getFormatOffloadSupport(format)
}
