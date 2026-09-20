package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.audio.AudioProcessor.AudioFormat
import androidx.media3.exoplayer.audio.ToFloatPcmAudioProcessor
import androidx.media3.common.audio.ToInt16PcmAudioProcessor
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.*
import org.junit.Test

class NativePcmPrecisionTest {
    @Test fun modeSpeedPitchAndFallbackChooseOutputPrecision() {
        for (mode in NativeAudioOutputMode.entries) {
            assertEquals(mode != NativeAudioOutputMode.PCM_COMPATIBILITY,
                NativePlaybackAudioPolicy.useHighPrecisionPcm(mode, PlaybackParameters.DEFAULT, false))
            assertFalse(NativePlaybackAudioPolicy.useHighPrecisionPcm(mode, PlaybackParameters(1.5f), false))
            assertFalse(NativePlaybackAudioPolicy.useHighPrecisionPcm(mode, PlaybackParameters(1f, 0.9f), false))
            assertFalse(NativePlaybackAudioPolicy.useHighPrecisionPcm(mode, PlaybackParameters.DEFAULT, true))
        }
    }

    @Test fun media3FloatConversionRetains24BitSampleValuesIncludingLowestBit() {
        val values = listOf(0, 1, -1, 16, -16, 0x123456, 0x7FFFFF, -0x800000)
        val input = ByteBuffer.allocateDirect(values.size * 3).order(ByteOrder.nativeOrder())
        values.forEach { input.put(it.toByte()).put((it shr 8).toByte()).put((it shr 16).toByte()) }
        input.flip()
        val processor = ToFloatPcmAudioProcessor()
        assertEquals(C.ENCODING_PCM_FLOAT, processor.configure(AudioFormat(48000, 2, C.ENCODING_PCM_24BIT)).encoding)
        processor.flush()
        processor.queueInput(input)
        val output = processor.output.order(ByteOrder.nativeOrder())
        values.forEach { assertEquals(it.toFloat() / 8388608f, output.float, 0f) }
        assertFalse(output.hasRemaining())
        processor.reset()
    }

    @Test fun compatibilityUsesMedia3IntegerConversion() {
        val processor = ToInt16PcmAudioProcessor()
        assertEquals(C.ENCODING_PCM_16BIT, processor.configure(AudioFormat(48000, 2, C.ENCODING_PCM_24BIT)).encoding)
        processor.flush()
        val input = ByteBuffer.allocateDirect(6).put(byteArrayOf(1, 0x34, 0x12, -1, -1, -1))
        input.flip()
        processor.queueInput(input)
        val output = processor.output.order(ByteOrder.nativeOrder())
        assertEquals(0x1234.toShort(), output.short)
        assertEquals((-1).toShort(), output.short)
        processor.reset()
    }
}
