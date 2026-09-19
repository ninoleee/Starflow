package com.example.starflow

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.text.CueGroup
import androidx.media3.common.text.Cue
import androidx.media3.decoder.DecoderInputBuffer
import androidx.media3.exoplayer.FormatHolder
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.RendererConfiguration
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.SampleStream
import androidx.media3.exoplayer.text.TextOutput
import androidx.media3.exoplayer.text.TextRenderer
import androidx.media3.extractor.text.CueDecoder
import androidx.media3.extractor.text.CuesWithTiming
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class NativeSubtitleOutputTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()
    private val jobs = mutableListOf<Runnable>()
    private val delivered = mutableListOf<CueGroup>()
    private val output = NativeSubtitleOutput(object : TextOutput {
        override fun onCues(cueGroup: CueGroup) { delivered += cueGroup }
    }) { jobs += it }

    @Test fun blockedUiOnlyReceivesLatestStateIncludingClear() {
        repeat(100) { output.onCues(CueGroup(emptyList(), it.toLong())) }
        assertEquals(1, jobs.size)
        jobs.removeAt(0).run()
        assertEquals(listOf(99L), delivered.map { it.presentationTimeUs })
    }

    @Test fun batchNeverPostsIntermediateCues() {
        output.beginBatch()
        repeat(10) { output.onCues(CueGroup(emptyList(), it.toLong())) }
        assertTrue(jobs.isEmpty())
        output.endBatch()
        jobs.removeAt(0).run()
        assertEquals(listOf(9L), delivered.map { it.presentationTimeUs })
    }

    @Test fun seekAndReleaseInvalidateQueuedCues() {
        output.onCues(CueGroup(emptyList(), 100L))
        output.invalidate()
        jobs.removeAt(0).run()
        assertTrue(delivered.isEmpty())
        output.onCues(CueGroup(emptyList(), 200L))
        output.close()
        jobs.removeAt(0).run()
        assertTrue(delivered.isEmpty())
    }

    @Test fun pendingUiTaskDuringBatchIsRescheduledAtBatchEnd() {
        output.onCues(CueGroup(emptyList(), 100L))
        output.beginBatch()
        jobs.removeAt(0).run()
        assertTrue(delivered.isEmpty())
        output.onCues(CueGroup(emptyList(), 200L))
        output.endBatch()
        jobs.removeAt(0).run()
        assertEquals(200L, delivered.single().presentationTimeUs)
    }

    private fun renderer(delegate: Renderer, pgs: Boolean = true): NativeSubtitleRenderer {
        return NativeSubtitleRenderer(delegate, output).also {
            it.enable(RendererConfiguration.DEFAULT, arrayOf(Format.Builder()
                .setSampleMimeType(MimeTypes.APPLICATION_MEDIA3_CUES)
                .setCodecs(if (pgs) MimeTypes.APPLICATION_PGS else MimeTypes.TEXT_VTT).build()),
                mock(SampleStream::class.java), 0L, false, false, 0L, 0L,
                MediaSource.MediaPeriodId("test"))
        }
    }

    @Test fun pgsBacklogIsDrainedWithoutReplayingEachOldCueOnUi() {
        val delegate = mock(Renderer::class.java)
        var time = 0L
        `when`(delegate.readingPositionUs).thenAnswer { time }
        doAnswer {
            time += 1_000_000L
            if (time <= 5_000_000L) output.onCues(CueGroup(emptyList(), time))
            null
        }.`when`(delegate).render(5_000_000L, 0L)
        renderer(delegate).render(5_000_000L, 0L)
        verify(delegate, times(6)).render(5_000_000L, 0L)
        jobs.single().run()
        assertEquals(listOf(5_000_000L), delivered.map { it.presentationTimeUs })
    }

    @Test fun catchUpIsBoundedAndDoesNotSpinOnEmptyStream() {
        val delegate = mock(Renderer::class.java)
        var time = 0L
        `when`(delegate.readingPositionUs).thenAnswer { ++time }
        renderer(delegate).render(1_000_000L, 0L)
        verify(delegate, times(32)).render(1_000_000L, 0L)
        clearInvocations(delegate)
        `when`(delegate.readingPositionUs).thenReturn(1L)
        renderer(delegate).render(1_000_000L, 0L)
        verify(delegate, times(1)).render(1_000_000L, 0L)
    }

    @Test fun ordinaryTextKeepsOneReadPerRenderAndEndOfStreamStopsCatchUp() {
        val delegate = mock(Renderer::class.java)
        `when`(delegate.readingPositionUs).thenReturn(0L, 1L)
        renderer(delegate, pgs = false).render(1_000_000L, 0L)
        verify(delegate, times(1)).render(1_000_000L, 0L)
        clearInvocations(delegate)
        `when`(delegate.readingPositionUs).thenReturn(C.TIME_END_OF_SOURCE)
        renderer(delegate).render(1_000_000L, 0L)
        verify(delegate, times(1)).render(1_000_000L, 0L)
    }

    @Test fun boundedCatchUpRetainsLastCueUntilNextBatchConfirmsNoMoreData() {
        val delegate = mock(Renderer::class.java)
        var time = 0L
        `when`(delegate.readingPositionUs).thenAnswer { time }
        doAnswer {
            if (time < 32L) {
                time++
                output.onCues(CueGroup(emptyList(), time))
            }
            null
        }.`when`(delegate).render(100L, 0L)
        val renderer = renderer(delegate)
        renderer.render(100L, 0L)
        assertTrue(jobs.isEmpty())
        renderer.render(100L, 0L)
        jobs.single().run()
        assertEquals(listOf(32L), delivered.map { it.presentationTimeUs })
    }

    @Test fun equalTimestampUpdatesAreDrainedUntilNoMoreOutput() {
        val delegate = mock(Renderer::class.java)
        `when`(delegate.readingPositionUs).thenReturn(1L)
        var updates = 0
        doAnswer {
            if (++updates <= 4) output.onCues(CueGroup(emptyList(), 1L))
            null
        }.`when`(delegate).render(100L, 0L)
        renderer(delegate).render(100L, 0L)
        verify(delegate, times(5)).render(100L, 0L)
        jobs.single().run()
        assertEquals(1, delivered.size)
    }

    @Test fun realMedia3RendererCatchesUpToCurrentCueInOneBatch() {
        mockConstruction(CueDecoder::class.java) { decoder, _ ->
            `when`(decoder.decode(anyLong(), any(ByteArray::class.java), anyInt(), anyInt()))
                .thenAnswer {
                    val time = it.getArgument<Long>(0)
                    CuesWithTiming(listOf(Cue.Builder().setText("cue-$time").build()), time, C.TIME_UNSET)
                }
        }.use {
            val format = Format.Builder().setSampleMimeType(MimeTypes.APPLICATION_MEDIA3_CUES)
                .setCodecs(MimeTypes.APPLICATION_PGS)
                .setCueReplacementBehavior(Format.CUE_REPLACEMENT_BEHAVIOR_REPLACE).build()
            var index = 0
            val stream = object : SampleStream {
                override fun isReady() = true
                override fun maybeThrowError() = Unit
                override fun skipData(positionUs: Long) = 0
                override fun readData(holder: FormatHolder, buffer: DecoderInputBuffer, flags: Int): Int {
                    if (index >= 6) return C.RESULT_NOTHING_READ
                    buffer.timeUs = ++index * 1_000_000L
                    buffer.ensureSpaceForWrite(1)
                    buffer.data!!.put(0.toByte())
                    return C.RESULT_BUFFER_READ
                }
            }
            val renderer = NativeSubtitleRenderer(TextRenderer(output, null), output)
            renderer.enable(RendererConfiguration.DEFAULT, arrayOf(format), stream,
                0L, false, false, 0L, 0L, MediaSource.MediaPeriodId("test"))
            renderer.start()
            renderer.render(5_000_000L, 0L)
            jobs.single().run()
            assertEquals(6, index)
            assertEquals("cue-5000000", delivered.single().cues.single().text.toString())
            renderer.stop()
            renderer.disable()
            renderer.release()
        }
    }

    @Test fun futureSampleGateRetainsOnlyOneLookaheadAndHonorsOffsetAndSeek() {
        var reads = 0
        val source = object : SampleStream {
            override fun isReady() = true
            override fun maybeThrowError() = Unit
            override fun skipData(positionUs: Long) = 0
            override fun readData(holder: FormatHolder, buffer: DecoderInputBuffer, flags: Int): Int {
                buffer.timeUs = (reads + 1) * 1_000_000L
                if (flags and SampleStream.FLAG_PEEK == 0) reads++
                return C.RESULT_BUFFER_READ
            }
        }
        val stream = BitmapSubtitleSampleStream(source, 5_000_000L)
        val holder = FormatHolder()
        val buffer = DecoderInputBuffer(DecoderInputBuffer.BUFFER_REPLACEMENT_MODE_NORMAL)
        stream.positionUs = 5_000_000L
        assertEquals(C.RESULT_BUFFER_READ, stream.readData(holder, buffer, SampleStream.FLAG_PEEK))
        assertEquals(0, reads)
        repeat(200) { stream.readData(holder, buffer, 0) }
        assertEquals(1, reads)
        stream.positionUs = 6_000_000L
        repeat(200) { stream.readData(holder, buffer, 0) }
        assertEquals(2, reads)
        stream.reset(0)
        stream.readData(holder, buffer, 0)
        assertEquals(3, reads)
    }

    @Test fun disablingBitmapRendererClearsResolverThroughPublicReset() {
        val delegate = mock(Renderer::class.java)
        val renderer = renderer(delegate)
        renderer.render(500L, 0L)
        renderer.disable()
        val ordered = inOrder(delegate)
        ordered.verify(delegate).resetPosition(500L, false)
        ordered.verify(delegate).disable()
        assertNull(renderer.stream)
    }

    @Test fun realRendererKeepsFutureQueueBoundedWhileClockShowsAndClearsCues() {
        mockConstruction(CueDecoder::class.java) { decoder, _ ->
            `when`(decoder.decode(anyLong(), any(ByteArray::class.java), anyInt(), anyInt()))
                .thenAnswer {
                    CuesWithTiming(listOf(Cue.Builder().setText("bitmap").build()),
                        it.getArgument<Long>(0), 500_000L)
                }
        }.use {
            val format = Format.Builder().setSampleMimeType(MimeTypes.APPLICATION_MEDIA3_CUES)
                .setCodecs(MimeTypes.APPLICATION_PGS)
                .setCueReplacementBehavior(Format.CUE_REPLACEMENT_BEHAVIOR_REPLACE).build()
            var reads = 0
            val stream = object : SampleStream {
                override fun isReady() = true
                override fun maybeThrowError() = Unit
                override fun skipData(positionUs: Long) = 0
                override fun readData(holder: FormatHolder, buffer: DecoderInputBuffer, flags: Int): Int {
                    buffer.timeUs = 10_000_000L + reads * 1_000_000L
                    buffer.ensureSpaceForWrite(1)
                    buffer.data!!.put(0.toByte())
                    reads++
                    return C.RESULT_BUFFER_READ
                }
            }
            val renderer = NativeSubtitleRenderer(TextRenderer(output, null), output)
            renderer.enable(RendererConfiguration.DEFAULT, arrayOf(format), stream,
                0L, false, false, 0L, 0L, MediaSource.MediaPeriodId("test"))
            assertSame(stream, renderer.stream)
            renderer.start()
            repeat(200) { renderer.render(it * 10_000L, 0L) }
            assertEquals(1, reads)
            renderer.render(10_000_000L, 0L)
            while (jobs.isNotEmpty()) jobs.removeAt(0).run()
            assertEquals("bitmap", delivered.last().cues.single().text.toString())
            assertEquals(2, reads)
            renderer.render(10_500_000L, 0L)
            while (jobs.isNotEmpty()) jobs.removeAt(0).run()
            assertTrue(delivered.last().cues.isEmpty())
            assertEquals(2, reads)
            renderer.stop()
            renderer.disable()
            renderer.release()
        }
    }
}
