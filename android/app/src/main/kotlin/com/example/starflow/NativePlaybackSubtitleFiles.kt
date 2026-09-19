package com.example.starflow

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import java.io.File
import java.nio.charset.StandardCharsets
import java.io.RandomAccessFile
import java.nio.channels.FileLock

internal class NativePlaybackSubtitleFiles(private val context: Context) {
    private var leaseFile: RandomAccessFile? = null
    private var lease: FileLock? = null
    private val directory by lazy {
        val root = File(context.cacheDir, "playback_subtitles").apply { mkdirs() }
        val cutoff = System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000
        root.listFiles()?.filter { it.isDirectory && it.lastModified() < cutoff }?.forEach { old ->
            runCatching {
                RandomAccessFile(File(old, ".lease"), "rw").use { file ->
                    file.channel.tryLock()?.use { old.deleteRecursively() }
                }
            }
        }
        File.createTempFile("session-", ".dir", root).apply {
            delete()
            mkdirs()
            leaseFile = RandomAccessFile(File(this, ".lease"), "rw")
            lease = leaseFile!!.channel.lock()
        }
    }
    private var cachedSource: Uri? = null
    private var cachedText: String? = null

    fun close() {
        cachedSource = null
        cachedText = null
        directory.deleteRecursively()
        lease?.release()
        leaseFile?.close()
        lease = null
        leaseFile = null
    }

    fun deletePrepared(uri: Uri?) {
        val path = uri?.path ?: return
        val file = File(path)
        if (file.parentFile == directory) file.delete()
    }
    fun buildSubtitleConfiguration(
        source: ExternalSubtitleSource,
        delayMs: Long,
    ): MediaItem.SubtitleConfiguration {
        val effectiveUri = buildShiftedSubtitleFile(source, delayMs)
        return MediaItem.SubtitleConfiguration.Builder(effectiveUri)
            .setMimeType(source.mimeType)
            .setLanguage(C.LANGUAGE_UNDETERMINED)
            .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
            .setLabel(
                if (delayMs == 0L) {
                    source.displayName
                } else {
                    "${source.displayName} (${NativePlaybackFormatting.formatSubtitleDelayLabel(delayMs)})"
                }
            )
            .setId("external:${source.originalUri}:$delayMs")
            .build()
    }

    private fun buildShiftedSubtitleFile(source: ExternalSubtitleSource, delayMs: Long): Uri {
        val extension = resolveSubtitleExtension(source)
        val originalContent = if (cachedSource == source.originalUri && cachedText != null) {
            cachedText!!
        } else {
            val bytes = openSubtitleInputStream(source.originalUri)?.use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    require(output.size() + count <= NativeSubtitleContent.MAX_BYTES) { "字幕文件过大" }
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            } ?: throw IllegalStateException("字幕文件读取失败")
            NativeSubtitleContent.decode(bytes).also {
                cachedSource = source.originalUri
                cachedText = it
            }
        }
        val shiftedContent =
            NativeSubtitleTiming.shiftSubtitleContent(
                content = originalContent,
                mimeType = source.mimeType,
                delayMs = delayMs,
            )
        val outputFile = File.createTempFile("subtitle-", ".$extension", directory)
        outputFile.writeText(shiftedContent, StandardCharsets.UTF_8)
        return Uri.fromFile(outputFile)
    }

    private fun openSubtitleInputStream(uri: Uri) =
        when (uri.scheme?.lowercase()) {
            "file" -> {
                val path = uri.path?.trim().orEmpty()
                if (path.isEmpty()) {
                    null
                } else {
                    File(path).inputStream()
                }
            }

            else -> context.contentResolver.openInputStream(uri)
        }

    fun resolveSubtitleMimeType(uri: Uri): String? {
        val fromResolver =
            context.contentResolver.getType(uri)?.let { candidate ->
                when (candidate.lowercase()) {
                    "application/x-subrip" -> MimeTypes.APPLICATION_SUBRIP
                    "text/vtt" -> MimeTypes.TEXT_VTT
                    "text/x-ssa",
                    "application/ssa",
                    "application/ass",
                    "text/x-ass" -> MimeTypes.TEXT_SSA
                    else -> null
                }
            }
        if (fromResolver != null) {
            return fromResolver
        }

        val name = resolveDisplayName(uri).lowercase()
        return when {
            name.endsWith(".srt") -> MimeTypes.APPLICATION_SUBRIP
            name.endsWith(".vtt") -> MimeTypes.TEXT_VTT
            name.endsWith(".ass") || name.endsWith(".ssa") -> MimeTypes.TEXT_SSA
            else -> null
        }
    }

    private fun resolveSubtitleExtension(source: ExternalSubtitleSource): String {
        return when (source.mimeType) {
            MimeTypes.APPLICATION_SUBRIP -> "srt"
            MimeTypes.TEXT_VTT -> "vtt"
            MimeTypes.TEXT_SSA -> "ass"
            else -> "srt"
        }
    }

    fun resolveDisplayName(uri: Uri): String {
        if (uri.scheme?.lowercase() == "file") {
            val fileName = uri.path?.let { path -> File(path).name }.orEmpty()
            if (fileName.isNotBlank()) {
                return fileName
            }
        }
        var result = uri.lastPathSegment ?: "外挂字幕"
        try {
            context.contentResolver
                .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0 && cursor.moveToFirst()) {
                        result = cursor.getString(index) ?: result
                    }
                }
        } catch (_: Throwable) {}
        return result
    }
}
