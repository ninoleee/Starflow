package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.Util
import androidx.media3.exoplayer.audio.AudioSink

// One instance per player; old callbacks never update the next player's observations.
internal class NativeAudioOutputState {
    data class Snapshot(
        val sourceInput: Format? = null,
        val sinkInput: Format? = null,
        val outputEncoding: Int? = null,
        val decoderName: String = "",
        val activeOutput: AudioSink.AudioTrackConfig? = null,
    )

    private val lock = Any()
    @Volatile private var observations = Snapshot()
    private var nextGeneration = 0L
    private var activeTrackGeneration: Long? = null
    private var activeDecoderGeneration: Long? = null
    private val tracks = mutableListOf<Pair<Long, AudioSink.AudioTrackConfig>>()
    private val decoders = mutableListOf<Pair<Long, String>>()

    // Read this once when a decision depends on more than one observation.
    val snapshot: Snapshot get() = observations

    var sourceInput: Format?
        get() = observations.sourceInput
        set(value) = onSourceInputChanged(value)

    var sinkInput: Format?
        get() = observations.sinkInput
        set(value) {
            synchronized(lock) { observations = observations.copy(sinkInput = value) }
        }

    var outputEncoding: Int?
        get() = observations.outputEncoding
        set(value) {
            synchronized(lock) {
                // Compatibility assignments have no track identity to correlate with releases.
                tracks.clear()
                activeTrackGeneration = null
                observations = observations.copy(outputEncoding = value, activeOutput = null)
            }
        }

    var decoderName: String
        get() = observations.decoderName
        set(value) {
            synchronized(lock) {
                decoders.clear()
                activeDecoderGeneration = null
                if (value.isNotEmpty()) {
                    val generation = ++nextGeneration
                    decoders.add(generation to value)
                    activeDecoderGeneration = generation
                }
                observations = observations.copy(decoderName = value)
            }
        }

    fun onSourceInputChanged(format: Format?) {
        synchronized(lock) { observations = observations.copy(sourceInput = format) }
    }

    fun onSinkConfigured(format: Format) {
        // This is the attempted input, even if configure fails. The old track may still be active.
        synchronized(lock) { observations = observations.copy(sinkInput = format) }
    }

    fun onDecoderInitialized(name: String) {
        synchronized(lock) {
            val generation = ++nextGeneration
            decoders.add(generation to name)
            activeDecoderGeneration = generation
            observations = observations.copy(decoderName = name)
        }
    }

    fun onDecoderReleased(name: String) {
        synchronized(lock) {
            val index = decoders.indexOfFirst { it.second == name }
            if (index < 0) return
            if (decoders.removeAt(index).first == activeDecoderGeneration) {
                activeDecoderGeneration = null
                observations = observations.copy(decoderName = "")
            }
        }
    }

    fun onAudioTrackInitialized(config: AudioSink.AudioTrackConfig) {
        synchronized(lock) {
            val generation = ++nextGeneration
            tracks.add(generation to config)
            activeTrackGeneration = generation
            observations = observations.copy(outputEncoding = config.encoding, activeOutput = config)
        }
    }

    fun onAudioTrackReleased(config: AudioSink.AudioTrackConfig) {
        synchronized(lock) {
            // Media3 creates a fresh config for release, without a track ID. Identical configs
            // therefore require FIFO releases; a config alone cannot distinguish reordered ones.
            val index = tracks.indexOfFirst { sameConfiguration(it.second, config) }
            if (index < 0) return
            if (tracks.removeAt(index).first == activeTrackGeneration) {
                activeTrackGeneration = null
                observations = observations.copy(outputEncoding = null, activeOutput = null)
            }
        }
    }

    fun hasHighResolutionInput(): Boolean = hasHighResolutionInput(observations)

    fun isPassthrough(): Boolean {
        val current = observations
        current.outputEncoding?.takeIf { it != C.ENCODING_INVALID && it != Format.NO_VALUE }?.let {
            return !Util.isEncodingLinearPcm(it)
        }
        return current.sinkInput?.sampleMimeType?.let {
            MimeTypes.isAudio(it) && it != MimeTypes.AUDIO_RAW
        } == true
    }

    fun needsPrecisionChange(enableFloat: Boolean, desiredFloat: Boolean): Boolean {
        if (enableFloat == desiredFloat) return false
        val current = observations
        if (current.sinkInput == null) return true
        return hasHighResolutionInput(current) || current.outputEncoding == C.ENCODING_PCM_FLOAT ||
            (desiredFloat && NativeAudioDecoderPrecisionPolicy.shouldRestoreFloat(
                current.sourceInput?.sampleMimeType, current.decoderName))
    }

    private fun hasHighResolutionInput(current: Snapshot): Boolean = current.sinkInput?.let {
        it.sampleMimeType == MimeTypes.AUDIO_RAW && Util.isEncodingHighResolutionPcm(it.pcmEncoding)
    } == true

    private fun sameConfiguration(a: AudioSink.AudioTrackConfig, b: AudioSink.AudioTrackConfig): Boolean =
        a.encoding == b.encoding && a.sampleRate == b.sampleRate &&
            a.channelConfig == b.channelConfig && a.tunneling == b.tunneling &&
            a.offload == b.offload && a.bufferSize == b.bufferSize
}
