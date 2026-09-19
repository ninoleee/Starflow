package com.example.starflow

import java.nio.charset.Charset
import org.junit.Assert.assertEquals
import org.junit.Test

class NativeSubtitleContentTest {
    private val text = "1\n00:00:01,000 --> 00:00:02,000\n中文字幕"

    @Test fun decodesUtf8Utf16AndGbk() {
        assertEquals(text, NativeSubtitleContent.decode(text.toByteArray(Charsets.UTF_8)))
        assertEquals(text, NativeSubtitleContent.decode(text.toByteArray(Charsets.UTF_16)))
        assertEquals(text, NativeSubtitleContent.decode(text.toByteArray(Charset.forName("GBK"))))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsHtml() { NativeSubtitleContent.decode("<html>login</html>".toByteArray()) }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsLargeContent() { NativeSubtitleContent.decode(ByteArray(NativeSubtitleContent.MAX_BYTES + 1)) }
}
