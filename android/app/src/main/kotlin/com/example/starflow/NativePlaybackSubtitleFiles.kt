package com.example.starflow

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import java.io.File
import java.nio.charset.StandardCharsets

internal class NativePlaybackSubtitleFiles(private val context: Context) {
    fun buildSubtitleConfiguration(
        source: ExternalSubtitleSource,
        delayMs: Long,
    ): MediaItem.SubtitleConfiguration {
        val effectiveUri =
            if (delayMs == 0L) {
                source.originalUri
            } else {
                buildShiftedSubtitleFile(source, delayMs)
            }
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
        val subtitleDirectory = File(context.cacheDir, "native_subtitles").apply { mkdirs() }
        val extension = resolveSubtitleExtension(source)
        val outputFile =
            File(
                subtitleDirectory,
                "shifted_${source.displayName.hashCode()}_${delayMs}.$extension",
            )
        val originalContent =
            openSubtitleInputStream(source.originalUri)
                ?.bufferedReader(StandardCharsets.UTF_8)
                ?.use { it.readText() } ?: throw IllegalStateException("字幕文件读取失败")
        val shiftedContent =
            NativeSubtitleTiming.shiftSubtitleContent(
                content = originalContent,
                mimeType = source.mimeType,
                delayMs = delayMs,
            )
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
