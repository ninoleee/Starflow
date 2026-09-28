package com.example.starflow

import android.content.pm.ApplicationInfo
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaybackMemoryClassTest {
    private val mib = 1024L * 1024

    @Test
    fun runtimeHeapDeterminesClass() {
        for (memory in listOf(128, 192, 256, 257, 512, 513, 1024)) {
            assertEquals(memory, PlaybackMemoryClass.resolve(memory * mib))
        }
    }

    @Test
    fun runtimeHeapUsesPercentageBudget() {
        val memory = PlaybackMemoryClass.resolve(512 * mib)
        assertEquals(512, memory)
        assertEquals(192 * mib, NativePlaybackBufferBudget.limit(memory).toLong())
        assertEquals(192 * mib,
            NativePlaybackBufferPolicy.resolve(true, memory, false).targetBufferBytes.toLong())
    }

    @Test
    fun reportedClassesAndRequestFlagDoNotOverrideRuntimeHeap() {
        for (flags in listOf(0, ApplicationInfo.FLAG_LARGE_HEAP)) {
            for (reported in listOf(-1, 0, 256, 512, 1024)) {
                val fields = PlaybackMemoryClass.diagnosticFields(flags,
                    reported, reported, 512 * mib)
                assertEquals(512, fields["effectiveMemoryClassMb"])
                assertEquals(reported, fields["normalMemoryClassMb"])
                assertEquals(reported, fields["largeMemoryClassMb"])
            }
        }
    }

    @Test
    fun runtimeHeapIsRoundedDownAtTierBoundaries() {
        for (memory in listOf(256, 512)) {
            assertEquals(memory, PlaybackMemoryClass.resolve((memory + 1) * mib - 1))
            assertEquals(memory + 1, PlaybackMemoryClass.resolve((memory + 1) * mib))
        }
    }

    @Test
    fun invalidOrSubMibRuntimeHeapStaysConservativeAndLargeValuesDoNotOverflow() {
        for (bytes in listOf(Long.MIN_VALUE, -mib, -1L, 0L, 1L, mib - 1)) {
            assertEquals(1, PlaybackMemoryClass.resolve(bytes))
        }
        assertEquals(Int.MAX_VALUE, PlaybackMemoryClass.resolve(Long.MAX_VALUE))
    }

    @Test
    fun diagnosticFieldsDistinguishRequestedReportedAndEffectiveHeap() {
        assertEquals(mapOf(
            "largeHeapRequested" to true,
            "normalMemoryClassMb" to 256,
            "largeMemoryClassMb" to 1024,
            "runtimeMaxHeapBytes" to 512 * mib,
            "runtimeMaxHeapMiB" to 512L,
            "effectiveMemoryClassMb" to 512,
        ), PlaybackMemoryClass.diagnosticFields(ApplicationInfo.FLAG_LARGE_HEAP,
            256, 1024, 512 * mib))
    }

    @Test
    fun diagnosticFieldsKeepRawValuesWithoutLimitingEffectiveClass() {
        val ordinary = PlaybackMemoryClass.diagnosticFields(0, 256, 512, 512 * mib)
        assertEquals(false, ordinary["largeHeapRequested"])
        assertEquals(512, ordinary["effectiveMemoryClassMb"])
        val invalid = PlaybackMemoryClass.diagnosticFields(ApplicationInfo.FLAG_LARGE_HEAP,
            256, 0, 0)
        assertEquals(0L, invalid["runtimeMaxHeapBytes"])
        assertEquals(0L, invalid["runtimeMaxHeapMiB"])
        assertEquals(1, invalid["effectiveMemoryClassMb"])
    }

    @Test
    fun manifestRequestsLargeHeapAndBothPlaybackEntrypointsUseSharedReader() {
        val manifest = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(File("src/main/AndroidManifest.xml"))
        val application = manifest.getElementsByTagName("application").item(0)
        assertEquals("true", application.attributes.getNamedItemNS(
            "http://schemas.android.com/apk/res/android", "largeHeap").nodeValue)
        val source = File("src/main/kotlin/com/example/starflow")
        assertTrue(File(source, "MainActivity.kt").readText()
            .contains("result.success(PlaybackMemoryClass.read(this))"))
        assertTrue(File(source, "NativePlaybackSession.kt").readText()
            .contains("val memoryClassMb = PlaybackMemoryClass.read(host.activity)"))
    }
}
