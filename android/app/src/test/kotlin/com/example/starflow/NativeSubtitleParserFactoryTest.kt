package com.example.starflow

import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.text.SubtitleParser
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class NativeSubtitleParserFactoryTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()

    @Test fun factoriesUseBoundedParsers() {
        val factory = NativeSubtitleParserFactory()
        assertTrue(factory.create(Format.Builder().setSampleMimeType(MimeTypes.APPLICATION_PGS).build()) is BoundedPgsParser)
        assertTrue(factory.create(Format.Builder().setSampleMimeType(MimeTypes.APPLICATION_VOBSUB).build()) is BoundedVobsubParser)
    }

    @Test fun extractorResetIsIsolatedEvenWhenFormatIdsMatch() {
        val first = mock(Extractor::class.java)
        val second = mock(Extractor::class.java)
        val firstParser = mock(SubtitleParser::class.java)
        val secondParser = mock(SubtitleParser::class.java)
        val factory = mock(SubtitleParser.Factory::class.java)
        `when`(factory.create(any())).thenReturn(firstParser, secondParser)
        var scoped: SubtitleParser.Factory? = null
        mockConstruction(DefaultExtractorsFactory::class.java) { instance, _ ->
            `when`(instance.setSubtitleParserFactory(any())).thenAnswer {
                scoped = it.getArgument(0)
                instance
            }
            `when`(instance.createExtractors()).thenReturn(arrayOf(first, second))
        }.use {
            val extractors = NativePlaybackExtractorsFactory().setSubtitleParserFactory(factory).createExtractors()
            val format = Format.Builder().setId("same-id").setSampleMimeType(MimeTypes.APPLICATION_PGS).build()
            for (extractor in listOf(first, second)) {
                doAnswer { scoped!!.create(format); null }.`when`(extractor).init(any())
            }
            val output = mock(ExtractorOutput::class.java)
            extractors[0].init(output)
            extractors[1].init(output)
            extractors[0].seek(0, 0)
            verify(firstParser).reset()
            verifyNoInteractions(secondParser)
            extractors[1].release()
            verify(secondParser).reset()
            verify(second).release()
        }
    }
}
