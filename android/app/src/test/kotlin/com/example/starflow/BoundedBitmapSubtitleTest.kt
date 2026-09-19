package com.example.starflow

import android.graphics.Bitmap
import android.graphics.Rect
import androidx.media3.extractor.text.CuesWithTiming
import androidx.media3.extractor.text.SubtitleParser
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class BoundedBitmapSubtitleTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()
    private fun bytes(vararg values: Int) = values.map { it.toByte() }.toByteArray()
    private fun segment(type: Int, body: ByteArray) = bytes(type, body.size shr 8, body.size) + body
    private fun pcs(state: Int = 0x80, count: Int = 1, crop: Boolean = false): ByteArray {
        val header = bytes(7, 128, 4, 56, 0, 0, 0, state, 0, 0, count)
        val first = bytes(0, 0, 0, if (crop) 128 else 0, 0, 100, 0, 200) +
            if (crop) bytes(0, 1, 0, 0, 0, 1, 0, 1) else byteArrayOf()
        return segment(0x16, header + (if (count > 0) first else byteArrayOf()) +
            if (count > 1) bytes(0, 1, 0, 0, 2, 88, 2, 188) else byteArrayOf())
    }
    private val palette = segment(0x14, bytes(0, 0, 1, 235, 128, 128, 255))
    private val end = segment(0x80, byteArrayOf())
    private fun image(id: Int = 0, width: Int = 1, height: Int = 1, rle: ByteArray = bytes(1)) =
        segment(0x15, bytes(0, id, 0, 192, 0, 0, rle.size + 4,
            width shr 8, width, height shr 8, height) + rle)
    private fun parse(parser: SubtitleParser, sample: ByteArray): List<CuesWithTiming> {
        val result = mutableListOf<CuesWithTiming>()
        parser.parse(sample, SubtitleParser.OutputOptions.allCues()) { result += it }
        return result
    }

    private fun withBitmaps(action: () -> Unit) {
        mockStatic(Bitmap::class.java).use { bitmap ->
            bitmap.`when`<Bitmap> { Bitmap.createBitmap(any(IntArray::class.java), anyInt(), anyInt(),
                anyInt(), anyInt(), eq(Bitmap.Config.ARGB_8888)) }.thenReturn(mock(Bitmap::class.java))
            action()
        }
    }

    @Test fun reusesObjectsAndPalettesUntilResetOrEpoch() = withBitmaps {
        val parser = BoundedPgsParser()
        assertEquals(1, parse(parser, pcs() + palette + image() + end).single().cues.size)
        assertEquals(1, parse(parser, pcs(0) + end).single().cues.size)
        assertEquals(1, parser.cachedBytes)
        assertTrue(parse(parser, pcs(0x40) + end).single().cues.isEmpty())
        parse(parser, pcs() + palette + image() + end)
        parser.reset()
        assertEquals(0, parser.cachedBytes)
        assertTrue(parse(parser, pcs(0) + end).single().cues.isEmpty())
    }

    @Test fun composesMultipleObjectsAndCrops() = withBitmaps {
        val parser = BoundedPgsParser()
        val cues = parse(parser, pcs(count = 2) + palette + image() + image(1) + end).single().cues
        assertEquals(2, cues.size)
        assertEquals(100f / 1920, cues[0].position, 0.0001f)
        assertEquals(600f / 1920, cues[1].position, 0.0001f)
        val crop = parse(parser, pcs(crop = true) + palette + image(width = 2, rle = bytes(1, 1)) + end)
            .single().cues.single()
        assertEquals(1f / 1920, crop.size, 0.0001f)
        assertTrue(parse(parser, pcs(state = 0, count = 0) + end).single().cues.isEmpty())
    }

    @Test fun fragmentedObjectsAndNonzeroInputOffsetsWork() = withBitmaps {
        val parser = BoundedPgsParser()
        val first = segment(0x15, bytes(0, 0, 2, 128, 0, 0, 6, 0, 2, 0, 1, 1))
        val last = segment(0x15, bytes(0, 0, 2, 64, 1))
        assertTrue(parse(parser, pcs() + palette + first).isEmpty())
        assertEquals(1, parse(parser, last + end).single().cues.size)
        val sample = pcs(0) + end
        var cues: CuesWithTiming? = null
        parser.parse(bytes(99, 99) + sample, 2, sample.size, SubtitleParser.OutputOptions.allCues()) { cues = it }
        assertEquals(1, cues!!.cues.size)
    }

    @Test fun oversizedDimensionsAndMalformedRleAreDroppedBeforeBitmapAllocation() {
        val parser = BoundedPgsParser()
        for (objectData in listOf(image(width = 20000, height = 20000), image(rle = bytes(0)),
            image(rle = bytes(0, 0x82, 1)), image(rle = bytes(0, 0x80, 1)))) {
            assertTrue(parse(parser, pcs() + palette + objectData + end).single().cues.isEmpty())
            assertEquals(0, parser.cachedBytes)
        }
    }

    @Test(timeout = 3000) fun vobsubExhaustedRleAndCyclicControlsTerminate() {
        val parser = BoundedVobsubParser(listOf("size: 720x480\npalette: 000000,ffffff,888888,444444\n".toByteArray()))
        val sample = bytes(0,28,0,4, 0,0,0,4, 1, 3,0,0, 4,255,255,
            5,0,0,1,0,0,1, 6,0,28,0,28,255)
        assertTrue(parse(parser, sample).single().cues.isEmpty())
        assertTrue(parse(parser, bytes(0,14,0,4, 0,0,0,9,255, 0,0,0,4,255)).single().cues.isEmpty())
    }

    @Test(timeout = 3000) fun vobsubRunTruncationCannotSpinOrReadControlBytesAsPixels() {
        mockConstruction(Rect::class.java) { rect, _ ->
            `when`(rect.width()).thenReturn(2)
            `when`(rect.height()).thenReturn(2)
        }.use {
            val parser = BoundedVobsubParser(listOf("size: 720x480\npalette: 000000,ffffff,888888,444444\n".toByteArray()))
            val sample = bytes(0,29,0,5, 0, 0,0,0,5, 1, 3,0,0, 4,255,255,
                5,0,0,1,0,0,1, 6,0,4,0,4,255)
            assertTrue(parse(parser, sample).single().cues.isEmpty())
        }
    }

    @Test fun zlibExpansionIsBounded() {
        val compressed = java.io.ByteArrayOutputStream()
        java.util.zip.DeflaterOutputStream(compressed).use { it.write(ByteArray(BitmapSubtitleLimits.MAX_SAMPLE_BYTES + 1)) }
        assertTrue(parse(BoundedPgsParser(), compressed.toByteArray()).single().cues.isEmpty())
    }

    @Test fun dvbRejectsLargeDisplayBeforeDecodeAndSlicesOffsets() {
        val delegates = mutableListOf<SubtitleParser>()
        val parser = BoundedDvbParser { mock(SubtitleParser::class.java).also { delegates += it } }
        val tooLarge = bytes(15, 0x14, 0, 1, 0, 5, 0, 255, 255, 255, 255)
        assertTrue(parse(parser, tooLarge).single().cues.isEmpty())
        verifyNoInteractions(delegates.first())
        val original = delegates.last()
        parser.parse(bytes(99, 99, 0), 2, 1, SubtitleParser.OutputOptions.allCues()) {}
        verify(original).parse(eq(bytes(0)), eq(0), eq(1), any(), any())
        parser.reset()
        assertNotSame(original, delegates.last())
    }

    @Test fun objectVersionsAndPaletteUpdatesDoNotLeakAcrossEpochs() = withBitmaps {
        val parser = BoundedPgsParser()
        parse(parser, pcs() + palette + image() + end)
        val update = segment(0x14, bytes(0, 1, 1, 235, 128, 128, 128))
        assertEquals(1, parse(parser, pcs(0) + update + end).single().cues.size)
        val fragment = segment(0x15, bytes(0, 0, 9, 64, 1))
        assertTrue(parse(parser, pcs(0) + fragment + end).single().cues.isEmpty())
        assertEquals(0, parser.cachedBytes)
    }

    @Test fun validVobsubStillDecodesBothInterlacedRows() {
        mockConstruction(Rect::class.java) { rect, _ ->
            `when`(rect.width()).thenReturn(2)
            `when`(rect.height()).thenReturn(2)
        }.use {
            mockStatic(Bitmap::class.java).use { bitmap ->
                bitmap.`when`<Bitmap> { Bitmap.createBitmap(any(IntArray::class.java), eq(2), eq(2),
                    eq(Bitmap.Config.ARGB_8888)) }.thenAnswer {
                    assertArrayEquals(intArrayOf(-16777216, -16777216, -16777216, -16777216),
                        it.getArgument<IntArray>(0))
                    mock(Bitmap::class.java)
                }
                val parser = BoundedVobsubParser(listOf("size: 720x480\npalette: 000000,ffffff,888888,444444\n".toByteArray()))
                val sample = bytes(0,30,0,6, 0x90,0x90, 0,0,0,6, 1, 3,0,0, 4,255,255,
                    5,0,0,1,0,0,1, 6,0,4,0,5,255)
                assertEquals(1, parse(parser, sample).single().cues.size)
            }
        }
    }

    @Test fun incompleteObjectCacheCannotGrowBeyondBudget() {
        val parser = BoundedPgsParser()
        fun large(id: Int) = segment(0x15, bytes(0,id,0,128, 0x40,0,4, 0,1,0,1))
        assertTrue(parse(parser, pcs() + large(0) + large(1)).isEmpty())
        assertEquals(BitmapSubtitleLimits.MAX_CACHE_BYTES, parser.cachedBytes)
        assertTrue(parse(parser, large(2)).single().cues.isEmpty())
        assertEquals(0, parser.cachedBytes)
    }
}
