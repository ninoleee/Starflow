package com.example.starflow

import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.AudioOffloadSupport
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackAudioSinkTest {
    @Test fun blocksOnlyRequestedCompressedFormatAndForwardsPcmCapabilities() {
        val delegate = mock(AudioSink::class.java)
        val sink = NativePlaybackAudioSink(delegate) { it == MimeTypes.AUDIO_E_AC3 || it == MimeTypes.AUDIO_RAW }
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
}
