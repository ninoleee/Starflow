/*
 * Copyright (C) 2018 The Android Open Source Project
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy at https://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software distributed
 * under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * RLE and palette conversion adapted from Media3 1.10.1 PgsParser.
 */
package com.example.starflow

import android.graphics.Bitmap
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.text.Cue
import androidx.media3.common.util.Consumer
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.extractor.text.CuesWithTiming
import androidx.media3.extractor.text.SubtitleParser

internal class BoundedPgsParser : SubtitleParser {
    private data class Image(val version: Int, val width: Int, val height: Int,
        val bytes: ByteArray, var size: Int = 0, var complete: Boolean = false)
    private data class Area(val x: Int, val y: Int, val width: Int, val height: Int)
    private data class Placement(val id: Int, val window: Int, val x: Int, val y: Int, val crop: Area?)
    private val objects = mutableMapOf<Int, Image>()
    private val palettes = mutableMapOf<Int, IntArray>()
    private val windows = mutableMapOf<Int, Area>()
    private val diagnostics = BitmapSubtitleDiagnostics("pgs")
    private var placements: List<Placement>? = null
    private var width = 0
    private var height = 0
    private var paletteId = 0
    internal var cachedBytes = 0
        private set

    override fun getCueReplacementBehavior() = Format.CUE_REPLACEMENT_BEHAVIOR_REPLACE

    override fun reset() {
        objects.clear()
        palettes.clear()
        windows.clear()
        placements = null
        cachedBytes = 0
        width = 0
        height = 0
    }

    override fun parse(data: ByteArray, offset: Int, length: Int,
        outputOptions: SubtitleParser.OutputOptions, output: Consumer<CuesWithTiming>) {
        var result: List<Cue>? = null
        try {
            val input = ParsableByteArray(BitmapSubtitleLimits.sample(data, offset, length))
            while (input.bytesLeft() > 0) {
                require(input.bytesLeft() >= 3) { "truncated segment header" }
                val type = input.readUnsignedByte()
                val size = input.readUnsignedShort()
                require(size <= input.bytesLeft()) { "truncated segment" }
                val section = ParsableByteArray(ByteArray(size))
                input.readBytes(section.data, 0, size)
                when (type) {
                    0x14 -> palette(section)
                    0x15 -> image(section)
                    0x16 -> composition(section)
                    0x17 -> window(section)
                    0x80 -> {
                        require(size == 0) { "invalid END" }
                        require(result == null) { "multiple display sets in one sample" }
                        result = compose()
                        placements = null
                    }
                }
            }
        } catch (e: Exception) {
            diagnostics.drop(e.message ?: e.javaClass.simpleName)
            reset()
            result = emptyList()
        }
        // Container samples have one timestamp, so never emit multiple TIME_UNSET groups.
        result?.let { output.accept(CuesWithTiming(it, C.TIME_UNSET, C.TIME_UNSET)) }
    }

    private fun composition(b: ParsableByteArray) {
        require(b.bytesLeft() >= 11) { "short PCS" }
        val w = b.readUnsignedShort()
        val h = b.readUnsignedShort()
        BitmapSubtitleLimits.checkDimensions(w, h)
        b.skipBytes(3) // frame rate and composition number
        val state = b.readUnsignedByte()
        if (state and 0xc0 != 0) reset()
        width = w
        height = h
        b.skipBytes(1) // palette update flag; partial PDS entries merge below
        paletteId = b.readUnsignedByte()
        val count = b.readUnsignedByte()
        require(count <= 2) { "too many composition objects" }
        placements = List(count) {
            require(b.bytesLeft() >= 8) { "short composition object" }
            val id = b.readUnsignedShort()
            val window = b.readUnsignedByte()
            val flags = b.readUnsignedByte()
            val x = b.readUnsignedShort()
            val y = b.readUnsignedShort()
            val crop = if (flags and 0x80 != 0) readArea(b) else null
            Placement(id, window, x, y, crop)
        }
    }

    private fun readArea(b: ParsableByteArray): Area {
        require(b.bytesLeft() >= 8) { "short rectangle" }
        return Area(b.readUnsignedShort(), b.readUnsignedShort(), b.readUnsignedShort(), b.readUnsignedShort())
    }

    private fun window(b: ParsableByteArray) {
        require(b.bytesLeft() >= 1)
        val count = b.readUnsignedByte()
        require(count <= 2 && b.bytesLeft() == count * 9) { "invalid windows" }
        windows.clear()
        repeat(count) { windows[b.readUnsignedByte()] = readArea(b) }
    }

    private fun palette(b: ParsableByteArray) {
        require(b.bytesLeft() >= 2 && b.bytesLeft() % 5 == 2) { "invalid palette" }
        val id = b.readUnsignedByte()
        b.skipBytes(1) // New versions update entries by index, including alpha-only animations.
        require(id in palettes || palettes.size < 8) { "palette cache full" }
        val colors = palettes.getOrPut(id) { IntArray(256) }
        while (b.bytesLeft() > 0) {
            val index = b.readUnsignedByte()
            val y = b.readUnsignedByte()
            val cr = b.readUnsignedByte() - 128
            val cb = b.readUnsignedByte() - 128
            val a = b.readUnsignedByte()
            val r = (y + 1.402 * cr).toInt().coerceIn(0, 255)
            val g = (y - 0.34414 * cb - 0.71414 * cr).toInt().coerceIn(0, 255)
            val blue = (y + 1.772 * cb).toInt().coerceIn(0, 255)
            colors[index] = (a shl 24) or (r shl 16) or (g shl 8) or blue
        }
    }

    private fun image(b: ParsableByteArray) {
        require(b.bytesLeft() >= 4) { "short ODS" }
        val id = b.readUnsignedShort()
        val version = b.readUnsignedByte()
        val flags = b.readUnsignedByte()
        if (flags and 0x80 != 0) {
            require(b.bytesLeft() >= 7) { "short first ODS" }
            val size = b.readUnsignedInt24() - 4
            val w = b.readUnsignedShort()
            val h = b.readUnsignedShort()
            BitmapSubtitleLimits.checkDimensions(w, h)
            require(size in 1..BitmapSubtitleLimits.MAX_SAMPLE_BYTES) { "object exceeds budget" }
            val retained = cachedBytes - (objects[id]?.bytes?.size ?: 0)
            require(retained + size <= BitmapSubtitleLimits.MAX_CACHE_BYTES &&
                (id in objects || objects.size < 64)) { "object cache full" }
            objects[id] = Image(version, w, h, ByteArray(size))
            cachedBytes = retained + size
        }
        val image = requireNotNull(objects[id]) { "orphan ODS fragment" }
        require(image.version == version && !image.complete) { "ODS version or sequence mismatch" }
        val count = b.bytesLeft()
        require(count <= image.bytes.size - image.size) { "ODS overflow" }
        b.readBytes(image.bytes, image.size, count)
        image.size += count
        if (flags and 0x40 != 0) {
            require(image.size == image.bytes.size) { "incomplete ODS" }
            image.complete = true
        }
    }

    private fun compose(): List<Cue> {
        val startNs = System.nanoTime()
        val refs = requireNotNull(placements) { "END without PCS" }
        if (refs.isEmpty()) return emptyList()
        val colors = requireNotNull(palettes[paletteId]) { "missing palette" }
        var pixels = 0L
        refs.forEach {
            val image = requireNotNull(objects[it.id]) { "missing object" }
            require(image.complete) { "incomplete object" }
            pixels += image.width.toLong() * image.height
        }
        require(pixels <= BitmapSubtitleLimits.MAX_PIXELS) { "composition exceeds pixel budget" }
        val cues = refs.mapNotNull { ref ->
            val image = objects.getValue(ref.id)
            val crop = ref.crop ?: Area(0, 0, image.width, image.height)
            require(crop.width > 0 && crop.height > 0 && crop.x + crop.width <= image.width &&
                crop.y + crop.height <= image.height) { "invalid crop" }
            val window = windows[ref.window] ?: Area(0, 0, width, height)
            val left = maxOf(ref.x, window.x)
            val top = maxOf(ref.y, window.y)
            val right = minOf(ref.x + crop.width, window.x + window.width, width)
            val bottom = minOf(ref.y + crop.height, window.y + window.height, height)
            if (right <= left || bottom <= top) return@mapNotNull null
            val argb = decode(image, colors)
            val bitmap = Bitmap.createBitmap(argb,
                (crop.y + top - ref.y) * image.width + crop.x + left - ref.x,
                image.width, right - left, bottom - top, Bitmap.Config.ARGB_8888)
            Cue.Builder().setBitmap(bitmap)
                .setPosition(left.toFloat() / width).setPositionAnchor(Cue.ANCHOR_TYPE_START)
                .setLine(top.toFloat() / height, Cue.LINE_TYPE_FRACTION).setLineAnchor(Cue.ANCHOR_TYPE_START)
                .setSize((right - left).toFloat() / width)
                .setBitmapHeight((bottom - top).toFloat() / height).build()
        }
        diagnostics.decoded(startNs, pixels, cachedBytes)
        return cues
    }

    private fun decode(image: Image, colors: IntArray): IntArray {
        val input = ParsableByteArray(image.bytes)
        val pixels = IntArray(image.width * image.height)
        var x = 0
        var y = 0
        while (y < image.height) {
            // A final full row without EOL is accepted, matching Media3/container samples.
            if (y == image.height - 1 && x == image.width && input.bytesLeft() == 0) break
            require(input.bytesLeft() > 0) { "truncated RLE" }
            var color = input.readUnsignedByte()
            var run = 1
            if (color == 0) {
                require(input.bytesLeft() > 0) { "truncated RLE control" }
                val control = input.readUnsignedByte()
                if (control == 0) {
                    y++
                    x = 0
                    continue
                }
                run = control and 0x3f
                if (control and 0x40 != 0) run = (run shl 8) or input.readUnsignedByte()
                if (control and 0x80 != 0) color = input.readUnsignedByte()
            }
            require(run > 0 && run <= image.width - x) { "RLE crosses row or makes no progress" }
            pixels.fill(colors[color], y * image.width + x, y * image.width + x + run)
            x += run
        }
        return pixels
    }
}
