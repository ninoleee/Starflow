package com.example.starflow

import android.media.AudioTrack
import androidx.media3.common.Format
import androidx.media3.common.C
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.Util
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.AudioOffloadSupport
import androidx.media3.exoplayer.audio.AudioCapabilities
import androidx.media3.exoplayer.audio.AudioOutputProvider
import androidx.media3.exoplayer.audio.DefaultAudioSink
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackAudioSinkTest {
    @Test fun wrappedOutputProviderCapabilitiesArePreserved() {
        val delegate = mock(AudioSink::class.java)
        val capabilities = AudioCapabilities.DEFAULT_AUDIO_CAPABILITIES
        val sink = NativePlaybackAudioSink(delegate, { false }, audioCapabilities = { capabilities })
        assertSame(capabilities, sink.audioCapabilities)
        verifyNoInteractions(delegate)
    }

    @Test fun captureConfigurationBeforeSinkFailure() {
        val delegate = mock(AudioSink::class.java)
        val format = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_RAW)
            .setPcmEncoding(androidx.media3.common.C.ENCODING_PCM_FLOAT).build()
        val state = NativeAudioOutputState()
        val sink = NativePlaybackAudioSink(delegate, { false }, { state.sinkInput = it })
        val cause = AudioOutputProvider.ConfigurationException("unsupported")
        val failure = AudioSink.ConfigurationException(cause, format)
        doThrow(failure)
            .`when`(delegate).configure(format, 0, null)
        assertSame(failure, assertThrows(AudioSink.ConfigurationException::class.java) {
            sink.configure(format, 0, null)
        })
        assertSame(cause, failure.cause)
        assertSame(format, failure.format)
        assertSame(format, state.sinkInput)
    }

    @Test fun rejectedHighPrecisionBufferConfigurationIsTyped() {
        for (encoding in listOf(C.ENCODING_PCM_24BIT, C.ENCODING_PCM_32BIT, C.ENCODING_PCM_FLOAT)) {
            val delegate = mock(AudioOutputProvider::class.java)
            val format = highPrecisionFormat(encoding)
            `when`(delegate.getOutputConfig(any())).thenAnswer { invocation ->
                val config = invocation.getArgument<AudioOutputProvider.FormatConfig>(0)
                assertSame(format, config.format)
                assertEquals(1, config.preferredBufferSize)
                outputConfig(encoding)
            }
            var queries = 0
            val provider = NativePlaybackAudioOutputProvider(delegate) { sampleRate, channelMask, actualEncoding ->
                queries++
                assertEquals(96000, sampleRate)
                assertEquals(12, channelMask)
                assertEquals(encoding, actualEncoding)
                AudioTrack.ERROR_BAD_VALUE
            }
            assertThrows(AudioOutputProvider.ConfigurationException::class.java) {
                provider.getOutputConfig(AudioOutputProvider.FormatConfig.Builder(format).build())
            }
            assertEquals(1, queries)
        }
    }

    @Test fun acceptedBufferConfigurationUsesMedia3DefaultSizing() {
        for (usePlaybackParameters in listOf(false, true)) {
            val delegate = mock(AudioOutputProvider::class.java)
            val format = highPrecisionFormat(C.ENCODING_PCM_FLOAT)
            val output = outputConfig(format.pcmEncoding).buildUpon()
                .setUsePlaybackParameters(usePlaybackParameters).build()
            `when`(delegate.getOutputConfig(any())).thenReturn(output)
            val provider = NativePlaybackAudioOutputProvider(delegate) { _, _, _ -> 4096 }

            val actual = provider.getOutputConfig(AudioOutputProvider.FormatConfig.Builder(format).build())
            val expectedSize = DefaultAudioSink.AudioTrackBufferSizeProvider.DEFAULT.getBufferSizeInBytes(
                4096, format.pcmEncoding, DefaultAudioSink.OUTPUT_MODE_PCM,
                Util.getPcmFrameSize(format.pcmEncoding, format.channelCount),
                format.sampleRate, format.bitrate,
                if (usePlaybackParameters) DefaultAudioSink.MAX_PLAYBACK_SPEED.toDouble() else 1.0,
            )
            assertEquals(output.buildUpon().setBufferSize(expectedSize).build(), actual)
        }
    }

    @Test fun ordinaryPcmPassthroughAndExplicitBufferSizeKeepOriginalProviderPath() {
        val formats = listOf(
            highPrecisionFormat(C.ENCODING_PCM_16BIT),
            Format.Builder().setSampleMimeType(MimeTypes.AUDIO_DTS).build(),
            highPrecisionFormat(C.ENCODING_PCM_FLOAT),
        )
        for ((index, format) in formats.withIndex()) {
            val delegate = mock(AudioOutputProvider::class.java)
            val config = AudioOutputProvider.FormatConfig.Builder(format)
                .setPreferredBufferSize(if (index == 2) 4096 else C.LENGTH_UNSET).build()
            val output = outputConfig(C.ENCODING_PCM_16BIT)
            `when`(delegate.getOutputConfig(config)).thenReturn(output)
            val provider = NativePlaybackAudioOutputProvider(delegate) { _, _, _ ->
                fail("No buffer query expected")
                AudioTrack.ERROR_BAD_VALUE
            }
            assertSame(output, provider.getOutputConfig(config))
            verify(delegate).getOutputConfig(config)
        }
    }

    @Test fun unrelatedProviderAndPlatformRuntimeFailuresRemainUnchanged() {
        val failures = listOf(
            IllegalStateException("getMinBufferSize ERROR_BAD_VALUE"),
            IllegalArgumentException(),
            NullPointerException(),
        )
        for (failure in failures) {
            val delegate = mock(AudioOutputProvider::class.java)
            val config = AudioOutputProvider.FormatConfig.Builder(highPrecisionFormat(C.ENCODING_PCM_FLOAT)).build()
            doAnswer { throw failure }.`when`(delegate).getOutputConfig(any())
            val provider = NativePlaybackAudioOutputProvider(delegate) { _, _, _ -> throw failure }
            assertSame(failure, assertThrows(RuntimeException::class.java) {
                provider.getOutputConfig(config)
            })
            doReturn(outputConfig(C.ENCODING_PCM_FLOAT)).`when`(delegate).getOutputConfig(any())
            assertSame(failure, assertThrows(RuntimeException::class.java) {
                provider.getOutputConfig(config)
            })
        }
    }

    @Test fun originalProviderConfigurationExceptionIsPassedThrough() {
        val delegate = mock(AudioOutputProvider::class.java)
        val failure = AudioOutputProvider.ConfigurationException("unsupported")
        doThrow(failure).`when`(delegate).getOutputConfig(any())
        val provider = NativePlaybackAudioOutputProvider(delegate) { _, _, _ -> 4096 }
        assertSame(failure, assertThrows(AudioOutputProvider.ConfigurationException::class.java) {
            provider.getOutputConfig(AudioOutputProvider.FormatConfig.Builder(highPrecisionFormat(C.ENCODING_PCM_FLOAT)).build())
        })
    }

    @Test fun configurationObserverFailureIsNotWrappedOrForwarded() {
        val delegate = mock(AudioSink::class.java)
        val failure = IllegalStateException()
        val sink = NativePlaybackAudioSink(delegate, { false }, { throw failure })

        assertSame(failure, assertThrows(IllegalStateException::class.java) {
            sink.configure(highPrecisionFormat(C.ENCODING_PCM_FLOAT), 0, null)
        })
        verifyNoInteractions(delegate)
    }

    @Test fun blocksOnlyRequestedCompressedFormatAndForwardsPcmCapabilities() {
        val delegate = mock(AudioSink::class.java)
        val sink = NativePlaybackAudioSink(delegate, { it == MimeTypes.AUDIO_E_AC3 || it == MimeTypes.AUDIO_RAW })
        val compressed = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_E_AC3).build()
        assertFalse(sink.supportsFormat(compressed))
        assertSame(AudioOffloadSupport.DEFAULT_UNSUPPORTED, sink.getFormatOffloadSupport(compressed))
        verifyNoInteractions(delegate)
        for (mime in listOf(MimeTypes.AUDIO_RAW, MimeTypes.AUDIO_AC3)) {
            val format = Format.Builder().setSampleMimeType(mime).build()
            `when`(delegate.getFormatSupport(format)).thenReturn(AudioSink.SINK_FORMAT_SUPPORTED_DIRECTLY)
            assertTrue(sink.supportsFormat(format))
            verify(delegate).getFormatSupport(format)
        }
    }

    private fun highPrecisionFormat(encoding: Int): Format = Format.Builder()
        .setSampleMimeType(MimeTypes.AUDIO_RAW)
        .setPcmEncoding(encoding)
        .setSampleRate(96000)
        .setChannelCount(2)
        .build()

    private fun outputConfig(encoding: Int): AudioOutputProvider.OutputConfig = AudioOutputProvider.OutputConfig.Builder()
        .setSampleRate(96000)
        .setChannelMask(12)
        .setEncoding(encoding)
        .setBufferSize(1)
        .build()
}
