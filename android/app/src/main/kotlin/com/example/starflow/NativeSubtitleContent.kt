package com.example.starflow

import java.nio.ByteBuffer
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

internal object NativeSubtitleContent {
    const val MAX_BYTES = 16 * 1024 * 1024

    fun decode(bytes: ByteArray): String {
        require(bytes.size <= MAX_BYTES) { "字幕超过 16 MiB 限制" }
        fun has(a: Int, b: Int) = bytes.size >= 2 &&
            bytes[0].toInt() and 255 == a && bytes[1].toInt() and 255 == b
        val text = when {
            has(0xff, 0xfe) -> String(bytes, 2, bytes.size - 2, Charsets.UTF_16LE)
            has(0xfe, 0xff) -> String(bytes, 2, bytes.size - 2, Charsets.UTF_16BE)
            else -> try {
                Charsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes)).toString()
            } catch (_: java.nio.charset.CharacterCodingException) {
                Charset.forName("GB18030").newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes)).toString()
            }
        }.removePrefix("\uFEFF")
        require(!text.contains('\u0000') &&
            !Regex("<(?:!doctype|html)\\b", RegexOption.IGNORE_CASE).containsMatchIn(text)) {
            "不是有效文本字幕"
        }
        require(Regex("^WEBVTT(?:\\s|$)").containsMatchIn(text.trimStart()) ||
            (Regex("^\\[Events\\]\\s*$", setOf(RegexOption.MULTILINE, RegexOption.IGNORE_CASE))
                .containsMatchIn(text) && Regex("^Dialogue\\s*:", setOf(RegexOption.MULTILINE, RegexOption.IGNORE_CASE))
                .containsMatchIn(text)) ||
            Regex("\\d{1,3}:\\d{2}:\\d{2}[,.]\\d{3}\\s*-->\\s*\\d{1,3}:\\d{2}:\\d{2}[,.]\\d{3}")
                .containsMatchIn(text)) { "未识别到有效字幕时间轴" }
        return text
    }
}
